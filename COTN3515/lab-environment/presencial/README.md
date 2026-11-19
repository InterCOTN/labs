# Camino PRESENCIAL — Greenbone y Wazuh en vivo

Para los cursos presenciales: las computadoras (personales o del laboratorio) cumplen el mínimo; quien no lo cumple usa las del laboratorio. No hay camino opcional.

## Requisitos mínimos de la computadora (por estudiante)
- 16 GB de RAM, 4 núcleos, 100 GB de disco libre, x86_64 (Apple Silicon: ver "Pendientes").
- Docker Desktop (Windows/Mac) o Docker Engine + Compose v2 (Linux); Git; Python 3.
- Windows: WSL 2. En Linux y WSL 2: `sudo sysctl -w vm.max_map_count=262144` (Wazuh).
- Ejecutar **una pila a la vez** (Greenbone o Wazuh), nunca ambas.

## Greenbone (M2, M6)
1. `docker compose -f ../compose.scan.yaml up -d --wait` (objetivo 10.79.0.20).
2. `python greenbone/setup.py up` (primera vez: descarga y sincronización del feed, larga).
3. `python greenbone/setup.py password <nueva>`; abrir http://127.0.0.1:9392.
4. Apagar: `python greenbone/setup.py down`.

## Wazuh (M4, M7)
1. `python wazuh/setup.py up` → dashboard en https://localhost.
2. Apagar: `python wazuh/setup.py down`.

## Wazuh — eventos del M7
`python wazuh/setup.py emit-m7` carga los seis eventos del escenario (E1–E6) en el endpoint; las reglas personalizadas están en `wazuh/local_rules.xml`.

## Anexos técnicos presenciales
Cada anexo está en `courses/COTN3515/modules/module-0N/labs/`: M2, M4, M6 y M7 tienen versión `InPerson` (Greenbone y Wazuh en vivo) y, para M2, M4 y M6, versión `Online` (evidencia congelada). M3, M5, M9 y M10 sirven igual a ambos caminos.

## Reproducibilidad
Nmap, OpenSSL, respaldo, Red Faro y Faro-Vuln dan las mismas respuestas a todos. Greenbone y Wazuh **no**: el feed y las alertas cambian con el tiempo. Para igualar al grupo, el laboratorio distribuye las imágenes y los datos del feed ya descargados (`docker save`/`docker load` o un registro local) y fija su fecha.

## Estado: SIN PROBAR
Estos archivos se escribieron sin poder descargar las imágenes (el entorno de desarrollo no alcanza esos registros). Antes de usarlos con estudiantes hay que probarlos en una computadora del laboratorio: ver `PRUEBA-INICIAL.md`.
