#!/usr/bin/env python3
"""Prepara Greenbone Community Edition (presencial). Windows, macOS y Linux.
Uso:  python setup.py up | down | password <nueva> | status
Descarga el compose OFICIAL fijado a un commit del repositorio de documentación de Greenbone
(no se copia al repositorio del curso)."""
import os, subprocess, sys, time, urllib.request
from pathlib import Path
HERE = Path(__file__).resolve().parent
COMMIT = "53ab3ba090d9ffbc066839eee09c96b9216b4ec8"   # greenbone/docs, 2026-10-28
URL = f"https://raw.githubusercontent.com/greenbone/docs/{COMMIT}/src/_static/compose.yaml"   # (src/22.4/container/compose.yaml es un enlace simbólico: GitHub lo sirve como texto)
BASE = HERE / "compose.greenbone.yaml"
def dc(*a):
    return subprocess.run(["docker", "compose", "-p", "greenbone", "-f", str(BASE), "-f", str(HERE / "compose.override.yaml"), *a])
def need_scan_net():
    r = subprocess.run(["docker", "network", "inspect", "redfaro-scan_scan"], capture_output=True)
    if r.returncode:
        sys.exit("Primero enciende el objetivo: docker compose -f ../../compose.scan.yaml up -d --wait")
cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
if cmd == "up":
    need_scan_net()
    if not BASE.exists() or b"services:" not in BASE.read_bytes():
        data = urllib.request.urlopen(URL, timeout=60).read()
        if b"services:" not in data:
            sys.exit(f"La descarga no parece un compose válido ({URL}). Contenido recibido: {data[:120]!r}")
        BASE.write_bytes(data)
    # El registro de Greenbone responde a veces 502/timeout y 'compose pull' aborta TODO al primer error (son ~19
    # imagenes en paralelo). Se baja imagen por imagen y se reintentan solo las que fallan, hasta 120 min.
    r = subprocess.run(["docker", "compose", "-p", "greenbone", "-f", str(BASE), "-f", str(HERE / "compose.override.yaml"),
                        "config", "--images"], capture_output=True, text=True)
    pendientes = sorted(set(l.strip() for l in r.stdout.splitlines() if l.strip()))
    if not os.environ.get("GREENBONE_ACTUALIZAR"):
        # Solo se descargan las que faltan (p. ej. si se cargaron desde la cache del laboratorio, sin tocar el registro).
        # Para traer la version mas reciente de todas: GREENBONE_ACTUALIZAR=1
        pendientes = [i for i in pendientes if subprocess.run(["docker", "image", "inspect", i], capture_output=True).returncode != 0]
    if r.returncode or not pendientes:
        sys.exit("No se pudo obtener la lista de imágenes de Greenbone: " + r.stderr.strip())
    limite = time.time() + 120 * 60
    ronda = 0
    while pendientes:
        ronda += 1
        fallidas = []
        for img in pendientes:
            print(f"\n== {img}", flush=True)
            if subprocess.run(["docker", "pull", img]).returncode != 0:
                fallidas.append(img)
        pendientes = fallidas
        if not pendientes:
            break
        if time.time() > limite:
            sys.exit("No se pudieron descargar en 120 min: " + ", ".join(pendientes) + " (registry.community.greenbone.net). Revisa tu red o inténtalo más tarde.")
        print(f"\nFaltan {len(pendientes)} imágenes (ronda {ronda}; suele ser un error temporal del registro, p. ej. 502). Reintento en 30 s...", flush=True)
        time.sleep(30)
    # En discos lentos los contenedores de datos tardan en quedar 'healthy' (en un disco mecanico con volumenes
    # nuevos, hasta ~45 min); si compose se rinde antes, deja el scanner (ospd-openvas, openvasd) en estado
    # 'Created' sin arrancar. Se reintenta cada 60 s, hasta 120 min, hasta que arranque todo.
    limite = time.time() + 120 * 60
    intento = 0
    while True:
        intento += 1
        if dc("up", "-d").returncode == 0:
            break
        if time.time() > limite:
            sys.exit("Greenbone no arrancó en 120 min. Revisa: docker ps -a")
        print(f"\n'up' terminó con error (intento {intento}): un contenedor de datos aún no está 'healthy'. Reintento en 60 s...")
        time.sleep(60)
    print("\nPrimera vez: la sincronización del feed puede tardar (40 min en un SSD rápido; horas en un disco lento).")
    print("Cuando Administration -> Feed Status muestre todo en 'Current', abre https://127.0.0.1 (acepta el certificado autofirmado).")
    print("Usuario: admin. Cambia la contraseña desde la carpeta lab-environment:")
    print("  py presencial\\greenbone\\setup.py password '<nueva>'      (Windows)")
    print("  python3 presencial/greenbone/setup.py password '<nueva>'   (macOS/Linux)")
elif cmd == "password" and len(sys.argv) == 3:
    dc("exec", "-u", "gvmd", "gvmd", "gvmd", "--user=admin", f"--new-password={sys.argv[2]}")
elif cmd == "down":
    dc("down")
else:
    dc("ps")
