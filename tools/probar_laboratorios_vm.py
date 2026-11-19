#!/usr/bin/env python3
"""Prueba de principio a fin los servidores de práctica de los laboratorios de COTN 2150 en una máquina virtual REAL.

Funciona en Windows y en macOS (Intel o chip Apple) con Python 3.9 o superior y solo la biblioteca estándar.
Usa Multipass (Canonical): crea una VM Ubuntu Server 24.04 con el mismo sistema que usan los laboratorios, y en ella,
para cada módulo (4 a 10), copia y ejecuta su `lab_server_setup.sh`, comprueba el resultado dentro de la VM y desde el
equipo anfitrión (red real VM <-> Windows/macOS), vuelve a ejecutarlo (idempotencia) y restaura la VM limpia.
Al final escribe un informe (Markdown y JSON) con aprobado/fallido por prueba, y borra la VM.

Uso (desde cualquier carpeta; el script encuentra el repositorio):
    Windows:  py -3 tools\\probar_laboratorios_vm.py --install
    macOS:    python3 tools/probar_laboratorios_vm.py --install
Opciones:
    --install          instala Multipass si falta (winget en Windows, Homebrew en macOS)
    --modules 4,6,10   solo esos módulos (por defecto 4 a 10; el laboratorio A1 usa el servidor del Módulo 10)
    --driver MOTOR     Windows: hyperv (Pro/Enterprise) o virtualbox (Home); por defecto, el que ya use Multipass
    --keep             no borra la VM al terminar
    --out CARPETA      dónde escribir el informe (por defecto ./informe-vm)
    --dry-run          muestra el plan sin crear nada
    --local            SOLO validación del propio script: ejecuta en este Linux (como root) en vez de una VM; no es una VM real

Los Módulos 1 a 3 no tienen servidor de práctica (usan el equipo del estudiante): no se prueban aquí.
No modifica nada del repositorio. Las contraseñas de las guías son valores de entrenamiento de la VM de práctica.
"""
import argparse
import base64
import datetime
import json
import os
import pathlib
import platform
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

REPO = pathlib.Path(__file__).resolve().parent.parent
MODS = REPO / "courses" / "COTN2150" / "modules"


def setup_dir(m):
    """Carpeta con lab_server_setup.sh del módulo m. Admite el repositorio completo (courses/COTN2150/modules/module-NN/labs/source)
    y el repositorio público de laboratorios (COTN2150/module-NN)."""
    for cand in (MODS / f"module-{m:02d}" / "labs" / "source", REPO / "COTN2150" / f"module-{m:02d}"):
        if (cand / "lab_server_setup.sh").exists():
            return cand
    return None
VM = "cotn2150-lab"
ALL_MODULES = [4, 5, 6, 7, 8, 9, 10]

