# Probar los laboratorios en una VM real (Windows y macOS)

`probar_laboratorios_vm.py` crea una VM Ubuntu Server 24.04 con Multipass y prueba, de principio a fin, el servidor de práctica de los Módulos 4 a 10 (`lab_server_setup.sh`): lo ejecuta dos veces, comprueba servicios, cuentas, permisos y puertos dentro de la VM y desde el equipo anfitrión, y escribe un informe `informe-vm/informe-vm-AAAAMMDD-HHMM.md` (y `.json`). Al terminar borra la VM.

## Requisitos
- Python 3.9 o superior.
- **Windows 10/11:** terminal de administrador la primera vez; Multipass usa Hyper-V (Pro/Enterprise) o VirtualBox (Home). `winget` instala Multipass.
- **macOS (Intel o chip Apple):** Homebrew. Multipass usa el hipervisor del sistema.
- Unos 15 GB libres de disco, 2 GB de RAM para la VM y conexión a internet (descarga Ubuntu 24.04 y paquetes).

## Ejecutar
```bash
python3 tools/probar_laboratorios_vm.py --install
```
En Windows, abra **PowerShell como administrador** en la carpeta del repositorio y ejecute el asistente todo-en-uno. No hay pasos manuales: instala winget si falta (con el módulo oficial de Microsoft), Python, VirtualBox (Windows Home, o Pro sin Hyper-V habilitado, para no tener que reiniciar) y Multipass, actualiza el PATH de la sesión y lanza las pruebas:
```powershell
powershell -ExecutionPolicy Bypass -File tools\probar_laboratorios_vm.ps1
```
Opciones: `-Modules "4,6,10"`, `-Keep`, `-Out carpeta`, `-Driver hyperv|virtualbox`.

**Si Multipass no funciona** (por ejemplo, la red del equipo ocupa todo `10.x.x.x` y `multipassd` se detiene con «256 is greater than the largest subnet block index 255»), en Windows el script usa **WSL2 con Ubuntu 24.04** automáticamente (`--backend wsl` para forzarlo). WSL2 es una VM ligera con su propia red; Windows reenvía a localhost incluso los puertos que en Linux escuchan solo en 127.0.0.1, así que con WSL2 no se comprueba que un puerto «solo local» esté cerrado desde el anfitrión. Requiere `wsl --install --no-distribution` (el asistente lo ejecuta) y descargar la imagen de Ubuntu 24.04 para WSL (`cloud-images.ubuntu.com/wsl`).

**Windows, notas:** la virtualización debe estar activada en el BIOS/UEFI; Hyper-V necesita reiniciar al habilitarlo; con VirtualBox las instantáneas pueden no estar disponibles y el script recrea la VM en cada módulo (más lento). Los comandos y archivos viajan en base64 y se normalizan los saltos de línea, para que un checkout de Git con CRLF no rompa `lab_server_setup.sh` (el repositorio también fuerza LF en `*.sh`).
Opciones: `--modules 4,6,10` (solo esos), `--keep` (no borrar la VM), `--out CARPETA`, `--dry-run` (solo muestra el plan).

## Qué cubre y qué no
- Cubre: la preparación del servidor de cada módulo, su idempotencia y la red real VM ↔ Windows/macOS. El laboratorio A1 usa el servidor del Módulo 10. Los Módulos 1 a 3 no tienen servidor de práctica.
- No cubre: seguir los pasos de cada guía de laboratorio (eso requiere una persona) ni probar clientes Windows/macOS más allá del acceso a los puertos.
- `--local` es solo para validar el propio script en Linux como root (no es una VM; sin systemd los servicios no arrancan y algunas pruebas fallan a propósito).
- Probado: el script y su plan (`--dry-run`) y el modo `--local`. Ejecutado con Multipass 1.17.1 en macOS (chip Apple): los Módulos 4 a 10 aprobaron las 85 pruebas (18 de noviembre de 2026). Ejecutado también en Windows 10 Pro con WSL2 (Ubuntu 24.04): 75 de 75 pruebas aprobadas (18 de noviembre de 2026). Con Multipass en Windows aún no se ha podido probar (en esa PC no arranca por el conflicto de red descrito abajo).
