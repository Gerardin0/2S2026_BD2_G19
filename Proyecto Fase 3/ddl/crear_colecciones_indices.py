#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
crear_colecciones_indices.py — Proyecto Fase 2026, Fase 3 (MongoDB)

Crea (de forma idempotente) las 5 colecciones del modelo NoSQL de las Olimpiadas
y todos sus índices, replicando el modelo ya cargado en la base `olimpiadas`:

    atletas       153,325 docs — 1 doc por atleta con sus participaciones,
                                  resultados, medallas y roles embebidos
    paises          234 docs — 1 doc por código NOC con participaciones,
                                  medallero, poblaciones y ediciones como sede
    disciplinas   2,087 docs — catálogo deporte + evento
    ediciones        63 docs — una edición de Juegos (año + temporada)
    roles            11 docs — catálogo de roles del atleta

Uso típico (desde la carpeta `Proyecto Fase 3`):

    python3 ddl/crear_colecciones_indices.py                       # crea lo que falte
    python3 ddl/crear_colecciones_indices.py --uri mongodb://localhost:27017 --base olimpiadas
    python3 ddl/crear_colecciones_indices.py --solo-indices        # no toca colecciones
    python3 ddl/crear_colecciones_indices.py --collmod             # aplica validadores a colecciones ya existentes
    python3 ddl/crear_colecciones_indices.py --extras              # agrega índices compuestos extra (ver nota)
    python3 ddl/crear_colecciones_indices.py --reporte             # solo lectura: estado de colecciones/índices

Requisitos:  pip install pymongo   (se probó con pymongo 4.19 / MongoDB 7.x local)

Notas de diseño
---------------
* Idempotente: volver a ejecutar no duplica nada. `create_index` con la misma
  clave/nombre es un no-op; si un índice homónimo tiene opciones distintas se
  reporta el error y se indica cómo eliminarlo.
* La ejecución queda registrada con fecha y hora en `docs/logs/`.
* Los validadores `$jsonSchema` son deliberadamente tolerantes: solo fijan los
  campos que el 100 % de los documentos actuales ya cumple, para no romper la
  carga existente ni las correcciones pendientes (poblaciones ISO-3, ciudades
  de ediciones, etc.). Con `--collmod` se re-validan colecciones existentes con
  `validationLevel: moderate`, es decir, solo documentos nuevos o modificados.
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

try:
    from pymongo import MongoClient
    from pymongo.errors import OperationFailure, PyMongoError
except ImportError:  # pragma: no cover
    sys.exit("Falta pymongo. Instalar con:  pip install pymongo")

# --------------------------------------------------------------------------
# MODELO: colecciones, validadores e índices
# --------------------------------------------------------------------------
# Nota sobre índices multikey: `participaciones` es un array, por lo que Mongo
# NO permite índices compuestos con dos campos dentro del mismo array (parallel
# arrays). Por eso los índices sobre participaciones son de un solo campo; el
# cruce deporte/año/país/medalla se resuelve combinando el índice del campo
# embebido con el filtro de la consulta.

