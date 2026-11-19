#!/bin/bash
# Alerts only after 2 failed runs in a row. State is kept in a small file.
FILE=~/.vv-failures
out=$(~/comprobar.sh); st=$?
if [ "$st" -eq 2 ]; then
  n=$(( $(cat "$FILE" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FILE"
  if [ "$n" -ge 2 ]; then echo "ALERT ($n failures in a row)"; echo "$out" | grep ACT
  else echo "no alert (failures in a row: $n)"; fi
else
  echo 0 > "$FILE"; echo "no alert (failures in a row: 0)"
fi
