# ==========================================================================
# PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
# Jose - Carga por DEPORTE (100 m planos femeninos)
#
# docs/deporte/medir_tiempos_restore.ps1
#
# Mide el tiempo REAL de cada restauracion y lo deja en un CSV listo para la
# tabla de tiempos del Checklist (seccion 5). El enunciado pide tiempos, no
# solo el resultado de la restauracion, asi que el cronometro va aqui y no
# dentro del .sql (SQL Server no expone un temporizador por sentencia).
#
# Uso (desde la carpeta "Proyecto Fase 2"):
#   pwsh -File docs/deporte/medir_tiempos_restore.ps1
# ==========================================================================

param(
    [string]$Servidor   = 'localhost,1433',
    [string]$Usuario    = 'sa',
    [string]$Password  = 'Password123!',
    [string]$CarpetaSQL = 'restauracion/deporte',
    [string]$Salida     = 'docs/deporte/tiempos_restore_deporte.csv'
)

$ErrorActionPreference = 'Stop'

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
        '-b',                       # salir con codigo de error si el SQL falla
        '-i', $Ruta
    )
    & sqlcmd @args
    if ($LASTEXITCODE -ne 0) {
        throw "Falló la ejecución de $Ruta (sqlcmd exit $LASTEXITCODE)"
    }
}

$Resultados = @()

foreach ($Paso in $Pasos) {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Yellow
    Write-Host "  $($Paso.Etiqueta)" -ForegroundColor Yellow
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host "===========================================================" -ForegroundColor Yellow

    if ($Paso.Eliminar) {
        Invoke-SqlFile -Ruta (Join-Path $CarpetaSQL '01_eliminar_base.sql')
    }

    $ScriptSql = Join-Path $CarpetaSQL $Paso.Script
    $Log = "logs/restore_deporte_$($Paso.Etiqueta -replace '\W+','_').log"

    $Inicio = Get-Date
    Invoke-SqlFile -Ruta $ScriptSql | Tee-Object -FilePath $Log
    $Fin = Get-Date

    $Segundos = [math]::Round(($Fin - $Inicio).TotalSeconds, 3)
    Write-Host ">>> Tiempo de restauración [$($Paso.Etiqueta)] = $Segundos s" -ForegroundColor Green

    $Resultados += [pscustomobject]@{
        tipo_carga          = 'Deporte'
        restauracion        = $Paso.Etiqueta
        fecha_hora          = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        tiempo_s            = $Segundos
        filas_restauradas   = 'ver capturas'
        tamano_bak          = 'ver logs'
    }
}

# --- Volcado de la tabla de tiempos -------------------------------------
$Resultados | Format-Table -AutoSize
$Resultados | Export-Csv -Path $Salida -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Tabla de tiempos guardada en: $Salida" -ForegroundColor Green
Write-Host "Copiar las filas 'Deporte' a la seccion 5 del Checklist." -ForegroundColor Green