# Comprobaciones por módulo. Cada una: (nombre, comando bash dentro de la VM). Debe terminar con código 0.
COMMON = [
    ("existe la cuenta lab", "id lab"),
    ("SSH escucha en el puerto 22", "ss -ltn | grep -q ':22 '"),
]
CHECKS = {
    4: [
        ("nginx sirve el portal (HTTP 200 con el texto del portal)", "curl -s -m 5 http://127.0.0.1/ | grep -q 'Portal'"),
        ("/var/www/portal es root:portal con modo 2775", "[ \"$(stat -c '%U:%G:%a' /var/www/portal)\" = 'root:portal:2775' ]"),
        ("lab está en el grupo portal", "id -nG lab | tr ' ' '\\n' | grep -qx portal"),
        ("lab NO tiene sudo (cuenta sin administrador)", "! id -nG lab | tr ' ' '\\n' | grep -qx sudo"),
        ("el sitio por defecto de nginx fue retirado", "[ ! -e /etc/nginx/sites-enabled/default ]"),
    ],
    5: [
        ("lab tiene sudo solo dentro de la VM", "id -nG lab | tr ' ' '\\n' | grep -qx sudo"),
        ("todavía no escucha web (80) ni base de datos (3306)", "! ss -ltn | grep -qE ':(80|3306) '"),
    ],
    6: [
        ("Apache responde en el puerto 80", "curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1/ | grep -qE '^(200|403)$'"),
        ("PHP instalado", "php -v | head -n 1 | grep -q PHP"),
        ("MySQL escucha solo en 127.0.0.1", "ss -ltn | grep -q '127.0.0.1:3306 ' && ! ss -ltn | grep -qE '(0.0.0.0|\\*|\\[::\\]):3306 '"),
        ("WordPress NO está instalado (lo instala el laboratorio)", "[ ! -d /var/www/html/wp-admin ]"),
    ],
    7: [
        ("todavía no escucha FTP (21), correo (25) ni IMAP (143)", "! ss -ltn | grep -qE ':(21|25|143) '"),
    ],
    8: [
        ("Apache responde en el puerto 80", "curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1/ | grep -qE '^(200|403)$'"),
        ("Postfix escucha solo en 127.0.0.1:25", "ss -ltn | grep -q '127.0.0.1:25 ' && ! ss -ltn | grep -qE '(0.0.0.0|\\*|\\[::\\]):25 '"),
        ("existen las cuentas maestra1 y director1 sin shell", "id maestra1 && id director1 && getent passwd maestra1 | grep -q nologin"),
        ("el registro de Postfix está configurado", "postconf -h maillog_file | grep -q /var/log/postfix.log"),
    ],
    9: [
        ("Apache responde en el puerto 80", "curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1/ | grep -qE '^(200|403)$'"),
        ("Postfix escucha solo en 127.0.0.1:25", "ss -ltn | grep -q '127.0.0.1:25 ' && ! ss -ltn | grep -qE '(0.0.0.0|\\*|\\[::\\]):25 '"),
        ("existen las cuentas maestra1 y director1 sin shell", "id maestra1 && id director1 && getent passwd maestra1 | grep -q nologin"),
    ],
    10: [
        ("Apache responde en el puerto 80", "curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1/ | grep -qE '^(200|403)$'"),
        ("Postfix escucha solo en 127.0.0.1:25", "ss -ltn | grep -q '127.0.0.1:25 ' && ! ss -ltn | grep -qE '(0.0.0.0|\\*|\\[::\\]):25 '"),
        ("existen las cuentas maestra1 y director1 sin shell", "id maestra1 && id director1 && getent passwd maestra1 | grep -q nologin"),
    ],
}
# Puertos que deben verse DESDE EL ANFITRIÓN (Windows/macOS) hacia la VM, y los que no.
HOST_OPEN = {4: [22, 80], 5: [22], 6: [22, 80], 7: [22], 8: [22, 80], 9: [22, 80], 10: [22, 80]}
HOST_CLOSED = {4: [3306], 5: [80, 3306], 6: [3306], 7: [21, 25, 143], 8: [25], 9: [25], 10: [25]}
EXTRA_FILES = {8: ["comprobar.sh"]}  # se copian y se ejecutan para ver que, en una VM recién preparada, no marca ACT (código 2)


def run(cmd, timeout=900, check=False, input_text=None):
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout, input=input_text)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(map(str, cmd))}\n{p.stdout}\n{p.stderr}")
    return p


def find_multipass():
    """Busca multipass en el PATH y, en Windows, en la ruta de instalación (el PATH no se actualiza hasta abrir otra terminal)."""
    exe = shutil.which("multipass")
    if exe:
        return exe
    for base in (os.environ.get("ProgramFiles"), os.environ.get("ProgramW6432"), r"C:\Program Files"):
        if base:
            cand = pathlib.Path(base) / "Multipass" / "bin" / "multipass.exe"
            if cand.exists():
                return str(cand)
    mac = pathlib.Path("/usr/local/bin/multipass")
    return str(mac) if mac.exists() else None


def is_admin():
    if platform.system() != "Windows":
        return os.geteuid() == 0
    try:
        import ctypes
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def b64(text):
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


class Base:
    """Comandos y archivos viajan en base64: sin problemas de comillas entre PowerShell/cmd/zsh y sin saltos de línea de Windows."""

    def run_script(self, command, timeout):
        raise NotImplementedError

    def sh(self, command, timeout=900):
        return self.run_script(f"echo {b64(command)} | base64 -d | bash", timeout)

    def put(self, local, remote):
        data = pathlib.Path(local).read_bytes().replace(b"\r\n", b"\n")  # un checkout de Git en Windows puede traer CRLF y bash fallaría
        r = self.run_script(f"echo {base64.b64encode(data).decode('ascii')} | base64 -d > {remote}", 120)
        if r.returncode != 0:
            raise RuntimeError(f"no se pudo copiar {local} a la VM: {r.stderr}")