COLECCIONES = {
    "atletas": {
        "descripcion": "Atleta con sus participaciones, resultados y medallas embebidos.",
        "validador": {
            "$jsonSchema": {
                "bsonType": "object",
                "required": ["_id", "nombre_completo", "busqueda_nombre", "roles", "participaciones"],
                "properties": {
                    "_id": {"bsonType": "int", "description": "athlete_id de la fuente (bios/olympics)"},
                    "source_athlete_id": {"bsonType": ["string", "null"]},
                    "nombre_completo": {"bsonType": "string"},
                    "nombre_uso": {"bsonType": ["string", "null"]},
                    "busqueda_nombre": {"bsonType": "string", "description": "nombre(s) en minúsculas para búsqueda"},
                    "sexo": {"enum": ["Male", "Female", None]},
                    "noc_code": {"bsonType": ["string", "null"], "description": "NOC más frecuente de sus participaciones"},
                    "roles": {"bsonType": "array", "items": {"bsonType": "string"}},
                    "participaciones": {
                        "bsonType": "array",
                        "items": {
                            "bsonType": "object",
                            "required": ["id_participacion", "id_edicion", "id_disciplina", "anio", "deporte", "evento"],
                        },
                    },
                },
            }
        },
        "indices": [
            {"key": [("busqueda_nombre", 1)], "name": "ix_atletas_busqueda"},
            {
                "key": [("busqueda_nombre", "text")],
                "name": "tx_atletas_nombre",
                "weights": {"busqueda_nombre": 1},
                "default_language": "spanish",
            },
            {"key": [("noc_code", 1)], "name": "ix_atletas_noc"},
            {"key": [("participaciones.anio", 1)], "name": "ix_atletas_part_anio"},
            {"key": [("participaciones.deporte", 1)], "name": "ix_atletas_part_deporte"},
            {"key": [("participaciones.pais", 1)], "name": "ix_atletas_part_pais"},
            {"key": [("participaciones.medalla", 1)], "name": "ix_atletas_part_medalla"},
        ],
        "indices_extras": [
            # país + año en el mismo índice (legal: un campo escalar + uno de array)
            {"key": [("noc_code", 1), ("participaciones.anio", 1)], "name": "ix_atletas_noc_anio"},
        ],
    },
    "paises": {
        "descripcion": "País (NOC) con participaciones, medallero, población y ediciones como sede.",
        "validador": {
            "$jsonSchema": {
                "bsonType": "object",
                "required": ["_id", "resumen", "medallero", "participaciones", "poblaciones", "ediciones_sede"],
                "properties": {
                    "_id": {"bsonType": "string", "description": "código NOC"},
                    "nombre": {"bsonType": ["string", "null"]},
                    "notas": {"bsonType": ["string", "null"]},
                    "resumen": {"bsonType": "object"},
                    "medallero": {"bsonType": "object"},
                    "participaciones": {"bsonType": "array"},
                    "poblaciones": {"bsonType": "array"},
                    "ediciones_sede": {"bsonType": "array"},
                },
            }
        },
        "indices": [
            {"key": [("nombre", 1)], "name": "ix_paises_nombre"},
            {"key": [("participaciones.anio", 1)], "name": "ix_paises_part_anio"},
            {"key": [("participaciones.deporte", 1)], "name": "ix_paises_part_deporte"},
            {"key": [("participaciones.busqueda_atleta", 1)], "name": "ix_paises_part_atleta"},
            {"key": [("participaciones.medalla", 1)], "name": "ix_paises_part_medalla"},
            {"key": [("ediciones_sede.anio", 1)], "name": "ix_paises_sede_anio"},
            {"key": [("medallero.por_anio.anio", 1)], "name": "ix_paises_medallas_anio"},
        ],
        "indices_extras": [
            {"key": [("poblaciones.anio", 1)], "name": "ix_paises_poblacion_anio"},
        ],
    },
    "disciplinas": {
        "descripcion": "Catálogo de disciplinas (deporte + evento) usadas en las participaciones.",
        "validador": {
            "$jsonSchema": {
                "bsonType": "object",
                "required": ["_id", "deporte", "evento"],
                "properties": {
                    "_id": {"bsonType": "int", "description": "id_disciplina de la fuente"},
                    "deporte": {"bsonType": "string"},
                    "evento": {"bsonType": "string"},
                },
            }
        },
        "indices": [
            {"key": [("deporte", 1), ("evento", 1)], "name": "ix_disciplinas_deporte_evento"},
        ],
        "indices_extras": [],
    },
    "ediciones": {
        "descripcion": "Edición de Juegos Olímpicos (año + temporada) con su sede.",
        "validador": {
            "$jsonSchema": {
                "bsonType": "object",
                "required": ["_id", "anio", "temporada", "juegos", "total_participaciones"],
                "properties": {
                    "_id": {"bsonType": "int", "description": "id_edicion_juego de la fuente"},
                    "anio": {"bsonType": ["int", "null"]},
                    "temporada": {"enum": ["Summer", "Winter", "Zappas Olympic Games",
                                           "Intercalated Games", "Equestrian Olympics", None]},
                    "juegos": {"bsonType": "string"},
                    "ciudad": {"bsonType": ["string", "null"]},
                    "noc_sede": {"bsonType": ["string", "null"]},
                    "pais_sede": {"bsonType": ["string", "null"]},
                    "sede_confirmada": {"bsonType": ["bool", "null"]},
                    "total_participaciones": {"bsonType": "int"},
                },
            }
        },
        "indices": [
            {"key": [("anio", 1)], "name": "ix_ediciones_anio"},
            {"key": [("noc_sede", 1)], "name": "ix_ediciones_sede"},
            {"key": [("ciudad", 1)], "name": "ix_ediciones_ciudad"},
        ],
        "indices_extras": [
            {"key": [("anio", 1), ("temporada", 1)], "name": "ix_ediciones_anio_temporada"},
        ],
    },
    "roles": {
        "descripcion": "Catálogo de roles (competidor, medallista, etc.) asociados a los atletas.",
        "validador": {
            "$jsonSchema": {
                "bsonType": "object",
                "required": ["_id", "nombre"],
                "properties": {
                    "_id": {"bsonType": "int"},
                    "nombre": {"bsonType": "string"},
                    "descripcion": {"bsonType": ["string", "null"]},
                },
            }
        },
        "indices": [
            {"key": [("nombre", 1)], "name": "ix_roles_nombre", "unique": True},
        ],
        "indices_extras": [],
    },
}

