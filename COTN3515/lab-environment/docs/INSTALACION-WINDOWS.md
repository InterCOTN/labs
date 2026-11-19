# Instalación en Windows 10/11 (64 bits)

Sirve para una computadora de estudiante o del laboratorio. Tiempo: 30–60 min más reinicios.

## 0. Requisitos
- Windows 10 (22H2) o 11, 64 bits; virtualización activada en BIOS/UEFI (Administrador de tareas → Rendimiento → CPU → "Virtualización: Habilitado").
- 16 GB de RAM, 4 núcleos, 100 GB libres (mínimo del camino presencial).
- Cuenta con permisos de administrador (solo para instalar).
- Disco **SSD** (o disco duro CMR). Los discos duros SMR (p. ej. Seagate Barracuda ST2000DM008) son demasiado lentos para Wazuh y Greenbone. Prueba rápida de velocidad: `docker run --rm --entrypoint sh ghcr.io/intercotn/redfaro-lab:1.0.1 -c "dd if=/dev/zero of=/t bs=1M count=100 oflag=dsync 2>&1 | tail -1"` (referencia: SSD NVMe ~500 MB/s; disco SMR ~20 MB/s).
- Internet y ~20 GB libres para el primer arranque de Wazuh y Greenbone (descargan imágenes y feeds).

## 1. WSL 2
En PowerShell **como administrador**:
```
wsl --install
```
Reinicia cuando lo pida. Comprueba: `wsl --status` debe indicar "Versión predeterminada: 2".

## 2. Docker Desktop
1. Descarga Docker Desktop para Windows desde docker.com y ejecuta el instalador; deja marcada la opción **WSL 2**.
2. Revisa los términos de licencia de Docker Desktop para el uso de la institución (si hubiera duda, consúltalo con TI).
3. Ábrelo y espera a que el ícono diga "Engine running".
4. Comprueba en PowerShell:
```
docker --version
docker compose version
docker run --rm hello-world
```
`docker --version` y `docker compose version` responden aunque Docker Desktop esté cerrado; **solo `hello-world` prueba que el motor corre**. Si `hello-world` da `failed to connect to the docker API ... dockerDesktopLinuxEngine`, ver "Problemas frecuentes".

## 3. Git y Python
```
winget install --id Git.Git -e
winget install --id Python.Python.3.12 -e
```
Cierra y abre PowerShell. Comprueba `git --version` y `py --version`. En Windows usa `py` (no `python`, que a veces abre la Tienda de Microsoft).

## 4. Memoria para Docker (necesario para Greenbone y Wazuh)
Con el repositorio ya descargado (paso 6) puedes automatizarlo:
```
powershell -ExecutionPolicy Bypass -File scripts\configurar-wsl.ps1
```
Hace una copia de seguridad de tu `.wslconfig`, fija `memory=12GB`, `processors=4` y `swap=2GB` (limitados a lo que tenga la computadora, dejando 4 GB al sistema) y reinicia WSL. Opciones: `-MemoryGB 10 -Processors 4 -SwapGB 2` y `-NoRestart`.

A mano (equivalente): crea/edita `%USERPROFILE%\.wslconfig`:
```
[wsl2]
memory=12GB
processors=4
swap=2GB
```
Luego `wsl --shutdown` y reabre Docker Desktop. (Con 16 GB de RAM total, deja 4 GB al sistema.)

## 5. Ajuste del kernel para Wazuh
```
wsl -d docker-desktop -u root sysctl -w vm.max_map_count=262144
```
Si el comando falla en tu versión, usa: `docker run --rm --privileged --pid=host alpine sysctl -w vm.max_map_count=262144`. Se pierde al reiniciar Docker: repítelo antes de iniciar Wazuh. Verifica: `docker run --rm --privileged alpine sysctl vm.max_map_count` → `262144`.

## 6. Obtener el material
```
cd $HOME
git clone https://github.com/InterCOTN/labs.git
cd labs\COTN3515\lab-environment
```
(El repositorio es privado: inicia sesión con tu cuenta cuando lo pida, o copia la carpeta con un USB.)

## Descargar la imagen del curso
La imagen del laboratorio ya está publicada. Se descarga una sola vez y todos los estudiantes obtienen exactamente la misma:
```
docker compose pull
```
Debe terminar con `Pulled`. No necesitas configurar ninguna variable.

Si dice `denied` o `unauthorized`, la imagen aún no es pública: avisa al profesor.

## Comprobación final
```
docker compose up -d --wait
docker compose ps
docker compose down -v
```
`docker compose ps` debe mostrar todos los servicios en estado `running` o `healthy`.

## Problemas frecuentes
| Síntoma | Qué hacer |
|---|---|
| `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine ... cannot find the file specified` | El motor no está corriendo. Abre **Docker Desktop** desde el menú Inicio y espera a "Engine running"; repite `docker run --rm hello-world`. Si Docker Desktop no existe en la computadora, solo está el cliente: instala Docker Desktop (paso 2, requiere administrador). Si no arranca: `wsl --status`, `docker context ls`, `Get-Service com.docker.service`; causas: virtualización apagada en BIOS, `wsl --update` pendiente, o tu usuario fuera del grupo `docker-users` (lo agrega un administrador). |
| Solo copié `compose.*.yaml` y faltan archivos | Los entornos necesitan la carpeta completa `lab-environment`. Clónala (paso 6) o copia la carpeta entera. |
| "WSL 2 requires an update" | `wsl --update` y reinicia. |
| Docker Desktop se queda en "Starting" | Confirma virtualización en BIOS; reinicia; `wsl --shutdown`. |
| `python` abre la Tienda de Microsoft | Configuración → Aplicaciones → Alias de ejecución de aplicaciones: desactiva el de Python; o usa `py`. |
| Rutas con espacios o OneDrive | Clona en `C:\labs` o `$HOME\labs`, no dentro de OneDrive. |
| `WSL1 is not supported` al iniciar | Aviso inofensivo de Docker Desktop; ignóralo si WSL 2 es la versión predeterminada. |
| Nmap/otras herramientas "no existen" | No se instalan en Windows: se ejecutan **dentro** de los contenedores. |
