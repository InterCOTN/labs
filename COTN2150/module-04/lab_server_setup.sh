#!/bin/bash
# COTN 2150 · Module 4 · Laboratory: prepares the PRACTICE server (an Ubuntu 24.04 virtual machine).
# Run once, inside the virtual machine, by the instructor (on-campus) or by you (online):   sudo bash lab_server_setup.sh
# It creates: a normal account "lab" (no administrator rights), a folder /var/www/portal that group "portal" may write,
# and a web server (nginx) that serves that folder. The password below is a training value for THIS practice machine only.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo bash lab_server_setup.sh"; exit 1; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssh-server nginx curl
groupadd -f portal
id lab >/dev/null 2>&1 || useradd -m -s /bin/bash -G portal lab
echo 'lab:VistaVerde-Practice-1' | chpasswd
mkdir -p /var/www/portal
chown root:portal /var/www/portal
chmod 2775 /var/www/portal
if [ ! -f /var/www/portal/index.html ]; then
  printf '<h1>Vista Verde School - Portal</h1>\n<p>Placeholder page. Version 0.</p>\n' > /var/www/portal/index.html
  chown root:portal /var/www/portal/index.html; chmod 664 /var/www/portal/index.html
fi
cat > /etc/nginx/sites-available/portal <<'N'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/portal;
    index index.html;
}
N
ln -sf /etc/nginx/sites-available/portal /etc/nginx/sites-enabled/portal
rm -f /etc/nginx/sites-enabled/default
nginx -t
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl enable --now ssh nginx
  systemctl reload nginx
fi
echo "Done. Host key fingerprint of this server (give it to the students through a separate channel):"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
