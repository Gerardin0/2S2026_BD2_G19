#!/usr/bin/env bash
# ==========================================================================
# PROYECTO 2 - FASE 2 (Respaldo y Restauracion) - Grupo 19
#
# probar_todo.sh
# Prueba de punta a punta las tres cargas del equipo sobre el mismo
# contenedor de SQL Server:
#
#   anio        (Pablo)    db_olimpiadas_anio
#   deporte     (Jose)     db_olimpiadas_deporte
#   deportista  (Gerardo)  db_olimpiadas_deportista
#
# Por cada tipo de carga ejecuta, en orden, exactamente los scripts del
# repositorio:
#   ddl/01..03 -> carga/<tipo>/01..02 -> 4 cargas, cada una con su respaldo
#   -> 4 veces: eliminar la base + restaurar (full, +diff1, +diff2, +diff3)
# y al final compara las filas restauradas contra las de antes de eliminar.
#
# No modifica ningun script ni los logs/capturas de evidencia: su salida va
# a logs/prueba_todo/.
#
# USO (Ubuntu, desde la carpeta "Proyecto Fase 2"):
#   chmod +x probar_todo.sh
#   sudo ./probar_todo.sh              # las tres cargas
#   sudo ./probar_todo.sh deporte      # solo una: anio | deporte | deportista
#
# Necesita sudo porque usa docker. Si el contenedor "sqlserver_olimpiadas"
# no existe, lo crea montando ./CSVs y ./backups_fisicos.
#
# OJO: recrea las bases db_olimpiadas_<tipo> y sobrescribe los .bak de esos
# tipos en el volumen de respaldos.
# ==========================================================================
set -uo pipefail

CONTENEDOR="sqlserver_olimpiadas"
PASSWORD="Password123!"
IMAGEN="mcr.microsoft.com/mssql/server:2022-latest"
DIR_LOGS="logs/prueba_todo"

# --- sudo ----------------------------------------------------------------
# Si docker no responde con el usuario actual, se relanza el script con sudo.
if [ "$(id -u)" -ne 0 ] && ! docker info >/dev/null 2>&1; then
    echo "Docker requiere permisos de administrador: relanzando con sudo..."
    exec sudo bash "$0" "$@"
fi

# Siempre se trabaja desde la carpeta del script ("Proyecto Fase 2").
cd "$(dirname "$(readlink -f "$0")")" || exit 1

TIPOS=("anio" "deporte" "deportista")
if [ $# -ge 1 ] && [ "$1" != "todos" ]; then
    case "$1" in
        anio|deporte|deportista) TIPOS=("$1") ;;
        *) echo "Uso: sudo ./probar_todo.sh [anio|deporte|deportista|todos]"; exit 1 ;;
    esac
fi

# Filas esperadas en las nueve tablas dbo.* al terminar las 4 cargas
# (valores de la Documentacion Tecnica, seccion 5).
declare -A ESPERADO=( [anio]=180009 [deporte]=6285 [deportista]=107 )

VERDE=$'\e[32m'; ROJO=$'\e[31m'; AMARILLO=$'\e[33m'; CIAN=$'\e[36m'; NORMAL=$'\e[0m'
titulo() { echo; echo "${AMARILLO}=== $* ($(date '+%Y-%m-%d %H:%M:%S'))${NORMAL}"; }
ms()     { date +%s%3N; }
seg()    { awk "BEGIN {printf \"%.3f\", $1/1000}"; }

# --- 1. Contenedor ---------------------------------------------------------
titulo "Contenedor $CONTENEDOR"
if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTENEDOR"; then
    echo "No existe: se crea con ./CSVs y ./backups_fisicos"
    mkdir -p backups_fisicos
    chmod 777 backups_fisicos          # el usuario mssql (uid 10001) escribe aqui
    chmod -R a+rX CSVs
    # :z es para SELinux; en Ubuntu (AppArmor) no hace nada y no estorba.
    docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=$PASSWORD" \
        -e "MSSQL_COLLATION=Latin1_General_100_CI_AS_SC_UTF8" \
        -p 1433:1433 --name "$CONTENEDOR" \
        -v "$(pwd)/CSVs:/var/opt/mssql/csv:ro,z" \
        -v "$(pwd)/backups_fisicos:/var/opt/mssql/backups:z" \
        -d "$IMAGEN" >/dev/null || { echo "${ROJO}No se pudo crear el contenedor${NORMAL}"; exit 1; }
