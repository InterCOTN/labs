# COTN 3515 — Lab Environments (Docker)

Same environment, same answers, on Windows, macOS and Linux.

## Requirements
- Docker Desktop (Windows/Mac) or Docker Engine + Compose v2 (Linux). Check: `docker compose version`.
- ~1 GB free disk, internet only for the first download.

## Start
```
docker compose up -d --wait
```
The first run downloads the lab image (nothing is built on your computer).

## Work inside the lab
Run every tool **inside** the lab containers, never from your own computer, so your output matches everyone else's:
```
docker compose exec client nmap -sT -Pn -n -p 5432 10.77.20.10
docker compose exec web python /app/probe.py web-data
docker compose exec iot python /app/probe.py telemetry
docker compose exec gateway nft list ruleset
```
Containers: `client` (10.77.40.10), `web` (10.77.10.10), `data` (10.77.20.10), `iot` (10.77.30.10), `gateway` (10.77.x.254).

## Check that it is running
```
docker compose ps
```
All services should be `running` or `healthy`.

## Reset / stop
```
docker compose down -v      # remove everything; next `up` starts clean
```
The network is internal: it has no access to the Internet or to your own network. All data is synthetic.


## Environments (one compose file each)
| Module | Compose file |
|---|---|
| 2 and 6 (Nmap scan target 10.79.0.20) | `compose.scan.yaml` |
| 3 (backup/restore) | `compose.m3.yaml` |
| 4 (SCA evidence, no containers) | folder `evidence-m4` |
| 5 (TLS endpoints) | `compose.m5.yaml` |
| 9 (Red Faro) | `compose.yaml` |
| 10 (Faro-Vuln) | `compose.m10.yaml` |

Use `docker compose -f <file> up -d --wait`, then work with the instructions in your Technical Procedure Annex. Run one environment at a time; stop it with `docker compose -f <file> down -v`.

## Instalación
Guías en `docs/`: `INSTALACION-WINDOWS.md`, `INSTALACION-MACOS.md` e `INSTALACION-LINUX.md`.