class Multipass(Base):
    name = "Multipass"

    def __init__(self):
        self.exe = find_multipass()

    def available(self):
        return bool(self.exe)

    def version(self):
        return run([self.exe, "version"]).stdout.strip().replace("\n", " · ")

    def create(self):
        run([self.exe, "delete", "--purge", VM])
        run([self.exe, "launch", "24.04", "--name", VM, "--cpus", "2", "--memory", "2G", "--disk", "12G", "--timeout", "900"], timeout=1500, check=True)
        self.snap = False
        r = run([self.exe, "stop", VM])
        if r.returncode == 0:
            r = run([self.exe, "snapshot", VM, "--name", "limpia"])
            self.snap = r.returncode == 0
            run([self.exe, "start", VM], check=True)

    def reset(self):
        if self.snap:
            run([self.exe, "stop", VM])
            run([self.exe, "restore", "--destructive", f"{VM}.limpia"], check=True)
            run([self.exe, "start", VM], check=True)
        else:
            self.create()

    def run_script(self, command, timeout=900):
        return run([self.exe, "exec", VM, "--", "bash", "-c", command], timeout=timeout)

    def ip(self):
        info = json.loads(run([self.exe, "info", VM, "--format", "json"], check=True).stdout)
        return info["info"][VM]["ipv4"][0]

    def destroy(self):
        run([self.exe, "delete", "--purge", VM])


class Local(Base):
    """Solo para validar este script: ejecuta como root en este Linux. NO es una máquina virtual real."""
    name = "Local (no es una VM)"
    snap = False
    loopback = True

    def available(self):
        return sys.platform.startswith("linux") and os.geteuid() == 0

    def version(self):
        return "local"

    def create(self):
        pass

    def reset(self):
        pass

    def run_script(self, command, timeout=900):
        return run(["bash", "-c", command], timeout=timeout)

    def ip(self):
        return "127.0.0.1"

    def destroy(self):
        pass


WSL_NAME = "cotn2150-lab"
WSL_ROOTFS_URLS = [
    "https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz",
    "https://releases.ubuntu.com/noble/ubuntu-24.04-wsl-amd64.wsl",
]


def wsl_mgmt(args, timeout=900):
    """wsl.exe escribe sus mensajes de administración en UTF-16; los comandos dentro de Linux salen en UTF-8."""
    p = subprocess.run(["wsl"] + args, capture_output=True, timeout=timeout)
    raw = p.stdout + p.stderr
    text = raw.decode("utf-16-le", errors="replace") if b"\x00" in raw else raw.decode("utf-8", errors="replace")
    return p.returncode, text.replace("\x00", "").strip()


class Wsl(Base):
    """WSL2 con Ubuntu 24.04: usa su propia red NAT, así que funciona aunque la red del anfitrión ocupe todo 10.x.x.x (donde Multipass falla).
    Es una VM ligera de Windows, no una VM de VirtualBox/Hyper-V como la de los estudiantes. Ojo: Windows reenvía a localhost también los puertos
    que en Linux escuchan solo en 127.0.0.1, por eso aquí no se comprueba que un puerto 'solo local' esté cerrado desde el anfitrión."""
    name = "WSL2 (Ubuntu 24.04)"
    snap = False
    loopback = True

    def __init__(self):
        self.exe = shutil.which("wsl")
        self.dir = pathlib.Path(os.environ.get("LOCALAPPDATA", str(pathlib.Path.home()))) / "cotn2150-wsl"

    def available(self):
        return bool(self.exe) and wsl_mgmt(["--status"])[0] == 0

    def version(self):
        return wsl_mgmt(["--version"])[1].splitlines()[0] if self.exe else "?"

    def _rootfs(self):
        tar = self.dir / "ubuntu-24.04-rootfs.tar.gz"
        if tar.exists() and tar.stat().st_size > 50_000_000:
            return tar
        self.dir.mkdir(parents=True, exist_ok=True)
        last = ""
        for url in WSL_ROOTFS_URLS:
            try:
                print(f"Descargando Ubuntu 24.04 para WSL ({url})...")
                urllib.request.urlretrieve(url, str(tar))
                if tar.stat().st_size > 50_000_000:
                    return tar
            except Exception as e:
                last = str(e)
        raise RuntimeError(f"No se pudo descargar la imagen de Ubuntu 24.04 para WSL ({last}). Descárguela de https://cloud-images.ubuntu.com/wsl/ "
                           f"y guárdela como {tar}")

    def create(self):
        self._rootfs()
        self.reset()

    def reset(self):
        wsl_mgmt(["--unregister", WSL_NAME])
        rc, out = wsl_mgmt(["--import", WSL_NAME, str(self.dir / "vm"), str(self._rootfs()), "--version", "2"], timeout=1800)
        if rc != 0:
            raise RuntimeError(f"wsl --import falló: {out[:300]}")
        wsl_mgmt(["-d", WSL_NAME, "-u", "root", "--exec", "bash", "-c", "printf '[boot]\\nsystemd=true\\n' > /etc/wsl.conf"])
        wsl_mgmt(["--terminate", WSL_NAME])
        self.run_script("systemctl is-system-running --wait >/dev/null 2>&1; true", 180)  # arranca systemd; 'degraded' es aceptable

    def run_script(self, command, timeout=900):
        return run(["wsl", "-d", WSL_NAME, "-u", "root", "--exec", "bash", "-c", command], timeout=timeout)

    def ip(self):
        return "127.0.0.1"

    def destroy(self):
        wsl_mgmt(["--unregister", WSL_NAME])