elif [ "$(docker inspect -f '{{.State.Running}}' "$CONTENEDOR")" != "true" ]; then
    echo "Existe pero esta detenido: se inicia"
    docker start "$CONTENEDOR" >/dev/null
fi

# Cliente sqlcmd dentro del contenedor (mssql-tools18 en las imagenes nuevas).
if docker exec "$CONTENEDOR" test -x /opt/mssql-tools18/bin/sqlcmd; then
    SQLCMD=(docker exec -i "$CONTENEDOR" /opt/mssql-tools18/bin/sqlcmd -C)
else
    SQLCMD=(docker exec -i "$CONTENEDOR" /opt/mssql-tools/bin/sqlcmd)
fi
SQLCMD+=(-S localhost -U sa -P "$PASSWORD" -b)

echo -n "Esperando a que SQL Server acepte conexiones"
for _ in $(seq 1 60); do
    "${SQLCMD[@]}" -Q "SELECT 1" >/dev/null 2>&1 && break
    echo -n "."; sleep 2
done
if ! "${SQLCMD[@]}" -Q "SELECT 1" >/dev/null 2>&1; then
    echo; echo "${ROJO}SQL Server no responde. Revisar: sudo docker logs $CONTENEDOR${NORMAL}"; exit 1
fi
echo " listo."
"${SQLCMD[@]}" -h -1 -W -Q "SET NOCOUNT ON; SELECT SERVERPROPERTY('ProductVersion'), SERVERPROPERTY('Collation')"

# Los CSV deben tener fin de linea LF (ver .gitattributes); con CRLF el
# BULK INSERT deja un \r en la ultima columna y fallan las conversiones.
if head -c 2000 CSVs/tabla_participacion.csv | grep -q $'\r'; then
    echo "${ROJO}AVISO: los CSV tienen CRLF. Convertir con: sed -i 's/\r\$//' CSVs/*.csv${NORMAL}"
fi

mkdir -p "$DIR_LOGS"

# --- 2. Ejecucion de un script ---------------------------------------------
# sql <log> <archivo.sql> [args extra de sqlcmd]
# El script se pasa por stdin, asi no hace falta copiarlo al contenedor.
sql() {
    local log="$1" archivo="$2"; shift 2
    if "${SQLCMD[@]}" "$@" -i /dev/stdin < "$archivo" > "$log" 2>&1; then
        return 0
    fi
    echo "${ROJO}    ERROR en $archivo (ver $log):${NORMAL}"
    grep -E '^Msg|rror' "$log" | head -4 | sed 's/^/      /'
    return 1
}

# Suma de filas de las nueve tablas dbo.* que imprime un log de conteos.
filas() { tr -d '\r' < "$1" | grep -E '^dbo\.[a-z_]+ +[0-9]+ *$' | tail -9 | awk '{s+=$2} END {print s+0}'; }

declare -a RESUMEN=()

