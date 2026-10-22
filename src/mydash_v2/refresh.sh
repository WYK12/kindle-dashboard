#!/bin/sh
BASE=/mnt/us/mydash_v2
LOCK=/tmp/mydash-v2-refresh
REQUEST=/tmp/mydash-v2-refresh-request
case "${1:-auto}" in
 auto) ;;
 update|weather|hotspots|markets) : > "$REQUEST.$1" ;;
 *) exit 1 ;;
esac
mkdir "$LOCK" 2>/dev/null || exit 0
echo $$ > "$LOCK/pid"
cleanup() { rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; }
pending() { for kind in update weather hotspots markets; do [ ! -f "$REQUEST.$kind" ] || return 0; done; return 1; }
trap cleanup EXIT
trap 'exit 143' HUP INT TERM
export MYDASH_ROOT="$BASE"
export LUA_PATH="$BASE/?.lua;/mnt/us/koreader/common/?.lua;;"
while :; do
 MODE=auto
 for kind in update weather hotspots markets; do
  if [ -f "$REQUEST.$kind" ]; then MODE="$MODE,$kind"; rm -f "$REQUEST.$kind"; fi
 done
 /mnt/us/koreader/luajit "$BASE/refresh.lua" "$MODE" >> "$BASE/network.log" 2>&1
 RESULT=$?
 pending || break
done
cleanup
trap - EXIT
# A request may arrive between the final pending check and releasing the lock.
if pending; then exec sh "$0" auto; fi
exit "$RESULT"
