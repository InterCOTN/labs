# Asistente todo-en-uno para Windows: prepara el equipo y ejecuta probar_laboratorios_vm.py (pruebas de los laboratorios de COTN 2150 en una VM real).
# Uso: abra PowerShell COMO ADMINISTRADOR en la carpeta del repositorio y ejecute:
#     powershell -ExecutionPolicy Bypass -File tools\probar_laboratorios_vm.ps1
# Parametros opcionales:  -Modules "4,6,10"   -Keep   -Out "informe-vm"   -Driver hyperv|virtualbox   -Backend auto|multipass|wsl
# -Backend auto (por defecto) usa Multipass y, si no funciona en este equipo (p. ej. la red ocupa todo 10.x.x.x), WSL2 con Ubuntu 24.04.
# Hace todo sin pasos manuales: instala winget si falta (modulo oficial Microsoft.WinGet.Client), instala Python, VirtualBox (Windows Home
# o Hyper-V no disponible) y Multipass, actualiza el PATH de esta sesion (no hay que cerrar la terminal) y lanza las pruebas.
param(
    [string]$Modules = "4,5,6,7,8,9,10",
    [switch]$Keep,
    [string]$Out = "informe-vm",
    [ValidateSet("", "hyperv", "virtualbox")][string]$Driver = "",
    [ValidateSet("auto", "multipass", "wsl")][string]$Backend = "auto"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$py = Join-Path $here "probar_laboratorios_vm.py"

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Error "Abra PowerShell como administrador (clic derecho > Ejecutar como administrador) y vuelva a ejecutar."; exit 1 }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Virtualizacion habilitada en el firmware (BIOS/UEFI)
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
# Con Hyper-V activo Windows informa VirtualizationFirmwareEnabled=False aunque la virtualizacion este encendida; por eso se mira tambien HypervisorPresent.
$hvOn = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
if ($cpu.VirtualizationFirmwareEnabled -eq $false -and -not $hvOn) { Write-Warning "La virtualizacion parece desactivada en el BIOS/UEFI. Activela: en Gigabyte Intel, Tweaker > Advanced CPU Settings > Intel Virtualization Technology (VT-x; VT-d no basta); en AMD, SVM Mode o la VM no arrancara." }

# --- winget: si falta, se instala con el modulo oficial de Microsoft
function Ensure-Winget {
    Refresh-Path
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    Write-Host "winget no esta instalado: instalandolo con el modulo oficial Microsoft.WinGet.Client..."
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope AllUsers | Out-Null
        Import-Module Microsoft.WinGet.Client
        Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null
    } catch {
        Write-Warning "No se pudo instalar winget automaticamente: $($_.Exception.Message)"
        Write-Warning "Instale 'Instalador de aplicacion' desde Microsoft Store (o https://aka.ms/getwinget) y vuelva a ejecutar este archivo."
        exit 1
    }
    Refresh-Path
    $wa = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $wa "winget.exe"))) { $env:Path += ";$wa" }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget quedo instalado pero esta sesion no lo ve. Cierre y abra PowerShell (administrador) y vuelva a ejecutar este archivo."
        exit 1
    }
}

function Install-Pkg($id, $nombre) {
    Ensure-Winget
    Write-Host "Instalando $nombre..."
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
    Refresh-Path
}

# --- Python
function Find-Python {
    Refresh-Path
    if (Get-Command py -ErrorAction SilentlyContinue) { return @("py", "-3") }
    foreach ($c in @("python", "python3")) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        # el alias de la Microsoft Store (WindowsApps\python.exe) no es un Python real
        if ($cmd -and $cmd.Source -notmatch "WindowsApps") { return @($c) }
    }
    foreach ($d in @("C:\Program Files\Python312", "C:\Program Files\Python311", "$env:LOCALAPPDATA\Programs\Python\Python312")) {
        if (Test-Path "$d\python.exe") { return @("$d\python.exe") }
    }
    return $null
}
$pyCmd = Find-Python
if (-not $pyCmd) { Install-Pkg "Python.Python.3.12" "Python 3.12"; $pyCmd = Find-Python }
if (-not $pyCmd) { Write-Error "Python se instalo pero no se encuentra. Cierre y abra PowerShell (administrador) y vuelva a ejecutar este archivo."; exit 1 }

# --- Motor de virtualizacion: Hyper-V solo en Pro/Enterprise/Education y habilitado; si no, VirtualBox (no requiere reiniciar)
$edition = (Get-CimInstance Win32_OperatingSystem).Caption
$driver = $Driver
if (-not $driver) {
    $driver = "hyperv"
    if ($edition -match "Home") { $driver = "virtualbox" }
    else {
        $hv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
        if ($hv -and $hv.State -ne "Enabled") {
            Write-Warning "Hyper-V no esta habilitado (habilitarlo requiere reiniciar). Se usara VirtualBox, que no necesita reiniciar."
            $driver = "virtualbox"
        }
    }
}
Write-Host "Windows: $edition -> motor $driver"
if ($driver -eq "virtualbox" -and -not (Test-Path "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe")) { Install-Pkg "Oracle.VirtualBox" "VirtualBox" }

# --- WSL2 (para -Backend wsl o como alternativa automatica si Multipass falla)
if ($Backend -ne "multipass") {
    & wsl --status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Habilitando WSL2 (puede pedir reiniciar Windows; si lo pide, reinicie y vuelva a ejecutar este archivo)..."
        & wsl --install --no-distribution | Out-Host
        & wsl --status *> $null
        if ($LASTEXITCODE -ne 0 -and $Backend -eq "wsl") { Write-Warning "WSL2 aun no esta listo: reinicie Windows y vuelva a ejecutar."; exit 1 }
    }
}

# --- Multipass (si falta, lo instala el propio script de Python con --install)
$runArgs = @("--driver", $driver, "--backend", $Backend, "--modules", $Modules, "--out", $Out)
if ($Backend -ne "wsl" -and -not (Get-Command multipass -ErrorAction SilentlyContinue) -and -not (Test-Path "C:\Program Files\Multipass\bin\multipass.exe")) {
    Ensure-Winget
    $runArgs = @("--install") + $runArgs
}
if ($Keep) { $runArgs += "--keep" }

if ($pyCmd.Count -gt 1) { & $pyCmd[0] $pyCmd[1] $py @runArgs } else { & $pyCmd[0] $py @runArgs }
exit $LASTEXITCODE
