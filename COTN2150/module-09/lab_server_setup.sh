#!/bin/bash
# COTN 2150 · Module 9 · Laboratory: prepares the PRACTICE server (an Ubuntu 24.04 virtual machine) for the licenses and ethics laboratory.
# Run once, inside the virtual machine, by the instructor (on-campus) or by you (online):   sudo bash lab_server_setup.sh
# It installs SSH, curl, the Apache web server with PHP and a local-only mail server (Postfix), and creates the account "lab",
# which may use sudo INSIDE THIS VIRTUAL MACHINE ONLY. The laboratory then inventories, checks and repairs it (in a controlled way).
# The password below is a training value for THIS practice machine only.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo bash lab_server_setup.sh"; exit 1; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string vistaverde.test" | debconf-set-selections
apt-get install -y -qq openssh-server curl apache2 libapache2-mod-php postfix
id lab >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo lab
usermod -aG sudo lab
echo 'lab:VistaVerde-Practice-9' | chpasswd
for u in maestra1 director1; do id "$u" >/dev/null 2>&1 || useradd -m -s /usr/sbin/nologin "$u"; done
postconf -e "maillog_file = /var/log/postfix.log"
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl enable --now ssh apache2 postfix
  systemctl reload postfix
fi
echo "Done. Host key fingerprint of this server (give it to the students through a separate channel):"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
echo "Services that should be listening now (22 SSH, 80 web, 25 local mail):"
ss -ltn
