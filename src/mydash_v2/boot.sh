#!/bin/sh
BASE=/mnt/us/mydash_v2
sleep 45
[ -f "$BASE/DISABLE_AUTOSTART" ] && exit 0
[ -f /mnt/us/MYDASH_SAFE_MODE ] && exit 0
pgrep -f '(^|[ /])reader[.]lua([[:space:]]|$)' >/dev/null && exit 0
nohup sh "$BASE/run.sh" >> "$BASE/boot.log" 2>&1 </dev/null &
