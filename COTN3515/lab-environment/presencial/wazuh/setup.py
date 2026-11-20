#!/usr/bin/env python3
"""Prepara Wazuh (presencial): manager + indexador + dashboard + endpoint Ubuntu con agente.
Windows, macOS y Linux. Uso:  python setup.py up | down | reset | status | emit-m7
Requiere: git, Docker; en Linux/WSL2: vm.max_map_count >= 262144 (ver README)."""
import os, re, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
TAG = "v4.14.6"                       # wazuh/wazuh-docker (el de la documentación oficial)
REPO = HERE / "wazuh-docker"
SN = REPO / "single-node"
os.environ["WAZUH_LAB_DIR"] = HERE.as_posix()   # el override monta archivos de esta carpeta
def run(*a, cwd=None):
    r = subprocess.run(list(a), cwd=cwd); 
    if r.returncode: sys.exit(f"falló: {' '.join(a)}")
def dc(*a):
    return subprocess.run(["docker", "compose", "-p", "wazuh", "-f", "docker-compose.yml", "-f", str(HERE / "compose.override.yaml"), *a], cwd=SN)
def certs_ready():
    # La herramienta de certificados deja la carpeta con permisos de otro usuario: .exists() lanza
    # PermissionError en la 2.ª ejecución; eso significa que los certificados ya existen.
    try:
        return (SN / "config" / "wazuh_indexer_ssl_certs" / "root-ca.pem").exists()
    except PermissionError:
        return True
def apply_lab_config():
    """Desactiva la detección de vulnerabilidades del manager. Ningún laboratorio (M4: SCA, M7: reglas
    propias) la usa y, si está activa, el manager baja varios GB de feeds en cada arranque, con muchas
    escrituras y CPU; en un disco lento eso retrasa todo el arranque. Edita solo la copia clonada
    (tag fijado), es idempotente y falla si la sección cambia, para no dejarla activa en silencio."""
    conf = SN / "config" / "wazuh_cluster" / "wazuh_manager.conf"
    text = conf.read_bytes().decode("utf-8")
    new, n = re.subn(r"(<vulnerability-detection>\s*<enabled>)yes(</enabled>)", r"\1no\2", text, count=1)
    if n:
        conf.write_bytes(new.encode("utf-8"))
    elif not re.search(r"<vulnerability-detection>\s*<enabled>no</enabled>", text):
        sys.exit(f"no encontré <vulnerability-detection><enabled> en {conf}; revisa el tag de wazuh-docker")
cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
def fetch_repo():
    if not REPO.exists():
        run("git", "clone", "--depth", "1", "--branch", TAG, "https://github.com/wazuh/wazuh-docker.git", str(REPO))
if cmd == "fetch":            # solo clona wazuh-docker (lo usa scripts/cache-imagenes.py)
    fetch_repo()
elif cmd == "up":
    fetch_repo()
    apply_lab_config()
    if not certs_ready():
        run("docker", "compose", "-f", "generate-indexer-certs.yml", "run", "--rm", "generator", cwd=SN)
    dc("up", "-d")
    print("\nEl primer arranque tarda ~1 minuto. Dashboard: https://localhost  (usuario: admin, contraseña: SecretPassword; certificado autofirmado)")
elif cmd == "emit-m7":
    dc("exec", "-T", "endpoint", "/usr/local/bin/m7-emit.sh")
elif cmd == "down":
    dc("down")
elif cmd == "reset":          # down + borra volúmenes: Wazuh vuelve a empezar de cero
    dc("down", "-v")
else:
    dc("ps")
