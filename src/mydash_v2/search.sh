#!/bin/sh
BASE=/mnt/us/mydash_v2
mkdir -p "$BASE/cache"
export MYDASH_ROOT="$BASE"
export LUA_PATH="$BASE/?.lua;/mnt/us/koreader/common/?.lua;;"
exec /mnt/us/koreader/luajit "$BASE/search_network.lua" "$@" >> "$BASE/search.log" 2>&1
