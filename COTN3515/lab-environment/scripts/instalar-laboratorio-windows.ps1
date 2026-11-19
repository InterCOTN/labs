<#
.SYNOPSIS
  Instalacion DESATENDIDA del laboratorio COTN 3515 en Windows 10/11 (64 bits).
.DESCRIPTION
  Deja la computadora lista para todos los laboratorios (M2-M10) sin preguntas:
    1. Comprueba requisitos (Windows, RAM, CPU, virtualizacion, espacio, internet).
    2. Activa WSL 2 y la plataforma de maquina virtual.
    3. Instala Git y Python 3.12 (versiones fijas) y Docker Desktop.
    4. Configura la memoria de WSL y vm.max_map_count (Wazuh).
    5. Mide la velocidad de escritura del disco (informativo).
    6. Descarga las imagenes y levanta M9, M10, M5, M3 y el objetivo de escaneo; cada uno debe quedar sano.
    7. Prueba Wazuh (el agente debe quedar Active) y lo apaga.
    8. Prueba Greenbone: descarga las imagenes y deja el feed SINCRONIZADO en el disco (tarda ~40 min o mas),
       y lo apaga SIN borrar volumenes: en clase `setup.py up` arranca con el feed ya listo.
  Si hay que reiniciar, lo hace solo y continua al iniciar sesion de nuevo (tarea programada temporal).
  Es repetible: si falla o se interrumpe, vuelva a ejecutarlo y continua en el paso que fallo.
  Registro: C:\ProgramData\COTN3515\  (instalacion-AAAAMMDD.log, resumen.txt)
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\instalar-laboratorio-windows.ps1
.EXAMPLE
  # Un solo comando (repositorio publico, sin token):
  iwr -UseBasicParsing https://raw.githubusercontent.com/InterCOTN/labs/main/COTN3515/lab-environment/scripts/instalar-laboratorio-windows.ps1 -OutFile $env:TEMP\instalar.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\instalar.ps1
.NOTES
  Es AUTONOMO: basta este archivo. Si no esta dentro de la carpeta lab-environment, clona el material del
  laboratorio desde https://github.com/InterCOTN/labs (publico). Use -Rama para elegir la rama (por defecto main).
  Ejecutelo con la cuenta del estudiante (con permisos de administrador): pedira elevacion una vez.
  Docker Desktop tiene condiciones de licencia para uso institucional: confirmelas con TI.
