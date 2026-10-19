#!/bin/sh
BASE=/mnt/us/mydash_v2
PID=$(cat /tmp/mydash-v2.pid 2>/dev/null)
case "$PID" in ''|*[!0-9]*) ;; *)
 if [ -r "/proc/$PID/cmdline" ] && grep -q "$BASE/home.lua" "/proc/$PID/cmdline"; then
  : > /tmp/mydash-v2.stop
  N=0
  while kill -0 "$PID" 2>/dev/null && [ "$N" -lt 5 ]; do sleep 1; N=$((N+1)); done
  kill -0 "$PID" 2>/dev/null && kill -TERM "$PID"
 fi ;;
esac
rm -f /tmp/mydash-v2.pid