probar_tipo() {
    local t="$1" db="db_olimpiadas_$1" n=0 f inicio
    local L="$DIR_LOGS/$t"
    titulo "Carga por ${t^^}  ($db)"

    # Base y esquema (ddl compartido, recibe -v DbNombre)
    for f in ddl/01_crear_base_datos.sql ddl/02_esquema_staging.sql ddl/03_modelo_relacional.sql; do
        n=$((n+1)); echo "  $f"
        sql "${L}_$(printf %02d $n)_$(basename "$f" .sql).log" "$f" -v DbNombre="$db" || return 1
    done

    # Staging y procedimiento
    for f in carga/"$t"/01_*.sql carga/"$t"/02_*.sql; do
        n=$((n+1)); echo "  $f"
        sql "${L}_$(printf %02d $n)_$(basename "$f" .sql).log" "$f" || return 1
    done

    # Cuatro cargas, cada una seguida de su respaldo
    local cargas=(carga/"$t"/0[3-6]_*.sql) respaldos=(backup/"$t"/0[1-4]_*.sql) i
    for i in 0 1 2 3; do
        n=$((n+1)); inicio=$(ms)
        sql "${L}_$(printf %02d $n)_$(basename "${cargas[$i]}" .sql).log" "${cargas[$i]}" || return 1
        echo "  ${cargas[$i]}  ->  $(seg $(( $(ms) - inicio ))) s"
        n=$((n+1)); inicio=$(ms)
        sql "${L}_$(printf %02d $n)_$(basename "${respaldos[$i]}" .sql).log" "${respaldos[$i]}" || return 1
        echo "  ${respaldos[$i]}  ->  $(seg $(( $(ms) - inicio ))) s"
    done

    # Eliminar la base + restaurar, cuatro veces
    local etiquetas=("Full" "Full + Diff 1" "Full + Diff 2" "Full + Diff 3")
    local restores=(restauracion/"$t"/0[2-5]_*.sql) antes=0 despues=0 estado
    for i in 0 1 2 3; do
        n=$((n+1))
        local log_elim="${L}_$(printf %02d $n)_eliminar_antes_restore_$((i+1)).log"
        sql "$log_elim" restauracion/"$t"/01_eliminar_base.sql || return 1
        # La primera eliminacion imprime los conteos con las 4 cargas hechas:
        # es la referencia contra la que se valida Full + Diff 3.
        [ "$i" -eq 0 ] && antes=$(filas "$log_elim")

        n=$((n+1))
        local log_rest="${L}_$(printf %02d $n)_$(basename "${restores[$i]}" .sql).log"
        inicio=$(ms)
        sql "$log_rest" "${restores[$i]}" || return 1
        local dur; dur=$(seg $(( $(ms) - inicio )))
        despues=$(filas "$log_rest")

        # Tras la ultima restauracion los conteos deben ser los finales.
        estado="OK"
        if [ "$i" -eq 3 ] && [ "$despues" -ne "${ESPERADO[$t]}" ]; then
            estado="DISTINTO (esperado ${ESPERADO[$t]})"
        fi
        echo "  ${etiquetas[$i]}: ${dur} s, ${despues} filas restauradas  [${estado}]"
        RESUMEN+=("$t|${etiquetas[$i]}|$dur|$despues|$estado")
    done
    # Conteos con las 4 cargas (antes del primer DROP) contra Full + Diff 3.
    if [ "$antes" -ne "$despues" ]; then
        echo "${ROJO}  Las filas tras Full + Diff 3 ($despues) no coinciden con las de antes de eliminar ($antes)${NORMAL}"
        return 1
    fi
    echo "${VERDE}  Carga por $t: restauracion integra ($despues filas antes y despues).${NORMAL}"
    return 0
}

# --- 3. Ejecucion ----------------------------------------------------------
declare -A RESULTADO=()
INICIO_TOTAL=$(ms)
for t in "${TIPOS[@]}"; do
    if probar_tipo "$t"; then RESULTADO[$t]="${VERDE}OK${NORMAL}"; else RESULTADO[$t]="${ROJO}FALLO${NORMAL}"; fi
done

# --- 4. Resumen ------------------------------------------------------------
titulo "Resumen"
printf "%-11s %-14s %10s %10s  %s\n" "Tipo" "Restauracion" "Tiempo(s)" "Filas" "Estado"
for r in "${RESUMEN[@]}"; do
    IFS='|' read -r t e d f s <<< "$r"
    printf "%-11s %-14s %10s %10s  %s\n" "$t" "$e" "$d" "$f" "$s"
done
echo
echo "Respaldos en el volumen:"
docker exec "$CONTENEDOR" sh -c 'ls -lh /var/opt/mssql/backups/*.bak 2>/dev/null' | awk '{print "  " $5 "\t" $NF}'
echo
for t in "${TIPOS[@]}"; do echo "  $t: ${RESULTADO[$t]}"; done
echo "Tiempo total: $(seg $(( $(ms) - INICIO_TOTAL ))) s"
echo "Logs de esta prueba: ${CIAN}$DIR_LOGS/${NORMAL}"

# Los archivos creados con sudo quedan como root: devolverlos al usuario.
if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$DIR_LOGS" 2>/dev/null
fi

for t in "${TIPOS[@]}"; do [[ "${RESULTADO[$t]}" == *OK* ]] || exit 1; done
exit 0