#>
[CmdletBinding()]
param(
    [int]$MemoryGB = 12,
    [int]$Processors = 4,
    [int]$SwapGB = 2,
    [int]$MinDiskMBs = 5,
    [string]$Rama = 'main',
    [string]$Carpeta = '',
    [switch]$Reanudar,
    [switch]$Elevado
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$env:PYTHONIOENCODING = 'utf-8'

# --- Elevacion (una sola vez) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -MemoryGB $MemoryGB -Processors $Processors -SwapGB $SwapGB -MinDiskMBs $MinDiskMBs -Rama `"$Rama`""
    if ($Carpeta) { $a += " -Carpeta `"$Carpeta`"" }
    if ($Reanudar) { $a += ' -Reanudar' }
    $a += ' -Elevado'
    Write-Host 'Se abrira una ventana de administrador donde corre el instalador y permanecera abierta al terminar.'
    Write-Host "Progreso en vivo desde cualquier ventana: Get-Content C:\ProgramData\COTN3515\resumen.txt"
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    exit $LASTEXITCODE
}

$Data = Join-Path $env:ProgramData 'COTN3515'
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$RootFile = Join-Path $Data 'carpeta-laboratorio.txt'
$RepoDir  = 'C:\COTN3515\labs'
# Carpeta lab-environment: la recordada (al reanudar), -Carpeta, la que contiene este script, o la que se descarga de GitHub.
if (Test-Path $RootFile) { $Root = (Get-Content $RootFile -Raw).Trim() }
elseif ($Carpeta) { $Root = $Carpeta }
elseif (Test-Path (Join-Path $PSScriptRoot '..\compose.yaml')) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
else { $Root = Join-Path $RepoDir 'COTN3515\lab-environment' }
$DoneFile = Join-Path $Data 'pasos-completados.txt'
$Summary  = Join-Path $Data 'resumen.txt'
$Log      = Join-Path $Data ('instalacion-' + (Get-Date -Format 'yyyyMMdd') + '.log')
$TaskName = 'COTN3515-Instalacion'
$script:CurrentStep = ''
Start-Transcript -Path $Log -Append | Out-Null

# Evita que la computadora se suspenda mientras el script corre (se revierte solo al terminar).
Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);' -ErrorAction SilentlyContinue
[void][Win32.Power]::SetThreadExecutionState([uint32]2147483649)

function Log([string]$m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Note([string]$m) { Add-Content -Path $Summary -Value ("{0} {1}" -f (Get-Date -Format 's'), $m) }
function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
# Ejecuta un programa nativo sin que PowerShell 5.1 trate stderr como error. Devuelve Code y Out.
function Exec([string]$File, [string[]]$ArgList, [switch]$AllowFail, [switch]$Live) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $code = 0
    try {
        $out = (& $File @ArgList 2>&1 | ForEach-Object { if ($Live) { Write-Host "$_" }; "$_" }) | Out-String
        $code = $LASTEXITCODE
    } catch {
        # El programa no existe (p. ej. git aun no instalado): con -AllowFail se informa como codigo 9009.
        if (-not $AllowFail) { throw }
        $out = $_.Exception.Message; $code = 9009
    } finally { $ErrorActionPreference = $old }
    $out = $out -replace "`0", ''                    # wsl.exe escribe UTF-16: quita los NUL
    if ($code -ne 0 -and -not $AllowFail) { throw ("{0} {1} termino con codigo {2}`n{3}" -f $File, ($ArgList -join ' '), $code, $out) }
    [pscustomobject]@{ Code = $code; Out = $out }
}
function Download([string]$Url, [string]$Dest) {
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
            if ((Get-Item $Dest).Length -gt 1MB) {
                Log ("Descargado {0} ({1} MB, SHA256 {2})" -f (Split-Path $Dest -Leaf), [math]::Round((Get-Item $Dest).Length / 1MB), (Get-FileHash $Dest -Algorithm SHA256).Hash)
                return
            }
        } catch { Log "Intento $i fallo: $($_.Exception.Message)" }
        Start-Sleep -Seconds (5 * $i)
    }
    throw "No se pudo descargar $Url (revise la conexion a internet y el proxy)."
}
function Register-Resume {
    $who = "$env:USERDOMAIN\$env:USERNAME"
    $copy = Join-Path $Data 'instalar-laboratorio-windows.ps1'          # copia estable: el original puede estar en un USB o en Descargas
    if ($PSCommandPath -ne $copy) { Copy-Item -Path $PSCommandPath -Destination $copy -Force }
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -MemoryGB {1} -Processors {2} -SwapGB {3} -MinDiskMBs {4} -Reanudar' -f $copy, $MemoryGB, $Processors, $SwapGB, $MinDiskMBs)
    $trg = New-ScheduledTaskTrigger -AtLogOn -User $who
    $pri = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -Principal $pri -Force | Out-Null
}
function Request-Reboot([string]$Why) {
    Add-Content -Path $DoneFile -Value $script:CurrentStep       # el paso cuenta como hecho: al volver continua con el siguiente
    Register-Resume
    Note "reinicio: $Why"
    Log "Reinicio necesario ($Why). La computadora se reiniciara en 15 s; inicie sesion con la misma cuenta y el proceso continua solo."
    Stop-Transcript | Out-Null
    Start-Sleep -Seconds 15
    Restart-Computer -Force
    exit 0
}
function Step([string]$Name, [scriptblock]$Body) {
    $done = @(); if (Test-Path $DoneFile) { $done = @(Get-Content $DoneFile) }
    if ($done -contains $Name) { Log "Paso '$Name': ya hecho."; return }
    Log "=== Paso '$Name' ==="
    $script:CurrentStep = $Name
    Update-Path
    $t0 = Get-Date
    & $Body
    $min = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
    Add-Content -Path $DoneFile -Value $Name
    Note "paso $Name OK ($min min)"
    Log "Paso '$Name' terminado en $min min."
}
function Update-Wsl {
    $r = Exec 'wsl' @('--update') -AllowFail
    Log ("wsl --update: codigo {0} {1}" -f $r.Code, $r.Out.Trim())
    $v = Exec 'wsl' @('--version') -AllowFail
    if ($r.Code -ne 0 -or $v.Code -ne 0) {
        Log 'Reintentando con --web-download...'
        $r = Exec 'wsl' @('--update', '--web-download') -AllowFail
        Log ("wsl --update --web-download: codigo {0} {1}" -f $r.Code, $r.Out.Trim())
        $v = Exec 'wsl' @('--version') -AllowFail
    }
    if ($v.Code -ne 0) { throw "No se pudo actualizar WSL. Ejecute 'wsl --update' como administrador y envie la salida.`n$($r.Out)" }
    Note ('wsl: ' + (($v.Out -split "`r?`n" | Select-Object -First 1).Trim()))
    Exec 'wsl' @('--shutdown') -AllowFail | Out-Null
}
function Wait-Docker([int]$TimeoutMin) {
    $end = (Get-Date).AddMinutes($TimeoutMin)
    $script:DockerErr = ''
    do {
        $r = Exec 'docker' @('info', '--format', '{{.ServerVersion}}') -AllowFail
        if ($r.Code -eq 0 -and $r.Out.Trim()) { return $true }
        $script:DockerErr = $r.Out
        if ((Get-Date) -ge $end) { break }
        Start-Sleep -Seconds 10
    } while ($true)
    return $false
}
function Ensure-Docker {
    # Docker Desktop no siempre esta abierto al reanudar (otro dia, otro inicio de sesion).
    if (Wait-Docker 0) { return }
    Log 'Docker no esta corriendo: abriendo Docker Desktop...'
    if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    }
    if (-not (Wait-Docker 10)) { throw "Docker no arranco en 10 min. Ultimo error:`n$script:DockerErr" }
}
function Compose([string[]]$ComposeArgs, [switch]$AllowFail) {
    Push-Location $Root
    try { Exec 'docker' (@('compose') + $ComposeArgs) -AllowFail:$AllowFail } finally { Pop-Location }
}
function PyRun([string[]]$PyArgs, [switch]$AllowFail, [switch]$Live) {
    Push-Location $Root
    try { Exec 'py' (@('-3', '-X', 'utf8') + $PyArgs) -AllowFail:$AllowFail -Live:$Live } finally { Pop-Location }
}

