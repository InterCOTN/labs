#!/bin/sh
# Emite los 6 eventos del escenario del Módulo 7 (idénticos para todos los estudiantes).
# Uso (desde la carpeta wazuh/):  docker compose ... exec endpoint /usr/local/bin/m7-emit.sh
# event_time es el reloj del escenario; la hora de ingestión real de Wazuh será otra.
mkdir -p /var/log/redfaro
LOG=/var/log/redfaro/events.log
w(){ printf '%s\n' "$1" >> "$LOG"; }
w '{"lab":"redfaro-m7","event_id":"E1","event_time":"2026-03-02T09:02:00","service":"identity","outcome":"rejected","note":"rejected authentication"}'
w '{"lab":"redfaro-m7","event_id":"E2","event_time":"2026-03-02T09:03:00","service":"identity","outcome":"rejected","note":"second rejected authentication"}'
w '{"lab":"redfaro-m7","event_id":"E3","event_time":"2026-03-02T09:05:00","service":"identity","outcome":"success","note":"successful authentication"}'
w '{"lab":"redfaro-m7","event_id":"E4","event_time":"2026-03-02T09:06:00","service":"portal","outcome":"allowed","session":"S-42","action":"view"}'
w '{"lab":"redfaro-m7","event_id":"E5","event_time":"2026-03-02T09:08:00","service":"portal","outcome":"denied","session":"S-42","action":"export"}'
w '{"lab":"redfaro-m7","event_id":"E6","event_time":"2026-03-02T09:10:00","service":"operations","note":"scheduled activity note"}'
echo "Emitted 6 events to $LOG"
