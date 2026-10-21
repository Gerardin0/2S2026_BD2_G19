#!/usr/bin/env bash
# cargar_todo.sh — Regenera la base `olimpiadas` desde cero (Fase 3).
#
#   1. Levanta (o reutiliza) el contenedor `mongodb_olimpiadas` (mongo:9.0.4, admin/admin123)
#   2. Crea colecciones, validadores e índices   (ddl/crear_colecciones_indices.py)
#   3. Ejecuta el ETL dentro de un contenedor python:3.12-slim (carga/cargar_mongo.py)
#
# Se corre el ETL en Docker para no depender de pandas/numpy locales (en Windows con
# Control de aplicaciones la DLL de numpy puede estar bloqueada).
#
# Uso (Git Bash o Linux, desde cualquier carpeta):
#   bash "Proyecto Fase 3/carga/cargar_todo.sh"            # carga idempotente sobre la base actual
#   bash "Proyecto Fase 3/carga/cargar_todo.sh" --limpio   # borra la base y la carga de cero
set -euo pipefail

FASE3="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$FASE3/.." && (pwd -W 2>/dev/null || pwd))"   # pwd -W: ruta Windows en Git Bash
CONTENEDOR=mongodb_olimpiadas
URI="mongodb://admin:admin123@localhost:27017/"
export MSYS_NO_PATHCONV=1   # Git Bash: no convertir rutas de los argumentos de docker

mongosh_c() { docker exec "$CONTENEDOR" mongosh -u admin -p admin123 --authenticationDatabase admin --quiet olimpiadas --eval "$1"; }

if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTENEDOR"; then
  echo "[$(date '+%F %T')] Creando contenedor $CONTENEDOR"
  docker run -d --name "$CONTENEDOR" -p 27017:27017 \
    -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=admin123 \
    -v mongodata_olimpiadas:/data/db mongo:9.0.4 >/dev/null
else
  docker start "$CONTENEDOR" >/dev/null
fi
until mongosh_c 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; do sleep 1; done
echo "[$(date '+%F %T')] MongoDB $(mongosh_c 'db.version()') listo en localhost:27017"

if [[ "${1:-}" == "--limpio" ]]; then
  echo "[$(date '+%F %T')] Eliminando base olimpiadas"
  mongosh_c 'db.dropDatabase()' >/dev/null
fi

PY=python3; python3 -c 'import pymongo' 2>/dev/null || PY=python
cd "$FASE3"
PYTHONIOENCODING=utf-8 "$PY" ddl/crear_colecciones_indices.py --uri "$URI"

docker run --rm -e TZ=CST6 --network "container:$CONTENEDOR" \
  -v "$REPO:/repo" -w "/repo/Proyecto Fase 3" python:3.12-slim \
  sh -c "pip install -q --root-user-action=ignore pandas pymongo && python carga/cargar_mongo.py --uri '$URI'"
