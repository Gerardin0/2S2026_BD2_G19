# ==========================================================================
# PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
# Jose - Carga por DEPORTE (100 m planos femeninos)
#
# docs/deporte/capturar_ciclo.ps1
#
# Corre el ciclo completo (base, staging, 4 cargas, 4 respaldos, 4
# restauraciones) y toma SOLO las capturas de pantalla que pide el Checklist.
#
# Por cada paso ejecuta el mismo sqlcmd de la seccion 5 del README, parte la
# salida en pantallas, y por cada pantalla:
#   1. limpia la terminal,
#   2. imprime la fecha y hora del sistema operativo y el comando ejecutado,
#   3. muestra el bloque de salida,
#   4. guarda un PNG de la pantalla completa (reloj de Windows incluido) en
#      capturas/.
# Las tablas que no caben en una pantalla se muestran con sus primeras y
# ultimas filas; la salida integra de cada paso queda en logs/.
#
# IMPORTANTE: hay que correrlo desde una terminal VISIBLE y maximizada, en el
# monitor principal, y no tocar nada mientras corre (captura lo que haya en
# pantalla). Empieza desde cero: recrea la base y sobrescribe los .bak.
#
# Uso (desde la carpeta "Proyecto Fase 2"):
#   powershell -ExecutionPolicy Bypass -File docs/deporte/capturar_ciclo.ps1
#
# Si las capturas no salieron bien, se pueden repetir SIN volver a ejecutar
# nada, a partir de la salida guardada de esa corrida (tarda ~1 minuto):
#   powershell -ExecutionPolicy Bypass -File docs/deporte/capturar_ciclo.ps1 -SoloCapturas
# ==========================================================================

param(
    [string]$Servidor = 'localhost,1433',
    [string]$Usuario  = 'sa',
    [string]$Password = 'Password123!',
    [string]$Base     = 'db_olimpiadas_deporte',
    [int]$PausaMs     = 900,      # espera a que la terminal termine de pintar
    [switch]$SoloCapturas,        # no ejecuta nada: captura la salida ya guardada en logs/
    [string]$ProbarCon = ''       # solo pruebas: pagina un log existente, sin BD ni PNG
)

$ErrorActionPreference = 'Stop'
$DirCapturas = 'capturas'
$script:NumCaptura = 0

# --- Captura de pantalla -------------------------------------------------
if (-not $ProbarCon) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    # Sin esto, con el escalado de Windows (125 %, 150 %) la captura sale recortada.
    Add-Type -Namespace Win32 -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    [Win32.Dpi]::SetProcessDPIAware() | Out-Null
    Add-Type -Namespace Win32 -Name Ventana -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hWnd, int[] rect);
'@
    # La terminal desde la que se lanza el script es la ventana activa en este
    # momento: se guarda para comprobar, antes de cada captura, que sigue al frente.
    $script:Terminal = [Win32.Ventana]::GetForegroundWindow()
    New-Item -ItemType Directory -Force -Path $DirCapturas, 'logs' | Out-Null
    # Las capturas de una corrida anterior se reemplazan por las de esta.
    Remove-Item (Join-Path $DirCapturas 'deporte_*.png') -ErrorAction SilentlyContinue
}

$script:Indice = @()

function Write-Indice {
    # capturas/CAPTURAS_deporte.md: las capturas de ESTA carga, agrupadas por paso.
    if ($ProbarCon -or -not $script:Indice.Count) { return }
    $md  = @('# Capturas - Jose (carga por DEPORTE)', '',
             "Generado por ``docs/deporte/capturar_ciclo.ps1`` el $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss').",
             'Evento: 100 m planos femeninos (`id_disciplina = 237`). Base: `db_olimpiadas_deporte`.',
             'La salida completa de cada paso esta en `logs/captura_deporte_*.log`.', '')
    foreach ($g in ($script:Indice | Group-Object Paso)) {
        $md += "## $($g.Name -replace '^Deporte - ', '')"; $md += ''
        foreach ($c in $g.Group) { $md += "**Pantalla $($c.Pantalla)**"; $md += ''; $md += "![$($g.Name) $($c.Pantalla)]($($c.Archivo))"; $md += '' }
    }
    $md | Set-Content -Path (Join-Path $DirCapturas 'CAPTURAS_deporte.md') -Encoding UTF8
}

