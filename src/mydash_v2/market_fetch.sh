#!/bin/sh
BASE=/mnt/us/mydash_v2
LOCK=/tmp/mydash-v2-market
mkdir "$LOCK" 2>/dev/null || exit 0
echo $$ > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' EXIT HUP INT TERM
mkdir -p "$BASE/cache"
export MYDASH_ROOT="$BASE"
export LUA_PATH="$BASE/?.lua;/mnt/us/koreader/common/?.lua;;"
/mnt/us/koreader/luajit "$BASE/market_network.lua" >> "$BASE/markets.log" 2>&1
