<#
.SYNOPSIS
  Configura la memoria de WSL 2 (la que usa Docker Desktop) en Windows.
.DESCRIPTION
  Crea o actualiza la sección [wsl2] de %USERPROFILE%\.wslconfig con memory, processors y swap.
  - Hace una copia de seguridad del archivo existente antes de tocarlo.
  - Conserva las demás líneas y secciones.
  - Limita la memoria a (RAM total - 4 GB) y los núcleos a los disponibles.
  - Reinicia WSL (wsl --shutdown) al terminar, salvo que uses -NoRestart.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\configurar-wsl.ps1
  powershell -ExecutionPolicy Bypass -File scripts\configurar-wsl.ps1 -MemoryGB 10 -Processors 4 -SwapGB 2
#>
param(
    [int]$MemoryGB = 12,
    [int]$Processors = 4,
    [int]$SwapGB = 2,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'

$cs = Get-CimInstance Win32_ComputerSystem
$totalGB = [int][math]::Floor($cs.TotalPhysicalMemory / 1GB)
$cpus = [int]$cs.NumberOfLogicalProcessors
Write-Host "Esta computadora: $totalGB GB de RAM, $cpus procesadores lógicos."
if ($totalGB -lt 16) {
    Write-Warning "Tiene menos de 16 GB de RAM: Greenbone y Wazuh no son recomendables aquí; use una computadora del laboratorio."
}
$maxMem = $totalGB - 4
if ($maxMem -lt 2) { $maxMem = 2 }
if ($MemoryGB -gt $maxMem) {
    Write-Warning "Memoria pedida ($MemoryGB GB) deja menos de 4 GB al sistema; se usará $maxMem GB."
    $MemoryGB = $maxMem
}
if ($Processors -gt $cpus) { $Processors = $cpus }

$path = Join-Path $env:USERPROFILE '.wslconfig'
$lines = @()
if (Test-Path $path) {
    $backup = "$path.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -Path $path -Destination $backup
    Write-Host "Copia de seguridad: $backup"
    $lines = @(Get-Content -Path $path)
}

function Set-WslKey([string[]]$Lines, [string]$Key, [string]$Value) {
    $list = New-Object System.Collections.Generic.List[string]
    $list.AddRange($Lines)
    $start = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i].Trim() -ieq '[wsl2]') { $start = $i; break }
    }
    if ($start -lt 0) {
        if ($list.Count -gt 0 -and $list[$list.Count - 1].Trim() -ne '') { $list.Add('') }
        $list.Add('[wsl2]')
        $start = $list.Count - 1
    }
    $end = $list.Count
    for ($i = $start + 1; $i -lt $list.Count; $i++) {
        if ($list[$i].Trim().StartsWith('[')) { $end = $i; break }
    }
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($list[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $list[$i] = "$Key=$Value"
            return ,$list.ToArray()
        }
    }
    $list.Insert($start + 1, "$Key=$Value")
    return ,$list.ToArray()
}

$lines = Set-WslKey $lines 'memory' ("{0}GB" -f $MemoryGB)
$lines = Set-WslKey $lines 'processors' "$Processors"
$lines = Set-WslKey $lines 'swap' ("{0}GB" -f $SwapGB)

# ASCII: WSL lee bien el archivo sin BOM (Windows PowerShell 5.1 con UTF8 agrega BOM).
Set-Content -Path $path -Value $lines -Encoding ASCII
Write-Host "`nContenido de ${path}:"
Get-Content -Path $path | ForEach-Object { "  $_" }

if ($NoRestart) {
    Write-Host "`nListo. Ejecute 'wsl --shutdown' y reabra Docker Desktop para aplicar los cambios."
} else {
    Write-Host "`nReiniciando WSL (cierra Docker Desktop si está abierto)..."
    wsl --shutdown
    Write-Host "Listo. Abra Docker Desktop y espere a 'Engine running'."
    Write-Host "Para comprobar la memoria asignada: docker info --format '{{.MemTotal}}'  (bytes)"
}