URI_DEFECTO = "mongodb://localhost:27017"
BASE_DEFECTO = "olimpiadas"


# --------------------------------------------------------------------------
# Bitácora con fecha y hora
# --------------------------------------------------------------------------
class Bitacora:
    """Escribe en pantalla y en docs/logs/crear_colecciones_indices_<fecha>.log."""

    def __init__(self, carpeta_logs: Path | None):
        self.inicio = datetime.now()
        self.ruta = None
        self._fh = None
        if carpeta_logs is not None:
            carpeta_logs.mkdir(parents=True, exist_ok=True)
            self.ruta = carpeta_logs / f"crear_colecciones_indices_{self.inicio:%Y%m%d_%H%M%S}.log"
            self._fh = self.ruta.open("w", encoding="utf-8")

    def linea(self, texto: str = "") -> None:
        marca = f"[{datetime.now():%Y-%m-%d %H:%M:%S}]"
        for trozo in texto.split("\n"):
            print(f"{marca} {trozo}".rstrip())
        if self._fh:
            self._fh.write(f"{marca} {texto}\n")
            self._fh.flush()

    def cerrar(self, ok: bool = True) -> None:
        dur = (datetime.now() - self.inicio).total_seconds()
        self.linea(f"--- Fin de la ejecución ({'OK' if ok else 'CON ERRORES'}) en {dur:.1f}s ---")
        if self.ruta:
            print(f"\nBitácora guardada en: {self.ruta}")
        if self._fh:
            self._fh.close()


# --------------------------------------------------------------------------
# Operaciones
# --------------------------------------------------------------------------
def conectar(uri: str, base: str, log: Bitacora):
    cliente = MongoClient(uri, serverSelectionTimeoutMS=8000)
    info = cliente.admin.command("ping")
    version = cliente.server_info().get("version", "?")
    log.linea(f"Conectado a {uri} (MongoDB {version}, ping ok={info.get('ok')})")
    log.linea(f"Base de datos: {base}")
    return cliente[base], cliente


def crear_coleccion(db, nombre: str, cfg: dict, log: Bitacora) -> None:
    if nombre in db.list_collection_names():
        log.linea(f"  = {nombre}: ya existe, se omite la creación")
        return
    db.create_collection(nombre, validator=cfg["validador"], validationLevel="moderate")
    log.linea(f"  + {nombre}: creada con validador $jsonSchema (validationLevel=moderate)")


def aplicar_collmod(db, nombre: str, cfg: dict, log: Bitacora) -> None:
    """Re-valida una colección existente sin tocar documentos ya cargados."""
    db.command(
        "collMod",
        nombre,
        validator=cfg["validador"],
        validationLevel="moderate",
        validationAction="error",
    )
    log.linea(f"  ~ {nombre}: validador aplicado con collMod (moderate)")


def crear_indices(db, nombre: str, cfg: dict, extras: bool, log: Bitacora) -> None:
    specs = list(cfg["indices"]) + (list(cfg.get("indices_extras", [])) if extras else [])
    coleccion = db[nombre]
    for spec in specs:
        opciones = {k: v for k, v in spec.items() if k != "key"}
        try:
            nombre_idx = coleccion.create_index(spec["key"], **opciones)
            log.linea(f"  + {nombre}.{nombre_idx}: {json.dumps(spec['key'], ensure_ascii=False)}"
                      f"{' (único)' if spec.get('unique') else ''}")
        except OperationFailure as exc:
            log.linea(f"  ! {nombre}.{spec['name']}: NO se pudo crear -> {exc.details.get('codeName', '')} "
                      f"{exc.details.get('errmsg', exc)}")
            log.linea(f"      Si el índice homónimo tiene otras opciones, eliminarlo y re-ejecutar:")
            log.linea(f"      db.{nombre}.dropIndex(\"{spec['name']}\")")


