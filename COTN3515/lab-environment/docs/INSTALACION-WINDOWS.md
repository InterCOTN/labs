# Instalación en Windows 10/11 (64 bits)

Sirve para una computadora de estudiante o del laboratorio. Tiempo: 30–60 min más reinicios.

## Instalación desatendida (computadoras del laboratorio)
Un solo comando, en PowerShell, deja todo instalado y probado (WSL 2, Git, Python, Docker Desktop, memoria de WSL, laboratorios M3/M5/M9/M10/escaneo, Wazuh y Greenbone con su feed ya sincronizado). No hace falta token: el repositorio es público.
```
iwr -UseBasicParsing https://raw.githubusercontent.com/InterCOTN/labs/main/COTN3515/lab-environment/scripts/instalar-laboratorio-windows.ps1 -OutFile $env:TEMP\instalar.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\instalar.ps1
```
- Pide permisos de administrador una vez y abre una ventana que **no se cierra sola**; si hay que reiniciar, lo hace y continúa al iniciar sesión.
- Es repetible: si falla, vuelve a pegar el comando y sigue en el paso que falló.
- Progreso: `Get-Content C:\ProgramData\COTN3515\resumen.txt`. Registro completo en la misma carpeta. Termina con `INSTALACION COMPLETA`.
- Con un disco duro mecánico puede tardar varias horas (sobre todo Greenbone). Dejar la computadora encendida y conectada.
- Estado: probado de cero hasta `INSTALACION COMPLETA` en una PC con SSD NVMe (31 GB de RAM, 16 CPU): Greenbone tardó ~25 min en descargar imágenes y ~33 min en sincronizar el feed (58 min en total); Wazuh y los laboratorios, menos de 1 min cada uno. Pendiente: repetir la prueba en una computadora del laboratorio con disco mecánico.
- Docker Desktop tiene condiciones de licencia para uso institucional: confirmarlas con TI.

### Caché de imágenes en el NAS (opcional, recomendado)
Evita depender del registro de Greenbone (que a veces devuelve 502 y no deja instalar) y acelera la instalación; además fija la misma versión de imágenes y del feed para todo el grupo.

**Una vez (en tu computadora, con el registro funcionando):** hace falta Docker, Git y Python 3; no hace falta levantar Greenbone ni Wazuh (el script obtiene solo sus archivos). Siempre guarda imágenes `linux/amd64`, aunque lo corras desde un Mac Apple Silicon.
- Windows: `py scripts\cache-imagenes.py export \\NAS\cotn3515\imagenes`
- macOS (conecta antes el recurso con una cuenta con escritura: Finder → Ir → Conectarse al servidor → `smb://NAS/cotn3515`): `python3 scripts/cache-imagenes.py export /Volumes/cotn3515/imagenes`

Guarda todas las imágenes (laboratorios, Wazuh, Greenbone) como `.tar` con un `imagenes.json` que anota la fecha. Repítelo para refrescar versiones (p. ej. al empezar el semestre).

**Carpeta compartida en el NAS:** recurso SMB `cotn3515` (subcarpeta `imagenes`) con una cuenta de **solo lectura** para el laboratorio (`cotn`) y otra con escritura para quien exporta (`ha`). Windows bloquea por defecto el acceso de invitado, por eso se usa una cuenta.

**En cada computadora del laboratorio**, en PowerShell **como administrador** (la conexión debe hacerse en la misma ventana elevada que lanza el instalador):
```
net use \\NAS\cotn3515 /user:cotn * /persistent:yes
iwr -UseBasicParsing https://raw.githubusercontent.com/InterCOTN/labs/main/COTN3515/lab-environment/scripts/instalar-laboratorio-windows.ps1 -OutFile $env:TEMP\instalar.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\instalar.ps1 -Cache \\NAS\cotn3515\imagenes
```
(`*` pide la contraseña; no queda escrita en el comando ni en el registro del instalador.) El instalador carga desde la caché las imágenes que falten y, si la caché no está disponible o alguna imagen no carga, usa el registro como antes. `setup.py` de Greenbone solo descarga las imágenes que no están; para forzar la versión más reciente: variable `GREENBONE_ACTUALIZAR=1`.

Estado: sin probar. Al validarla, comprobar en `resumen.txt`/registro que las imágenes con versión fijada (`redfaro-lab:1.0.1@sha256:...`) quedan reconocidas tras `docker load`; si no, se bajarán del registro y el script lo avisa.

Las secciones siguientes son el camino manual (computadoras de estudiantes).

## 0. Requisitos
- Windows 10 (22H2) o 11, 64 bits; virtualización activada en BIOS/UEFI (Administrador de tareas → Rendimiento → CPU → "Virtualización: Habilitado").
- 16 GB de RAM, 4 núcleos, 100 GB libres (mínimo del camino presencial).
- Cuenta con permisos de administrador (solo para instalar).
- Disco **SSD** recomendado. Un disco duro mecánico (CMR o SMR) funciona, pero el primer arranque de Wazuh y Greenbone es lento. Medido en un WD Blue CMR de 1 TB: el agente de Wazuh quedó *Active* en unos 4 min y el primer arranque de Greenbone tardó unos 46 min solo en copiar sus datos (más la descarga y la sincronización del feed); en un disco SMR de Seagate el agente tardó unos 15 min. Pruebas cortas como `dd` o CrystalDiskMark (8 GiB) no distinguen SMR de CMR; la prueba real es arrancar Wazuh y ver cuánto tarda el agente en quedar *Active*.
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
