#!/bin/sh
# Registra el agente en el manager y arranca; el alias es el nombre aprobado del curso.
set -e
MANAGER="${WAZUH_MANAGER:-wazuh.manager}"
NAME="${WAZUH_AGENT_NAME:-costa-norte-ubuntu-01}"
sed -i "s|<address>.*</address>|<address>${MANAGER}</address>|" /var/ossec/etc/ossec.conf
# Fuente de eventos del Módulo 7: archivo JSON vigilado por el agente
mkdir -p /var/log/redfaro && touch /var/log/redfaro/events.log
# (ossec.conf del agente tiene varios </ossec_config>: se añade un bloque propio al final, una sola vez)
grep -q "redfaro/events.log" /var/ossec/etc/ossec.conf || printf '\n<ossec_config>\n  <localfile>\n    <log_format>json</log_format>\n    <location>/var/log/redfaro/events.log</location>\n  </localfile>\n</ossec_config>\n' >> /var/ossec/etc/ossec.conf
# Solo se registra la primera vez: /var/ossec/etc es un volumen y conserva client.keys. Si se registrara
# de nuevo, el manager (que conserva el agente) respondería "Duplicate agent name" y no conectaría.
[ -s /var/ossec/etc/client.keys ] || /var/ossec/bin/agent-auth -m "$MANAGER" -A "$NAME" || true
/var/ossec/bin/wazuh-control start
touch /tmp/ready
exec tail -F /var/ossec/logs/ossec.log
