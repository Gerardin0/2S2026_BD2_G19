# ==========================================================================
# PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
# Gerardo - Carga por DEPORTISTA (Usain Bolt)
#
# docs/deportista/medir_tiempos_restore.ps1
#
# Mide el tiempo REAL de cada restauracion y lo deja en un CSV listo para la
# tabla de tiempos del Checklist (seccion 5). El enunciado pide tiempos, no
# solo el resultado de la restauracion, asi que el cronometro va aqui y no
# dentro del .sql (SQL Server no expone un temporizador por sentencia).
#
# Uso (desde la carpeta "Proyecto Fase 2"):
#   export PATH="/opt/mssql-tools18/bin:$PATH"
#   pwsh -File docs/deportista/medir_tiempos_restore.ps1
#
# Todas las marcas de tiempo (PRINT de los .sql, cronometro y CSV) se
# emiten en hora de Guatemala (UTC-6, America/Guatemala).
# ==========================================================================

param(
    [string]$Servidor   = 'localhost,1433',
    [string]$Usuario    = 'sa',
    [string]$Password  = 'Password123!',
    [string]$CarpetaSQL = 'restauracion/deportista',
    [string]$Salida     = 'docs/deportista/tiempos_restore_deportista.csv'
)

$ErrorActionPreference = 'Stop'

# --- Hora de Guatemala ------------------------------------------------------
# Los PRINT de los .sql usan AT TIME ZONE 'Central America'; aca se hace lo
# mismo para que las marcas del cronometro y del CSV coincidan con ellas.
$ZonaHoraria = [System.TimeZoneInfo]::FindSystemTimeZoneById('America/Guatemala')
function Get-HoraGuatemala {
    param([datetime]$Instante = [datetime]::UtcNow)
    [System.TimeZoneInfo]::ConvertTimeFromUtc(
        $Instante.ToUniversalTime(), $ZonaHoraria).ToString('yyyy-MM-dd HH:mm:ss')
}

# Pares (etiqueta, script) en el orden en que hay que correrlos.
# Cada restauracion va precedida de la eliminacion de la base, porque el
# enunciado pide "eliminar la base de datos completa" entre restoreduras.
$Pasos = @(
    @{ Etiqueta = 'Full';           Eliminar = $true;  Script = '02_restore_solo_full.sql'      }
    @{ Etiqueta = 'Full + Diff 1';  Eliminar = $true;  Script = '03_restore_full_diff1.sql'     }
    @{ Etiqueta = 'Full + Diff 2';  Eliminar = $true;  Script = '04_restore_full_diff2.sql'     }
    @{ Etiqueta = 'Full + Diff 3';  Eliminar = $true;  Script = '05_restore_full_diff3.sql'     }
)

function Invoke-SqlFile {
    param([string]$Ruta)
    Write-Host "`n>>> sqlcmd -i $Ruta" -ForegroundColor Cyan
    $args = @(
        '-S', $Servidor, '-U', $Usuario, '-P', $Password,
        '-C',                       # confiar el certificado autofirmado (ODBC 18)
        '-b',                       # salir con codigo de error si el SQL falla
        '-i', $Ruta
    )
    & sqlcmd @args
    if ($LASTEXITCODE -ne 0) {
        throw "Falló la ejecución de $Ruta (sqlcmd exit $LASTEXITCODE)"
    }
}

function Get-FilasParticipacionRestauradas {
    $Consulta = @'
SET NOCOUNT ON;
SELECT COUNT(*)
FROM dbo.participacion AS p
INNER JOIN dbo.edicion_juego AS ej ON p.id_edicion = ej.id;
'@
    $ArgsSql = @(
        '-S', $Servidor, '-U', $Usuario, '-P', $Password,
        '-C', '-b', '-d', 'db_olimpiadas_deportista',
        '-h', '-1', '-W', '-Q', $Consulta
    )
    $SalidaSql = @(& sqlcmd @ArgsSql)
    if ($LASTEXITCODE -ne 0) {
        throw "Falló la consulta de filas restauradas (sqlcmd exit $LASTEXITCODE)"
    }

    $Valores = @($SalidaSql | ForEach-Object { "$_".Trim() } |
        Where-Object { $_ -match '^\d+$' })
    if ($Valores.Count -ne 1) {
        throw "No se pudo interpretar el conteo de filas restauradas: $($SalidaSql -join ' ')"
    }

    return [long]$Valores[0]
}

$Resultados = @()

foreach ($Paso in $Pasos) {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Yellow
    Write-Host "  $($Paso.Etiqueta)" -ForegroundColor Yellow
    Write-Host "  $(Get-HoraGuatemala)" -ForegroundColor DarkGray
    Write-Host "===========================================================" -ForegroundColor Yellow

    if ($Paso.Eliminar) {
        Invoke-SqlFile -Ruta (Join-Path $CarpetaSQL '01_eliminar_base.sql')
    }

    $ScriptSql = Join-Path $CarpetaSQL $Paso.Script
    $Log = "logs/restore_$($Paso.Etiqueta -replace '\W+','_').log"

    $Inicio = Get-Date
    Invoke-SqlFile -Ruta $ScriptSql | Tee-Object -FilePath $Log
    $Fin = Get-Date

    $Segundos = [math]::Round(($Fin - $Inicio).TotalSeconds, 3)
    $FilasRestauradas = Get-FilasParticipacionRestauradas
    Write-Host ">>> Tiempo de restauración [$($Paso.Etiqueta)] = $Segundos s" -ForegroundColor Green
    Write-Host ">>> Filas participacion + edicion restauradas = $FilasRestauradas" -ForegroundColor Green

    $Resultados += [pscustomobject]@{
        tipo_carga          = 'Deportista'
        restauracion        = $Paso.Etiqueta
        fecha_hora          = (Get-HoraGuatemala)
        tiempo_s            = $Segundos
        filas_restauradas   = $FilasRestauradas
        tamano_bak          = 'ver logs'
    }
}

# --- Volcado de la tabla de tiempos -------------------------------------
$Resultados | Format-Table -AutoSize
$Resultados | Export-Csv -Path $Salida -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Tabla de tiempos guardada en: $Salida" -ForegroundColor Green
Write-Host "Copiar las filas 'Deportista' a la seccion 5 del Checklist." -ForegroundColor Green