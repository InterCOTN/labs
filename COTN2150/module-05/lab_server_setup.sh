#!/bin/bash
# COTN 2150 · Module 5 · Laboratory: prepares the PRACTICE server (an Ubuntu 24.04 virtual machine) for the web platform laboratory.
# Run once, inside the virtual machine, by the instructor (on-campus) or by you (online):   sudo bash lab_server_setup.sh
# It installs only the SSH service and curl, and creates the account "lab", which may use sudo INSIDE THIS VIRTUAL MACHINE ONLY.
# It does NOT install Apache, PHP or MySQL: the laboratory does that. The password below is a training value for THIS practice machine only.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo bash lab_server_setup.sh"; exit 1; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssh-server curl
id lab >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo lab
usermod -aG sudo lab
echo 'lab:VistaVerde-Practice-5' | chpasswd
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl enable --now ssh
fi
echo "Done. Host key fingerprint of this server (give it to the students through a separate channel):"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
echo "Check that nothing else listens yet (no web server, no database):"
ss -ltn