# Titulo y comando de cada paso, por el nombre de su log (para -SoloCapturas).
$Catalogo = [ordered]@{
    '00_ddl'     = @('Base y esquema',          '-v DbNombre=db_olimpiadas_deporte -i ddl/01_crear_base_datos.sql ; 02_esquema_staging.sql ; 03_modelo_relacional.sql')
    '01_staging' = @('Staging y procedimiento', '-d db_olimpiadas_deporte -i carga/deporte/01_cargar_staging.sql ; 02_proc_cargar_deporte.sql')
    '02_carga1'  = @('Carga 1 - Paris 2024',    '-d db_olimpiadas_deporte -i carga/deporte/03_carga_1_paris_2024.sql')
    '03_full'    = @('Backup FULL',             '-d db_olimpiadas_deporte -i backup/deporte/01_full_deporte.sql')
    '04_carga2'  = @('Carga 2 - Tokio 2020',    '-d db_olimpiadas_deporte -i carga/deporte/04_carga_2_tokio_2020.sql')
    '05_diff1'   = @('Backup DIFERENCIAL 1',    '-d db_olimpiadas_deporte -i backup/deporte/02_dif_deporte_1.sql')
    '06_carga3'  = @('Carga 3 - Rio 2016',      '-d db_olimpiadas_deporte -i carga/deporte/05_carga_3_rio_2016.sql')
    '07_diff2'   = @('Backup DIFERENCIAL 2',    '-d db_olimpiadas_deporte -i backup/deporte/03_dif_deporte_2.sql')
    '08_carga4'  = @('Carga 4 - Londres 2012',  '-d db_olimpiadas_deporte -i carga/deporte/06_carga_4_londres_2012.sql')
    '09_diff3'   = @('Backup DIFERENCIAL 3',    '-d db_olimpiadas_deporte -i backup/deporte/04_dif_deporte_3.sql')
    '10_eliminar_antes_full'       = @('Eliminar base (antes de Full)',          '-i restauracion/deporte/01_eliminar_base.sql')
    '11_restore_full'              = @('Restauracion Full',                      '-i restauracion/deporte/02_restore_solo_full.sql')
    '12_eliminar_antes_full_diff1' = @('Eliminar base (antes de Full + Diff 1)', '-i restauracion/deporte/01_eliminar_base.sql')
    '13_restore_full_diff1'        = @('Restauracion Full + Diff 1',             '-i restauracion/deporte/03_restore_full_diff1.sql')
    '14_eliminar_antes_full_diff2' = @('Eliminar base (antes de Full + Diff 2)', '-i restauracion/deporte/01_eliminar_base.sql')
    '15_restore_full_diff2'        = @('Restauracion Full + Diff 2',             '-i restauracion/deporte/04_restore_full_diff2.sql')
    '16_eliminar_antes_full_diff3' = @('Eliminar base (antes de Full + Diff 3)', '-i restauracion/deporte/01_eliminar_base.sql')
    '17_restore_full_diff3'        = @('Restauracion Full + Diff 3',             '-i restauracion/deporte/05_restore_full_diff3.sql')
}

function Wait-TerminalAlFrente {
    # Si la terminal no esta al frente se intenta traerla (sin bloquear).
    $intentos = 0
    while ([Win32.Ventana]::GetForegroundWindow() -ne $script:Terminal -and $intentos -lt 5) {
        [Win32.Ventana]::SetForegroundWindow($script:Terminal) | Out-Null
        Start-Sleep -Milliseconds 300
        $intentos++
    }
}