def port_open(ip, port, timeout=3):
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def http_status(ip):
    try:
        with urllib.request.urlopen(f"http://{ip}/", timeout=5) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None


def install_multipass():
    system = platform.system()
    if system == "Windows":
        if not shutil.which("winget"):
            sys.exit("No se encontró winget. Instale Multipass a mano desde https://multipass.run/download/windows "
                     "(o instale 'Instalador de aplicación' desde Microsoft Store) y vuelva a ejecutar.")
        cmd = ["winget", "install", "--id", "Canonical.Multipass", "-e", "--accept-package-agreements", "--accept-source-agreements"]
    elif system == "Darwin":
        cmd = ["brew", "install", "--cask", "multipass"]
    else:
        cmd = ["sudo", "snap", "install", "multipass"]
    print("Instalando Multipass:", " ".join(cmd))
    r = subprocess.run(cmd)
    if r.returncode != 0:
        sys.exit("No se pudo instalar Multipass. En Windows necesita Hyper-V o VirtualBox y una terminal de administrador; "
                 "en macOS, Homebrew (https://brew.sh). Instálelo a mano desde https://multipass.run y vuelva a ejecutar.")
    if system == "Windows":
        print("Si 'multipass' no se reconoce, cierre y abra la terminal (el PATH se actualiza al abrirla).")


def test_module(be, m, report):
    t0 = time.time()
    results = []

    def add(name, ok, detail=""):
        results.append({"prueba": name, "ok": bool(ok), "detalle": detail[:300]})
        print(f"   [{'OK ' if ok else 'FALLA'}] {name}" + (f" — {detail[:120]}" if not ok and detail else ""))

    setup = setup_dir(m) / "lab_server_setup.sh"
    be.reset()
    be.put(setup, "/tmp/lab_server_setup.sh")
    for extra in EXTRA_FILES.get(m, []):
        be.put(setup.parent / extra, f"/tmp/{extra}")
    r = be.sh("sudo bash /tmp/lab_server_setup.sh", timeout=1500)
    add("el script de preparación termina sin error", r.returncode == 0, (r.stderr or r.stdout)[-300:])
    if r.returncode == 0:
        add("imprime la huella de la clave SSH del servidor", "ED25519" in r.stdout, r.stdout[-200:])
        r2 = be.sh("sudo bash /tmp/lab_server_setup.sh", timeout=1500)
        add("se puede ejecutar de nuevo (idempotente)", r2.returncode == 0, (r2.stderr or r2.stdout)[-300:])
    for name, cmd in COMMON + CHECKS[m]:
        p = be.sh(cmd)
        add(name, p.returncode == 0, (p.stdout + p.stderr).strip())
    for extra in EXTRA_FILES.get(m, []):
        p = be.sh(f"bash /tmp/{extra}")
        add(f"{extra}: en el servidor recién preparado no marca ACT (código 2)", p.returncode in (0, 1), p.stdout[-300:])
    ip = be.ip()
    for port in HOST_OPEN[m]:
        add(f"desde el anfitrión se alcanza {ip}:{port}", port_open(ip, port))
    for port in ([] if getattr(be, "loopback", False) else HOST_CLOSED[m]):
        add(f"desde el anfitrión NO se alcanza {ip}:{port} (solo local)", not port_open(ip, port))
    if 80 in HOST_OPEN[m]:
        st = http_status(ip)
        add("desde el anfitrión, HTTP responde 200 o 403 (página por defecto)", st in (200, 403), str(st))
    report.append({"modulo": m, "segundos": round(time.time() - t0), "pruebas": results})