try {
    Log "COTN 3515 - instalacion desatendida. Carpeta del laboratorio: $Root"
    if ($Reanudar) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue }

    # Al repetir o reanudar, actualiza el material ya descargado (los pasos hechos no lo vuelven a bajar).
    if (Test-Path (Join-Path $RepoDir '.git')) {
        $g = Exec 'git' @('-C', $RepoDir, 'pull', '--ff-only') -AllowFail
        if ($g.Code -eq 0) { Log ("Material actualizado: " + ($g.Out.Trim() -split "`n")[-1]) }
        else { Log "No se pudo actualizar el material (se usa la copia existente): $($g.Out.Trim())" }
    }

    Step 'requisitos' {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $build = [int]$os.BuildNumber
        if (-not [Environment]::Is64BitOperatingSystem) { throw 'Se requiere Windows de 64 bits.' }
        if ($build -lt 19041) { throw "Windows demasiado antiguo (build $build). Se requiere Windows 10 22H2 o Windows 11." }
        $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB)
        $cpu = [int]$cs.NumberOfLogicalProcessors
        if ($ram -lt 15) { throw "RAM insuficiente: $ram GB (minimo 16)." }
        if ($cpu -lt 4) { throw "Procesadores insuficientes: $cpu (minimo 4)." }
        $drive = (Split-Path $Root -Qualifier)
        $free = [math]::Round((Get-PSDrive ($drive.TrimEnd(':'))).Free / 1GB)
        if ($free -lt 100) { throw "Espacio libre insuficiente en ${drive}: $free GB (minimo 100)." }
        $virt = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
        if (-not $virt -and -not $cs.HypervisorPresent) { throw 'La virtualizacion esta apagada en la BIOS/UEFI. Activela y repita.' }
        foreach ($u in 'https://github.com', 'https://ghcr.io', 'https://raw.githubusercontent.com') {
            try { Invoke-WebRequest -UseBasicParsing -Uri $u -Method Head -TimeoutSec 30 | Out-Null } catch { if (-not $_.Exception.Response) { throw "Sin acceso a $u (internet o proxy)." } }
        }
        Note "equipo: build $build, $ram GB RAM, $cpu CPU, libre $free GB en $drive, usuario $env:USERNAME"
        Log "Requisitos OK: build $build, $ram GB RAM, $cpu CPU, $free GB libres."
    }

    Step 'git' {
        $r = Exec 'git' @('--version') -AllowFail
        if ($r.Code -ne 0) {
            $f = Join-Path $env:TEMP 'Git-2.47.1-64-bit.exe'
            Download 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe' $f
            Start-Process -FilePath $f -ArgumentList '/VERYSILENT', '/NORESTART', '/SP-', '/NOCANCEL', '/SUPPRESSMSGBOXES' -Wait
            Update-Path
        }
        $v = (Exec 'git' @('--version')).Out.Trim(); Note $v
    }

    Step 'material' {
        if (-not (Test-Path (Join-Path $Root 'compose.yaml'))) {
            if (Test-Path $RepoDir) { throw "$RepoDir ya existe pero no contiene el laboratorio. Renombrelo o borrelo y repita." }
            New-Item -ItemType Directory -Force -Path (Split-Path $RepoDir -Parent) | Out-Null
            Exec 'git' @('clone', '--depth', '1', '--branch', $Rama, 'https://github.com/InterCOTN/labs.git', $RepoDir) | Out-Null
            Note "material descargado de la rama $Rama"
        }
        if (-not (Test-Path (Join-Path $Root 'compose.yaml'))) { throw "No existe $Root\compose.yaml despues de descargar." }
        Set-Content -Path $RootFile -Value $Root -Encoding ASCII
        Note "carpeta del laboratorio: $Root"
    }

    Step 'wsl' {
        $need = $false
        foreach ($f in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') {
            $st = (Get-WindowsOptionalFeature -Online -FeatureName $f).State
            if ($st -ne 'Enabled') {
                $r = Exec 'dism.exe' @('/online', '/enable-feature', "/featurename:$f", '/all', '/norestart') -AllowFail
                if ($r.Code -ne 0 -and $r.Code -ne 3010) { throw "No se pudo activar $f (codigo $($r.Code))`n$($r.Out)" }
                $need = $true
            }
        }
        if ($need) { Request-Reboot 'activar WSL 2 y la plataforma de maquina virtual' }
    }

    Step 'python' {
        $r = Exec 'py' @('-3.12', '--version') -AllowFail
        if ($r.Code -ne 0) {
            $f = Join-Path $env:TEMP 'python-3.12.8-amd64.exe'
            Download 'https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe' $f
            Start-Process -FilePath $f -ArgumentList '/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_launcher=1', 'Include_test=0' -Wait
            Update-Path
        }
        $v = (Exec 'py' @('-3.12', '--version')).Out.Trim(); Note $v
    }

    Step 'wslconfig' {
        & (Join-Path $Root 'scripts\configurar-wsl.ps1') -MemoryGB $MemoryGB -Processors $Processors -SwapGB $SwapGB -NoRestart
        Note "wslconfig: $MemoryGB GB, $Processors CPU, swap $SwapGB GB"
    }

    Step 'docker-instalar' {
        if (-not (Test-Path "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe")) {
            Update-Wsl
            Exec 'wsl' @('--set-default-version', '2') -AllowFail | Out-Null
            $f = Join-Path $env:TEMP 'DockerDesktopInstaller.exe'
            Download 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe' $f
            $p = Start-Process -FilePath $f -ArgumentList 'install', '--quiet', '--accept-license', '--backend=wsl-2' -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "El instalador de Docker Desktop termino con codigo $($p.ExitCode)." }
        }
        $me = "$env:USERDOMAIN\$env:USERNAME"
        $inGroup = $false
        try { $inGroup = [bool](Get-LocalGroupMember -Group 'docker-users' -ErrorAction Stop | Where-Object { $_.Name -ieq $me }) } catch { }
        if (-not $inGroup) {
            Add-LocalGroupMember -Group 'docker-users' -Member $me -ErrorAction SilentlyContinue
            Request-Reboot 'agregar el usuario al grupo docker-users y terminar la instalacion de Docker Desktop'
        }
    }

    Step 'docker-motor' {
        Update-Wsl
        # Docker Desktop pudo arrancar antes con un WSL viejo: se cierra y se vuelve a abrir.
        Get-Process -Name 'Docker Desktop', 'com.docker.backend' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Start-Process -FilePath "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        if (-not (Wait-Docker 10)) { throw "Docker no arranco en 10 min. Ultimo error:`n$script:DockerErr" }
        Exec 'docker' @('run', '--rm', 'hello-world') | Out-Null
        Note ((Exec 'docker' @('--version')).Out.Trim())
        Note ((Exec 'docker' @('compose', 'version')).Out.Trim())
        $mem = [math]::Round([double](Exec 'docker' @('info', '--format', '{{.MemTotal}}')).Out.Trim() / 1GB, 1)
        Note "memoria de Docker: $mem GiB"
        if ($mem -lt 11) { throw "Docker solo tiene $mem GiB (se esperaban ~12). Revise %USERPROFILE%\.wslconfig y reinicie WSL." }
        Exec 'docker' @('pull', 'alpine:3.20') | Out-Null          # evita que los mensajes de descarga se mezclen con la salida
        $mmOut = (Exec 'docker' @('run', '--rm', '--privileged', 'alpine:3.20', 'sysctl', '-n', 'vm.max_map_count')).Out
        $mm = ($mmOut -split "`r?`n" | Where-Object { $_.Trim() -match '^\d+$' } | Select-Object -Last 1)
        if (-not $mm) { throw "No pude leer vm.max_map_count:`n$mmOut" }
        if ([int]$mm -lt 262144) {
            Log "vm.max_map_count=$mm; se ajusta ahora (el .wslconfig no lo aplico)."
            Exec 'docker' @('run', '--rm', '--privileged', '--pid=host', 'alpine:3.20', 'sysctl', '-w', 'vm.max_map_count=262144') | Out-Null
            Note 'vm.max_map_count ajustado en caliente (se pierde al reiniciar Docker)'
        } else { Note "vm.max_map_count=$mm (persistente por .wslconfig)" }
    }

    Step 'disco' {
        Ensure-Docker
        $imgs = (Compose @('config', '--images')).Out -split "`r?`n" | Where-Object { $_ -match 'redfaro-lab' }
        Compose @('pull') | Out-Null
        $img = $imgs | Select-Object -First 1
        $speeds = @()
        1..2 | ForEach-Object {
            $r = Exec 'docker' @('run', '--rm', '--entrypoint', 'sh', $img, '-c', 'dd if=/dev/zero of=/t bs=1M count=100 oflag=dsync 2>&1 | tail -1')
            if ($r.Out -match '([\d\.,]+)\s*(kB|MB|GB)/s') {
                $n = [double]($Matches[1] -replace ',', '.')
                $speeds += switch ($Matches[2]) { 'kB' { $n / 1000 } 'GB' { $n * 1000 } default { $n } }
            } else { throw "No pude leer la velocidad del disco:`n$($r.Out)" }
        }
        $min = [math]::Round(($speeds | Measure-Object -Minimum).Minimum)
        Note "disco (dd dsync, minimo de 2): $min MB/s"
        Log "Velocidad de escritura del disco: $min MB/s (minimo $MinDiskMBs)."
        # La prueba (dd con dsync) mide latencia de escritura: un disco duro mecanico da ~20 MB/s sea SMR o CMR, asi que
        # solo informa. Lo que decide es la prueba real: agente de Wazuh Active y sincronizacion de Greenbone.
        if ($min -lt 50) { Log "AVISO: disco lento para escrituras sincronas ($min MB/s). Se continua; Wazuh y Greenbone diran si rinde." }
        if ($min -lt $MinDiskMBs) { throw "Disco inutilizable ($min MB/s; minimo $MinDiskMBs). Revise el disco." }
    }

    Step 'laboratorios' {
        Ensure-Docker
        $envs = @(
            @{ n = 'M9';   f = @() },
            @{ n = 'M10';  f = @('-f', 'compose.m10.yaml') },
            @{ n = 'M5';   f = @('-f', 'compose.m5.yaml') },
            @{ n = 'M3';   f = @('-f', 'compose.m3.yaml') },
            @{ n = 'scan'; f = @('-f', 'compose.scan.yaml') }
        )
        foreach ($e in $envs) {
            Log "Probando $($e.n)..."
            # 'up --wait' falla si algun servicio no queda sano (todos tienen healthcheck o corren de forma continua).
            $r = Compose ($e.f + @('up', '-d', '--wait')) -AllowFail
            $ps = (Compose ($e.f + @('ps', '-a', '--format', '{{.Name}} {{.State}}')) -AllowFail).Out
            Write-Host $ps
            Compose ($e.f + @('down', '-v')) -AllowFail | Out-Null
            if ($r.Code -ne 0) { throw "El entorno $($e.n) no arranco sano:`n$($r.Out)" }
            $bad = ($ps -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch ' running$' }
            if ($bad) { throw "El entorno $($e.n) tiene servicios que no corren:`n$($bad -join "`n")" }
            Note "entorno $($e.n): OK"
        }
    }

    Step 'wazuh' {
        Ensure-Docker
        $t0 = Get-Date
        $r = PyRun @('presencial\wazuh\setup.py', 'up'); Write-Host $r.Out
        $ok = $false
        $end = (Get-Date).AddMinutes(30)
        while ((Get-Date) -lt $end) {
            $a = Exec 'docker' @('exec', 'wazuh-wazuh.manager-1', '/var/ossec/bin/agent_control', '-l') -AllowFail
            if ($a.Out -match 'costa-norte-ubuntu-01.*Active') { $ok = $true; break }
            Start-Sleep -Seconds 20
        }
        $min = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
        if (-not $ok) {
            Log (Exec 'docker' @('ps', '-a') -AllowFail).Out
            PyRun @('presencial\wazuh\setup.py', 'down') -AllowFail | Out-Null
            throw "El agente costa-norte-ubuntu-01 no quedo Active en 30 min."
        }
        Note "wazuh: agente Active en $min min"
        PyRun @('presencial\wazuh\setup.py', 'down') | Out-Null
    }

    Step 'greenbone' {
        Ensure-Docker
        $t0 = Get-Date
        Compose @('-f', 'compose.scan.yaml', 'up', '-d', '--wait') | Out-Null
        $r = PyRun @('presencial\greenbone\setup.py', 'up') -Live
        foreach ($c in 'greenbone-ospd-openvas-1', 'greenbone-openvasd-1') {
            if (-not (Exec 'docker' @('ps', '--filter', "name=$c", '--filter', 'status=running', '-q') -AllowFail).Out.Trim()) { throw "El scanner no arranco: $c no esta corriendo (docker ps -a)." }
        }
        Note ("greenbone: imagenes descargadas y arrancado en {0} min" -f [math]::Round(((Get-Date) - $t0).TotalMinutes, 1))
        $ok = $false; $quiet = 0
        # Se cuenta por vueltas (no por reloj): si la computadora se suspende, no se da por vencido el plazo.
        for ($n = 1; $n -le 300 -and -not $ok; $n++) {
            Start-Sleep -Seconds 60
            $run = (Exec 'docker' @('ps', '--filter', 'name=greenbone-gvmd-1', '--filter', 'status=running', '-q') -AllowFail).Out.Trim()
            if (-not $run) { throw 'El contenedor greenbone-gvmd-1 se detuvo durante la sincronizacion.' }
            foreach ($c in 'greenbone-ospd-openvas-1', 'greenbone-openvasd-1') {
                if (-not (Exec 'docker' @('ps', '--filter', "name=$c", '--filter', 'status=running', '-q') -AllowFail).Out.Trim()) { throw "El scanner se detuvo: $c ya no esta corriendo." }
            }
            $logs = (Exec 'docker' @('logs', 'greenbone-gvmd-1') -AllowFail).Out      # log completo: el mensaje puede quedar lejos del final
            if ($logs -match 'Data objects feed sync finished') {
                $busy = $false
                foreach ($line in ((Exec 'docker' @('stats', '--no-stream', '--format', '{{.Name}} {{.CPUPerc}}') -AllowFail).Out -split "`r?`n")) {
                    if ($line -match '^greenbone-(gvmd|pg-gvm|ospd-openvas)-1 ([\d\.]+)%' -and [double]$Matches[2] -gt 10) { $busy = $true }
                }
                if ($busy) { $quiet = 0 } else { $quiet++ }
                if ($quiet -ge 3) { $ok = $true }
            }
            Log ("Sincronizando Greenbone... {0} min" -f [math]::Round(((Get-Date) - $t0).TotalMinutes))
        }
        $min = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
        if (-not $ok) { throw "La sincronizacion de Greenbone no termino en 5 h (ultimo estado: revise 'docker logs greenbone-gvmd-1')." }
        Note "greenbone: feed sincronizado ($min min en total)"
        PyRun @('presencial\greenbone\setup.py', 'down') | Out-Null          # sin -v: el feed queda en el disco
        Compose @('-f', 'compose.scan.yaml', 'down', '-v') -AllowFail | Out-Null
    }

    Note 'INSTALACION COMPLETA'
    Log '=========================================='
    Log 'INSTALACION COMPLETA. El laboratorio esta listo.'
    Log "Resumen: $Summary"
    Get-Content $Summary | ForEach-Object { Log "  $_" }
    Stop-Transcript | Out-Null
    if ($Elevado -or $Reanudar) { Read-Host 'Pulse Enter para cerrar esta ventana' }
    exit 0
}
catch {
    Log "FALLO en el paso '$script:CurrentStep': $($_.Exception.Message)"
    Note "FALLO en el paso '$script:CurrentStep': $($_.Exception.Message)"
    Log "Registro completo: $Log   (repita el script para continuar desde este paso)"
    Stop-Transcript | Out-Null
    if ($Elevado -or $Reanudar) { Read-Host 'Pulse Enter para cerrar esta ventana' }
    exit 1
}
