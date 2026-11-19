# Instalación en Linux (Ubuntu 22.04/24.04; otras distribuciones: ver docs.docker.com)

## 0. Requisitos
x86_64 (arm64: sin confirmar), 16 GB de RAM, 4 núcleos, 100 GB libres, usuario con `sudo`.

## 1. Docker Engine + Compose (repositorio oficial de Docker)
```
sudo apt-get update
sudo apt-get install -y ca-certificates curl git python3
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker
```
No uses Docker instalado como paquete *snap* (no soportado por Greenbone). Comprueba:
```
docker --version
docker compose version
docker run --rm hello-world
```

## 2. Ajuste del kernel para Wazuh
```
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf
```

## 3. Obtener el material
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
| `Cannot connect to the Docker daemon` | `sudo systemctl enable --now docker` y repite `docker run --rm hello-world`. |
| Faltan archivos al copiar | Los entornos necesitan la carpeta completa `lab-environment`, no solo los `compose.*.yaml`. |
| `permission denied ... docker.sock` | Cierra sesión y vuelve a entrar tras `usermod -aG docker`. |
| Wazuh indexer se reinicia | Revisa `sysctl vm.max_map_count` (≥ 262144). |
| `python` no existe | Usa `python3`. |
