#!/usr/bin/env python3
"""Cache de imagenes Docker del laboratorio (carpeta local o compartida, p. ej. un NAS).
Windows, macOS y Linux.

  python cache-imagenes.py export <carpeta>   Descarga las imagenes y las guarda en <carpeta> (.tar + imagenes.json).
                                              Hacerlo UNA vez, con el registro funcionando, tras instalar el laboratorio.
  python cache-imagenes.py import <carpeta>   Carga en Docker las imagenes de <carpeta> que falten. Lo usa el instalador.

Siempre se descargan imagenes linux/amd64 (las del laboratorio), tambien si se exporta desde un Mac Apple Silicon.
Lista de imagenes: las de los compose del laboratorio, Greenbone y Wazuh (se leen con 'docker compose config --images').
Tras 'import' se verifica cada imagen; las que no queden disponibles se bajaran del registro como siempre."""
import json, os, re, subprocess, sys, time
from pathlib import Path

LAB = Path(__file__).resolve().parent.parent
GB = LAB / "presencial" / "greenbone"
WZ = LAB / "presencial" / "wazuh"
SN = WZ / "wazuh-docker" / "single-node"
MANIFEST = "imagenes.json"
PLATAFORMA = "linux/amd64"   # las computadoras del laboratorio son x86_64, aunque se exporte desde un Mac Apple Silicon


def run(*a, cwd=None, capture=False):
    return subprocess.run(list(a), cwd=cwd, capture_output=capture, text=True, encoding="utf-8", errors="replace")


def config_images(args, cwd, env=None):
    r = subprocess.run(["docker", "compose", *args, "config", "--images"], cwd=cwd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env={**os.environ, **(env or {})})
    if r.returncode:
        print(f"  (aviso) no se pudo leer la lista de {cwd.name}: {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else r.returncode}")
        return []
    return [l.strip() for l in r.stdout.splitlines() if l.strip()]


def preparar():
    """Obtiene (sin levantar nada) los archivos compose de Greenbone y Wazuh si faltan."""
    if not (GB / "compose.greenbone.yaml").exists():
        run(sys.executable, str(GB / "setup.py"), "fetch")
    if not SN.exists():
        run(sys.executable, str(WZ / "setup.py"), "fetch")


def lista_imagenes():
    preparar()
    imgs = set()
    for f in ("compose.yaml", "compose.m3.yaml", "compose.m5.yaml", "compose.m10.yaml", "compose.scan.yaml"):
        imgs.update(config_images(["-f", f], LAB))
    gb = GB / "compose.greenbone.yaml"
    if gb.exists():
        imgs.update(config_images(["-p", "greenbone", "-f", str(gb), "-f", str(GB / "compose.override.yaml")], LAB))
    else:
        print("  (aviso) falta presencial/greenbone/compose.greenbone.yaml: ejecute antes 'setup.py up' de Greenbone")
    if SN.exists():
        env = {"WAZUH_LAB_DIR": WZ.as_posix()}
        imgs.update(config_images(["-p", "wazuh", "-f", "docker-compose.yml", "-f", str(WZ / "compose.override.yaml")], SN, env))
        imgs.update(config_images(["-f", "generate-indexer-certs.yml"], SN, env))
    else:
        print("  (aviso) falta presencial/wazuh/wazuh-docker: ejecute antes 'setup.py up' de Wazuh")
    return sorted(imgs)


def image_id(ref):
    r = run("docker", "image", "inspect", ref, "--format", "{{.Id}}", capture=True)
    return r.stdout.strip() if r.returncode == 0 else None


def export(dest):
    dest.mkdir(parents=True, exist_ok=True)
    imgs = lista_imagenes()
    if not imgs:
        sys.exit("No se encontro ninguna imagen que guardar.")
    print(f"{len(imgs)} imagenes. Destino: {dest}")
    entradas, fallidas = [], []
    for ref in imgs:
        print(f"\n== {ref}", flush=True)
        for intento in range(1, 6):
            if run("docker", "pull", "--platform", PLATAFORMA, ref).returncode == 0:
                break
            if intento < 5:
                print(f"  fallo la descarga (intento {intento}); reintento en 30 s...", flush=True)
                time.sleep(30)
        else:
            fallidas.append(ref)
            continue
        tar = re.sub(r"[^A-Za-z0-9._-]+", "_", ref)[:150] + ".tar"
        # --platform en 'save' existe solo en Docker recientes; si no se reconoce, se guarda sin el.
        if run("docker", "save", "--platform", PLATAFORMA, "-o", str(dest / tar), ref).returncode != 0 \
                and run("docker", "save", "-o", str(dest / tar), ref).returncode != 0:
            fallidas.append(ref)
            continue
        entradas.append({"ref": ref, "id": image_id(ref), "tar": tar, "bytes": (dest / tar).stat().st_size})
    (dest / MANIFEST).write_text(json.dumps({"fecha": time.strftime("%Y-%m-%d %H:%M:%S"), "imagenes": entradas}, indent=2), encoding="utf-8")
    gb = sum(e["bytes"] for e in entradas) / 1e9
    print(f"\nGuardadas {len(entradas)} imagenes ({gb:.1f} GB) en {dest}")
    if fallidas:
        sys.exit("NO se pudieron guardar: " + ", ".join(fallidas))


def importar(src):
    mf = src / MANIFEST
    if not mf.exists():
        print(f"No hay {MANIFEST} en {src}: se usara el registro.")
        return 0
    datos = json.loads(mf.read_text(encoding="utf-8"))
    print(f"Cache del {datos.get('fecha')}: {len(datos['imagenes'])} imagenes.")
    for e in datos["imagenes"]:
        if e["id"] and image_id(e["ref"]) == e["id"]:
            print(f"  ya esta: {e['ref']}")
            continue
        print(f"  cargando: {e['ref']} ({e['bytes'] / 1e6:.0f} MB)", flush=True)
        if run("docker", "load", "-i", str(src / e["tar"])).returncode != 0:
            print("    (aviso) no se pudo cargar; se bajara del registro")
    faltan = [e["ref"] for e in datos["imagenes"] if image_id(e["ref"]) is None]
    if faltan:
        print("Sin cargar (se bajaran del registro): " + ", ".join(faltan))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("export", "import"):
        sys.exit(__doc__)
    carpeta = Path(sys.argv[2])
    export(carpeta) if sys.argv[1] == "export" else importar(carpeta)
