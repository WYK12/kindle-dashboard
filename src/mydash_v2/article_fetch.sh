#!/bin/sh
BASE=${MYDASH_ROOT:-/mnt/us/mydash_v2}
export MYDASH_ROOT="$BASE"
export LUA_PATH="$BASE/?.lua;/mnt/us/koreader/common/?.lua;;"
exec /mnt/us/koreader/luajit "$BASE/article_network.lua" "$1" >> "$BASE/article.log" 2>&1
