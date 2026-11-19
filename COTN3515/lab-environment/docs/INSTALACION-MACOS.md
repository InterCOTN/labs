# Instalación en macOS

## 0. Requisitos
- macOS reciente; 16 GB de RAM, 4 núcleos, 100 GB libres.
- **Apple Silicon (M1–M4):** las imágenes del curso y de Wazuh son multi-arquitectura (amd64 y arm64). Verificado en un Mac con Apple Silicon: M2–M6, M9, M10, Wazuh y Greenbone.
- **Intel:** misma instalación.
- Internet y ~20 GB libres para el primer arranque de Wazuh y Greenbone (descargan imágenes y feeds).


## 1. Docker Desktop
1. Descarga Docker Desktop para Mac (versión Apple Silicon o Intel según tu equipo: menú  → Acerca de este Mac).
2. Abre el `.dmg`, arrastra a Aplicaciones, ábrelo y acepta los permisos.
3. Revisa los términos de licencia para el uso de la institución.
4. Docker Desktop → Settings → Resources: Memory **12 GB**, CPUs **4**, Disk ≥ 100 GB → Apply & Restart.
5. Comprueba en Terminal:
```
docker --version
docker compose version
docker run --rm hello-world
```

## 2. Git y Python
```
xcode-select --install        # incluye git
brew install python           # si usas Homebrew; o instala Python 3 desde python.org
git --version && python3 --version
```
En macOS el comando es `python3`.

## 3. Ajuste para Wazuh
```
docker run --rm --privileged alpine sysctl vm.max_map_count
```
En Docker Desktop para Mac normalmente ya es suficiente. Si no muestra `262144` o más: `docker run --rm --privileged --pid=host alpine sysctl -w vm.max_map_count=262144` (se pierde al reiniciar Docker Desktop).

## 4. Obtener el material
```
cd ~
git clone https://github.com/InterCOTN/labs.git
cd labs/COTN3515/lab-environment
```
(Repositorio privado: inicia sesión cuando lo pida, o copia la carpeta con USB.)

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
| `Cannot connect to the Docker daemon` | Docker Desktop está cerrado: ábrelo, espera a que el ícono indique que el motor corre y repite `docker run --rm hello-world`. |
| Faltan archivos al copiar | Los entornos necesitan la carpeta completa `lab-environment`, no solo los `compose.*.yaml`. |
| `no matching manifest for linux/arm64` | No deberías verlo: las imágenes del curso son multi-arquitectura. Avisa al instructor y pega el nombre de la imagen. |
| El Mac se pone lento | Baja otras apps; usa solo una pila (Greenbone o Wazuh). |
| Puerto 443 o 9392 ocupado | Cierra el programa que lo usa; no cambies los puertos. |