def write_report(out, be, report, started):
    out.mkdir(parents=True, exist_ok=True)
    stamp = started.strftime("%Y%m%d-%H%M")
    host = f"{platform.system()} {platform.release()} ({platform.machine()})"
    osr = be.sh("lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release").stdout.strip()
    total = sum(len(x["pruebas"]) for x in report)
    bad = sum(1 for x in report for t in x["pruebas"] if not t["ok"])
    data = {"fecha": started.isoformat(timespec="seconds"), "anfitrion": host, "python": platform.python_version(),
            "motor": be.name, "version_motor": be.version(), "sistema_de_la_vm": osr, "total": total, "fallidas": bad, "modulos": report}
    (out / f"informe-vm-{stamp}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    L = [f"# Informe de pruebas de laboratorios en VM — COTN 2150", "",
         f"- **Fecha:** {data['fecha']}", f"- **Anfitrión:** {host}", f"- **Motor:** {be.name} {data['version_motor']}",
         f"- **Sistema de la VM:** {osr}", f"- **Resultado:** {total - bad} de {total} pruebas aprobadas" + (" ✅" if not bad else " ❌"), ""]
    for x in report:
        L.append(f"## Módulo {x['modulo']} ({x['segundos']} s)")
        L.append("")
        L.append("| Prueba | Resultado | Detalle |")
        L.append("|---|---|---|")
        for t in x["pruebas"]:
            L.append(f"| {t['prueba']} | {'Aprobada' if t['ok'] else '**FALLA**'} | {t['detalle'].replace('|', '/').replace(chr(10), ' ')} |")
        L.append("")
    L.append("Límites: prueba la preparación del servidor y su red; no sustituye revisar los pasos de cada guía con una persona. "
             "El laboratorio A1 usa el servidor del Módulo 10. Los Módulos 1 a 3 no tienen servidor de práctica.")
    (out / f"informe-vm-{stamp}.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"\nInforme: {out / f'informe-vm-{stamp}.md'}")
    return bad


class MultipassUnavailable(Exception):
    pass


def ensure_daemon(be):
    """Windows: Multipass es un servicio (Multipass). Si no está en marcha no existe su certificado y 'multipass set/get' fallan."""
    for intento in range(3):
        r = run([be.exe, "version"])
        if r.returncode == 0 and "multipassd" in r.stdout:
            return
        print("El servicio de Multipass no responde; intentando iniciarlo...")
        run(["net", "start", "Multipass"])
        run(["sc", "start", "Multipass"])
        time.sleep(10)
    r = run([be.exe, "version"])
    state = run(["sc", "query", "Multipass"]).stdout.strip()
    raise MultipassUnavailable("El servicio de Multipass no arranca.\n"
             f"Salida de 'multipass version': {(r.stdout + r.stderr).strip()[:300]}\n"
             f"Estado del servicio: {state[:300]}\n"
             "Revise: 1) que la virtualización (VT-x/SVM) esté activada en el BIOS/UEFI; 2) reinicie Windows si acaba de instalar Multipass o Hyper-V; "
             "3) Visor de eventos > Registros de Windows > Aplicación, origen Multipass.")


def prepare_driver(be, wanted):
    """Muestra el motor de virtualización de Multipass y, si se pide, lo cambia. Devuelve un aviso si falta algo."""
    cur = run([be.exe, "get", "local.driver"]).stdout.strip()
    if wanted and wanted != cur:
        r = run([be.exe, "set", f"local.driver={wanted}"])
        if r.returncode != 0:
            sys.exit(f"No se pudo cambiar el motor a {wanted}: {r.stderr.strip() or r.stdout.strip()}\n"
                     "En Windows, abra PowerShell como administrador. VirtualBox debe estar instalado (winget install Oracle.VirtualBox).")
        cur = wanted
        time.sleep(5)  # el servicio de Multipass se reinicia con el cambio
    print(f"Motor de virtualización de Multipass: {cur or 'desconocido'}")
    return cur


def main():
    for stream in (sys.stdout, sys.stderr):  # la consola de Windows puede usar una página de códigos sin flechas ni tildes
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--modules", default=",".join(map(str, ALL_MODULES)))
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--out", default="informe-vm")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--local", action="store_true")
    ap.add_argument("--backend", choices=["auto", "multipass", "wsl"], default="auto", help="Motor de la VM: auto (Multipass y, si no funciona en Windows, WSL2), multipass o wsl (solo Windows)")
    ap.add_argument("--driver", choices=["hyperv", "virtualbox", "qemu"], help="Windows: motor de virtualización de Multipass (Hyper-V en Pro/Enterprise; VirtualBox en Home)")
    a = ap.parse_args()
    mods = [int(x) for x in a.modules.split(",") if x.strip()]
    bad_m = [m for m in mods if m not in ALL_MODULES]
    if bad_m:
        sys.exit(f"Módulos no válidos: {bad_m}. Los servidores de práctica son los de los Módulos {ALL_MODULES}.")
    for m in mods:
        if setup_dir(m) is None:
            sys.exit(f"No se encontró lab_server_setup.sh del Módulo {m}. Ejecute el script dentro del repositorio.")
    be = Local() if a.local else (Wsl() if a.backend == "wsl" else Multipass())
    print(f"Anfitrión: {platform.system()} {platform.release()} ({platform.machine()}) · motor: {be.name} · módulos: {mods}")
    if a.dry_run:
        print("Plan: crear VM Ubuntu 24.04 (Multipass: 2 CPU, 2 GB, 12 GB; en Windows, si Multipass no funciona, WSL2) → instantánea limpia → por módulo: restaurar, copiar y ejecutar "
              "lab_server_setup.sh (dos veces), comprobar dentro de la VM y desde el anfitrión → informe → borrar la VM.")
        return 0
    if a.local:
        if not be.available():
            sys.exit("--local requiere Linux y ejecutar como root.")
    elif a.backend == "wsl":
        if platform.system() != "Windows" or not be.available():
            sys.exit("WSL2 no está disponible. En Windows ejecute como administrador: wsl --install --no-distribution (y reinicie si lo pide).")
    else:
        try:
            if not be.available():
                if a.install:
                    install_multipass()
                    be = Multipass()
                if not be.available():
                    raise MultipassUnavailable("Falta Multipass (use --install o instálelo desde https://multipass.run).")
            if platform.system() == "Windows":
                if not is_admin():
                    print("AVISO: no es una terminal de administrador. Multipass con Hyper-V o VirtualBox suele necesitarla; "
                          "si falla al crear la VM, abra PowerShell como administrador y vuelva a ejecutar.")
                ensure_daemon(be)
                prepare_driver(be, a.driver)
            elif a.driver:
                prepare_driver(be, a.driver)
        except MultipassUnavailable as e:
            if platform.system() == "Windows" and a.backend == "auto" and Wsl().available():
                print(f"\nMultipass no funciona en este equipo:\n{e}\nUsando WSL2 (Ubuntu 24.04) en su lugar.\n")
                be = Wsl()
            else:
                sys.exit(str(e))
    started = datetime.datetime.now()
    report = []
    try:
        print("Creando la VM (la primera vez descarga Ubuntu 24.04; puede tardar varios minutos)...")
        be.create()
        for m in mods:
            print(f"\n== Módulo {m} ==")
            try:
                test_module(be, m, report)
            except Exception as e:  # una falla de infraestructura no detiene los demás módulos
                print("   [FALLA] error de ejecución:", str(e)[:200])
                report.append({"modulo": m, "segundos": 0, "pruebas": [{"prueba": "ejecución de la prueba", "ok": False, "detalle": str(e)[:300]}]})
        bad = write_report(pathlib.Path(a.out), be, report, started)
    finally:
        if not a.keep:
            be.destroy()
    print("TODO APROBADO" if not bad else f"HAY {bad} PRUEBA(S) FALLIDA(S)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
