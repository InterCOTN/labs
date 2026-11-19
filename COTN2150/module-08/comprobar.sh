#!/bin/bash
# Practice check of the Vista Verde portal. Exit code: 0 all OK, 1 something to WATCH, 2 ACT.
VIGILAR=${VIGILAR:-80}; ACTUAR=${ACTUAR:-90}; URL=${URL:-http://127.0.0.1/}
trap 'echo "exit code: $?"' EXIT
state=0
mark() {
  echo "$(date '+%F %T') $1 $2"
  if [ "$1" = "ACT" ]; then state=2
  elif [ "$1" = "WATCH" ] && [ "$state" -lt 1 ]; then state=1
  fi
}
if ss -ltn | grep -q ':80 '; then mark OK "port 80 listens"; else mark ACT "port 80 does not listen"; fi
code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$URL")
if [ "$code" = "200" ]; then mark OK "web answers 200"; else mark ACT "web answers $code"; fi
use=$(df --output=pcent / | tail -n 1 | tr -dc '0-9')
if [ "$use" -ge "$ACTUAR" ]; then mark ACT "disk at ${use}%"
elif [ "$use" -ge "$VIGILAR" ]; then mark WATCH "disk at ${use}%"
else mark OK "disk at ${use}%"; fi
queued=$(postqueue -p 2>/dev/null | grep -c '^[0-9A-F]\{8,\}')
if [ "$queued" -le 5 ]; then mark OK "mail queue: $queued"; else mark WATCH "mail queue: $queued"; fi
exit $state
