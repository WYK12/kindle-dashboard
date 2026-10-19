#!/bin/sh
BASE=/mnt/us/mydash_v2
LOCK=/tmp/mydash-v2-network
mkdir "$LOCK" 2>/dev/null || exit 0
echo $$ > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' EXIT HUP INT TERM
export MYDASH_ROOT="$BASE"
export LUA_PATH="$BASE/?.lua;/mnt/us/koreader/common/?.lua;;"
/mnt/us/koreader/luajit "$BASE/network.lua" "$@" >> "$BASE/network.log" 2>&1
