#!/usr/bin/env bash
# ==========================================================================
# PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
# Pablo - Carga por AÑO
# docs/anio/medir_tiempos_restore.sh
# ==========================================================================
set -euo pipefail

SQLCMD="docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P Password123! -C -b"
CARPETA_SQL="restauracion/anio"
SALIDA_CSV="docs/anio/tiempos_restore_anio.csv"

echo "tipo_carga,restauracion,fecha_hora,tiempo_s,filas_restauradas,tamano_bak" > "$SALIDA_CSV"

ejecutar_paso() {
    local etiqueta="$1"
    local script_sql="$2"
    local log_eliminar="$3"
    local log_restore="$4"

    echo "==========================================================="
    echo "  $etiqueta ($(date '+%Y-%m-%d %H:%M:%S'))"
    echo "==========================================================="

    # 1. Eliminar base de datos completa
    $SQLCMD -i /dev/stdin < "$CARPETA_SQL/01_eliminar_base.sql" > "$log_eliminar"

    # 2. Medir tiempo real de restauración
    local t_ini
    t_ini=$(date +%s%3N)
    $SQLCMD -i /dev/stdin < "$CARPETA_SQL/$script_sql" > "$log_restore"
    local t_fin
    t_fin=$(date +%s%3N)

    local duracion_ms=$((t_fin - t_ini))
    local duracion_s
    duracion_s=$(awk "BEGIN {printf \"%.3f\", $duracion_ms/1000}")

    echo ">>> Tiempo de restauración [$etiqueta] = ${duracion_s} s"
    echo "\"Año\",\"$etiqueta\",\"$(date '+%Y-%m-%d %H:%M:%S')\",\"$duracion_s\",\"ver capturas\",\"ver logs\"" >> "$SALIDA_CSV"
}

ejecutar_paso "Full"          "02_restore_solo_full.sql"  "logs/00_eliminar_02_restore_solo_full_anio.log"  "logs/02_restore_solo_full_anio.log"
ejecutar_paso "Full + Diff 1" "03_restore_full_diff1.sql" "logs/00_eliminar_03_restore_full_diff1_anio.log" "logs/03_restore_full_diff1_anio.log"
ejecutar_paso "Full + Diff 2" "04_restore_full_diff2.sql" "logs/00_eliminar_04_restore_full_diff2_anio.log" "logs/04_restore_full_diff2_anio.log"
ejecutar_paso "Full + Diff 3" "05_restore_full_diff3.sql" "logs/00_eliminar_05_restore_full_diff3_anio.log" "logs/05_restore_full_diff3_anio.log"

echo ""
echo "=== TABLA DE TIEMPOS GENERADA ($SALIDA_CSV) ==="
column -t -s, "$SALIDA_CSV"