#!/usr/bin/env python3
"""Prepara Greenbone Community Edition (presencial). Windows, macOS y Linux.
Uso:  python setup.py up | down | password <nueva> | status
Descarga el compose OFICIAL fijado a un commit del repositorio de documentación de Greenbone
(no se copia al repositorio del curso)."""
import subprocess, sys, urllib.request
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
    dc("pull"); dc("up", "-d")
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