function Save-Pantalla {
    param([string]$Nombre)
    if ($ProbarCon) { return }
    Wait-TerminalAlFrente
    Start-Sleep -Milliseconds $PausaMs
    Wait-TerminalAlFrente
    # Se captura solo la franja de pantalla de la terminal: su ancho, desde su
    # borde superior hasta el borde inferior de la pantalla (para incluir la
    # barra de tareas con el reloj). Asi no salen las ventanas de al lado.
    $p = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $r = New-Object 'int[]' 4
    [Win32.Ventana]::GetWindowRect($script:Terminal, $r) | Out-Null
    $x0 = [math]::Max($p.Left, $r[0]); $y0 = [math]::Max($p.Top, $r[1]); $x1 = [math]::Min($p.Right, $r[2])
    if (($x1 - $x0) -lt 200) { $x0 = $p.Left; $y0 = $p.Top; $x1 = $p.Right }   # ventana fuera del monitor principal
    $b   = New-Object System.Drawing.Rectangle $x0, $y0, ($x1 - $x0), ($p.Bottom - $y0)
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save((Join-Path (Get-Location) (Join-Path $DirCapturas $Nombre)), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# --- Paginacion ----------------------------------------------------------
function Get-Tamano {
    try   { $w = $Host.UI.RawUI.WindowSize; if ($w.Height -gt 10) { return $w } } catch {}
    return New-Object System.Management.Automation.Host.Size 150, 40
}

function Get-Alto {
    # filas de pantalla que ocupa un conjunto de lineas (las largas se parten)
    param([string[]]$Lineas, [int]$Ancho)
    $n = 0
    foreach ($l in $Lineas) { $n += [math]::Max(1, [math]::Ceiling($l.Length / $Ancho)) }
    return $n
}

function Split-Bloques {
    # un bloque = un conjunto de resultados de sqlcmd (termina en "(N rows affected)")
    param([string[]]$Lineas)
    $bloques = @(); $actual = @()
    foreach ($l in $Lineas) {
        $actual += $l
        if ($l -match '^\(\d[\d,.]* rows? affected\)') { $bloques += ,$actual; $actual = @() }
    }
    if ($actual.Count) { $bloques += ,$actual }
    return ,$bloques
}

function Get-Paginas {
    param([string[]]$Lineas, [int]$Ancho, [int]$Alto)
    $paginas = @(); $pag = @()
    foreach ($b in (Split-Bloques $Lineas)) {
        $b = @($b | Where-Object { $_ -ne $null })
        if ((Get-Alto $b $Ancho) -gt $Alto) {
            # tabla mas alta que la pantalla: primeras filas + aviso + ultimas filas
            $cola   = 6
            $cabeza = @(); $i = 0
            while ($i -lt $b.Count -and (Get-Alto ($cabeza + $b[$i]) $Ancho) -le ($Alto - $cola - 2)) { $cabeza += $b[$i]; $i++ }
            $omit = $b.Count - $cabeza.Count - $cola
            if ($omit -gt 0) {
                $b = $cabeza + "   ... ($omit filas mas; salida completa en logs/) ..." + $b[($b.Count - $cola)..($b.Count - 1)]
            }
        }
        if ($pag.Count -and ((Get-Alto ($pag + $b) $Ancho) -gt $Alto)) { $paginas += ,$pag; $pag = @() }
        $pag += $b
    }
    if ($pag.Count) { $paginas += ,$pag }
    return ,$paginas
}

function Show-Paso {
    param([string]$Slug, [string]$Titulo, [string]$Comando, [string[]]$Salida, [string]$Pie = '')
    $t = Get-Tamano
    $paginas = Get-Paginas -Lineas $Salida -Ancho $t.Width -Alto ($t.Height - 7)
    $i = 0
    foreach ($p in $paginas) {
        $i++; $script:NumCaptura++
        Clear-Host
        Write-Host ("{0}   |   {1}   |   pantalla {2}/{3}" -f (Get-Date -Format 'dddd dd/MM/yyyy HH:mm:ss'), $Titulo, $i, $paginas.Count) -ForegroundColor Yellow
        Write-Host "PS> $Comando" -ForegroundColor Cyan
        Write-Host ''
        $p | ForEach-Object { Write-Host $_ }
        if ($Pie -and $i -eq $paginas.Count) { Write-Host ''; Write-Host $Pie -ForegroundColor Green }
        $png = "deporte_{0:D3}_{1}_{2:D2}.png" -f $script:NumCaptura, $Slug, $i
        Save-Pantalla $png
        $script:Indice += [pscustomobject]@{ Paso = ($Titulo -replace '\s+\|\s+ejecutado.*$', ''); Archivo = $png; Pantalla = "$i/$($paginas.Count)" }
    }
}

# --- Modo prueba: solo paginar un log existente --------------------------
if ($ProbarCon) {
    Show-Paso -Slug 'prueba' -Titulo 'PRUEBA' -Comando "(log) $ProbarCon" -Salida (Get-Content $ProbarCon)
    Write-Host "`n[prueba] pantallas generadas: $script:NumCaptura"
    return
}

# --- Modo -SoloCapturas --------------------------------------------------
# No ejecuta nada contra la base: muestra, pantalla por pantalla, la salida
# REAL que la ultima corrida dejo en logs/captura_deporte_*.log y la captura.
# Dura alrededor de un minuto. Cada pantalla indica cuando se ejecuto el paso
# (hora del log) y cuando se tomo la captura (hora actual).
if ($SoloCapturas) {
    $faltan = @($Catalogo.Keys | Where-Object { -not (Test-Path "logs/captura_deporte_$_.log") })
    if ($faltan.Count) { throw "Faltan logs de la corrida ($($faltan -join ', ')). Correr primero el script sin -SoloCapturas." }
    $tiempos = @{}
    if (Test-Path 'docs/deporte/tiempos_restore_deporte.csv') {
        Import-Csv 'docs/deporte/tiempos_restore_deporte.csv' | ForEach-Object { $tiempos[$_.restauracion] = $_.tiempo_s }
    }
    Clear-Host
    Write-Host 'Se van a tomar las capturas de los resultados ya guardados (aprox. 1 minuto).' -ForegroundColor Yellow
    Write-Host 'Deja ESTA ventana al frente y no toques nada hasta que diga "Listo".'
    Read-Host 'Presiona ENTER para empezar' | Out-Null
    $script:Terminal = [Win32.Ventana]::GetForegroundWindow()   # la ventana donde se acaba de pulsar ENTER
    foreach ($slug in $Catalogo.Keys) {
        $log = Get-Item "logs/captura_deporte_$slug.log"
        $tit = $Catalogo[$slug][0]
        $pie = ''
        $clave = $tit -replace '^Restauracion ', ''
        if ($tit -like 'Restauracion*' -and $tiempos.ContainsKey($clave)) { $pie = "Tiempo de restauracion [$clave] = $($tiempos[$clave]) s" }
        Show-Paso -Slug $slug -Titulo ("Deporte - $tit   |   ejecutado " + $log.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss')) `
                  -Comando ("sqlcmd -S $Servidor -U $Usuario -P ******** -W " + $Catalogo[$slug][1]) `
                  -Salida (Get-Content $log.FullName -Encoding UTF8) -Pie $pie
    }
    $script:NumCaptura++
    Clear-Host
    Write-Host ("{0}   |   Deporte - Tabla de tiempos de restauracion" -f (Get-Date -Format 'dddd dd/MM/yyyy HH:mm:ss')) -ForegroundColor Yellow
    Import-Csv 'docs/deporte/tiempos_restore_deporte.csv' | Format-Table -AutoSize | Out-Host
    Get-ChildItem 'C:\backups_olimpiadas' -Filter '*deporte*' -ErrorAction SilentlyContinue |
        Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } }, LastWriteTime | Format-Table -AutoSize | Out-Host
    $png = "deporte_{0:D3}_tiempos.png" -f $script:NumCaptura
    Save-Pantalla $png
    $script:Indice += [pscustomobject]@{ Paso = 'Deporte - Tabla de tiempos de restauracion'; Archivo = $png; Pantalla = '1/1' }
    Write-Indice
    Write-Host "Listo: $script:NumCaptura capturas en $DirCapturas" -ForegroundColor Green
    return
}

# --- Ejecucion de un paso ------------------------------------------------
function Invoke-Paso {
    param([string]$Slug, [string]$Titulo, [string[]]$Scripts, [switch]$ConBase, [switch]$ConVariable, [switch]$Medir)
    $todo = @(); $cmds = @()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($s in $Scripts) {
        $a = @('-S', $Servidor, '-U', $Usuario, '-P', $Password, '-W')
        if ($ConVariable) { $a += @('-v', "DbNombre=$Base") }
        if ($ConBase)     { $a += @('-d', $Base) }
        $a += @('-i', $s)
        $cmds += "sqlcmd -S $Servidor -U $Usuario -P ******** -W " + $(if ($ConVariable) { "-v DbNombre=$Base " }) + $(if ($ConBase) { "-d $Base " }) + "-i $s"
        $todo += @(& sqlcmd @a 2>&1 | ForEach-Object { "$_" })
    }
    $sw.Stop()
    $todo | Set-Content -Path "logs/captura_deporte_$Slug.log" -Encoding UTF8
    $errores = @($todo | Where-Object { $_ -match '^Msg \d+' })
    $pie = ''
    if ($Medir) {
        $seg = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        $pie = "Tiempo de restauracion [$Titulo] = $seg s"
        $script:Tiempos += [pscustomobject]@{ tipo_carga = 'Deporte'; restauracion = $Titulo; fecha_hora = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); tiempo_s = $seg }
    }
    Show-Paso -Slug $Slug -Titulo "Deporte - $Titulo" -Comando ($cmds -join '; ') -Salida $todo -Pie $pie
    if ($errores.Count) { throw "El paso '$Titulo' devolvio errores de SQL: $($errores[0]). Ver logs/captura_deporte_$Slug.log" }
}

$script:Tiempos = @()

Invoke-Paso -Slug '00_ddl' -Titulo 'Base y esquema' -ConVariable `
    -Scripts 'ddl/01_crear_base_datos.sql', 'ddl/02_esquema_staging.sql', 'ddl/03_modelo_relacional.sql'
Invoke-Paso -Slug '01_staging' -Titulo 'Staging y procedimiento' -ConBase `
    -Scripts 'carga/deporte/01_cargar_staging.sql', 'carga/deporte/02_proc_cargar_deporte.sql'

Invoke-Paso -Slug '02_carga1'  -Titulo 'Carga 1 - Paris 2024'     -ConBase -Scripts 'carga/deporte/03_carga_1_paris_2024.sql'
Invoke-Paso -Slug '03_full'    -Titulo 'Backup FULL'              -ConBase -Scripts 'backup/deporte/01_full_deporte.sql'
Invoke-Paso -Slug '04_carga2'  -Titulo 'Carga 2 - Tokio 2020'     -ConBase -Scripts 'carga/deporte/04_carga_2_tokio_2020.sql'
Invoke-Paso -Slug '05_diff1'   -Titulo 'Backup DIFERENCIAL 1'     -ConBase -Scripts 'backup/deporte/02_dif_deporte_1.sql'
Invoke-Paso -Slug '06_carga3'  -Titulo 'Carga 3 - Rio 2016'       -ConBase -Scripts 'carga/deporte/05_carga_3_rio_2016.sql'
Invoke-Paso -Slug '07_diff2'   -Titulo 'Backup DIFERENCIAL 2'     -ConBase -Scripts 'backup/deporte/03_dif_deporte_2.sql'
Invoke-Paso -Slug '08_carga4'  -Titulo 'Carga 4 - Londres 2012'   -ConBase -Scripts 'carga/deporte/06_carga_4_londres_2012.sql'
Invoke-Paso -Slug '09_diff3'   -Titulo 'Backup DIFERENCIAL 3'     -ConBase -Scripts 'backup/deporte/04_dif_deporte_3.sql'

$Restores = @(
    @{ Slug = 'full';       Titulo = 'Full';          Script = '02_restore_solo_full.sql'  }
    @{ Slug = 'full_diff1'; Titulo = 'Full + Diff 1'; Script = '03_restore_full_diff1.sql' }
    @{ Slug = 'full_diff2'; Titulo = 'Full + Diff 2'; Script = '04_restore_full_diff2.sql' }
    @{ Slug = 'full_diff3'; Titulo = 'Full + Diff 3'; Script = '05_restore_full_diff3.sql' }
)
$n = 10
foreach ($r in $Restores) {
    Invoke-Paso -Slug ("{0:D2}_eliminar_antes_{1}" -f $n, $r.Slug) -Titulo "Eliminar base (antes de $($r.Titulo))" `
        -Scripts 'restauracion/deporte/01_eliminar_base.sql'
    $n++
    Invoke-Paso -Slug ("{0:D2}_restore_{1}" -f $n, $r.Slug) -Titulo $r.Titulo -Medir `
        -Scripts "restauracion/deporte/$($r.Script)"
    $n++
}

# --- Tabla de tiempos ----------------------------------------------------
$script:Tiempos | Export-Csv -Path 'docs/deporte/tiempos_restore_deporte.csv' -NoTypeInformation -Encoding UTF8
$script:NumCaptura++
Clear-Host
Write-Host ("{0}   |   Deporte - Tabla de tiempos de restauracion" -f (Get-Date -Format 'dddd dd/MM/yyyy HH:mm:ss')) -ForegroundColor Yellow
$script:Tiempos | Format-Table -AutoSize | Out-Host
Get-ChildItem 'C:\backups_olimpiadas' -Filter '*deporte*' -ErrorAction SilentlyContinue |
    Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } } | Format-Table -AutoSize | Out-Host
$png = "deporte_{0:D3}_tiempos.png" -f $script:NumCaptura
Save-Pantalla $png
$script:Indice += [pscustomobject]@{ Paso = 'Deporte - Tabla de tiempos de restauracion'; Archivo = $png; Pantalla = '1/1' }
Write-Indice

Write-Host "Listo: $script:NumCaptura capturas en $DirCapturas\ , logs en logs\captura_deporte_*.log" -ForegroundColor Green