def reporte(db, log: Bitacora) -> None:
    disponibles = set(db.list_collection_names())
    log.linea("REPORTE DE ESTADO (solo lectura)")
    for nombre, cfg in COLECCIONES.items():
        if nombre not in disponibles:
            log.linea(f"  {nombre}: NO EXISTE ({cfg['descripcion']})")
            continue
        coleccion = db[nombre]
        docs = coleccion.count_documents({})
        tam = coleccion.aggregate([{"$collStats": {"storageStats": {"scale": 1024 * 1024}}}],
                                  allowDiskUse=True)
        mb = next(iter(tam), {}).get("storageStats", {}).get("size", 0)
        creados = set(coleccion.index_information())
        esperados = {s["name"] for s in cfg["indices"]}
        faltan = sorted(esperados - creados)
        log.linea(f"  {nombre}: {docs:,} documentos, ~{mb:.0f} MiB, "
                  f"índices propios {len(creados) - 1}/{len(esperados)}"
                  f"{' (FALTAN: ' + ', '.join(faltan) + ')' if faltan else ''}")
    sobrantes = disponibles - set(COLECCIONES)
    if sobrantes:
        log.linea(f"  Colecciones fuera del modelo: {', '.join(sorted(sobrantes))}")


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def main() -> int:
    raiz = Path(__file__).resolve().parents[1]  # .../Proyecto Fase 3
    ap = argparse.ArgumentParser(description="Crea colecciones e índices de la Fase 3 en MongoDB.")
    ap.add_argument("--uri", default=URI_DEFECTO, help=f"URI de MongoDB (defecto: {URI_DEFECTO})")
    ap.add_argument("--base", default=BASE_DEFECTO, help=f"Base de datos (defecto: {BASE_DEFECTO})")
    ap.add_argument("--solo-indices", action="store_true", help="No crea colecciones ni validadores, solo índices")
    ap.add_argument("--collmod", action="store_true",
                    help="Aplica los validadores a colecciones que ya existen (validationLevel=moderate)")
    ap.add_argument("--extras", action="store_true", help="Crea además los índices compuestos extra documentados")
    ap.add_argument("--reporte", action="store_true", help="Solo muestra el estado actual (no escribe nada)")
    ap.add_argument("--sin-log", action="store_true", help="No escribe la bitácora en docs/logs/")
    args = ap.parse_args()

    log_dir = None if args.sin_log else raiz / "docs" / "logs"
    log = Bitacora(log_dir)
    log.linea("=" * 78)
    log.linea("FASE 3 — creación de colecciones e índices (MongoDB)")
    log.linea(f"Script: {Path(__file__).name} | Ejecutado por: {Path.home().name}")
    log.linea("=" * 78)

    try:
        db, cliente = conectar(args.uri, args.base, log)
    except PyMongoError as exc:
        log.linea(f"ERROR al conectar: {exc}")
        log.linea("¿Está levantado mongod? Ejemplo: mongod --dbpath <carpeta> --port 27017 --fork --logpath <log>")
        log.cerrar(ok=False)
        return 1

    exito = True
    try:
        if args.reporte:
            reporte(db, log)
        else:
            log.linea("Colecciones:")
            for nombre, cfg in COLECCIONES.items():
                log.linea(f"[{nombre}] {cfg['descripcion']}")
                if not args.solo_indices:
                    crear_coleccion(db, nombre, cfg, log)
                    if args.collmod and nombre in db.list_collection_names():
                        aplicar_collmod(db, nombre, cfg, log)
                crear_indices(db, nombre, cfg, args.extras, log)

            log.linea("")
            log.linea("Conteos finales:")
            for nombre in COLECCIONES:
                if nombre in db.list_collection_names():
                    log.linea(f"  {nombre}: {db[nombre].count_documents({}):,} documentos")

            log.linea("")
            log.linea("Verificación de integridad básica (los conteos deben coincidir con la Fase 1):")
            verificaciones = [
                ("atletas", "worked_datasets/tabla_atletas.csv", 153325),
                ("paises", "worked_datasets/tabla_nocs.csv", 234),
                ("disciplinas", "worked_datasets/tabla_disciplina.csv", 2087),
                ("ediciones", "worked_datasets/tabla_edicion_juego.csv", 63),
                ("roles", "worked_datasets/tabla_rol.csv", 11),
            ]
            for nombre, fuente, esperado in verificaciones:
                real = db[nombre].count_documents({}) if nombre in db.list_collection_names() else 0
                estado = "OK" if real == esperado else f"REVISAR (esperado {esperado:,})"
                log.linea(f"  {nombre}: {real:,} vs {fuente} -> {estado}")
    except PyMongoError as exc:
        exito = False
        log.linea(f"ERROR de MongoDB: {exc}")

    log.cerrar(ok=exito)
    return 0 if exito else 1


if __name__ == "__main__":
    sys.exit(main())
