#!/bin/sh
BASE=/mnt/us/mydash_v2
cd "$BASE" || exit 1
# USB-storage FUSE can corrupt a running shell's reads after file replacement.
# Run an atomic tmpfs snapshot, as KOReader's own launcher does.
if [ "$0" != /var/tmp/mydash-v2-run.sh ]; then
 cp "$BASE/run.sh" /var/tmp/mydash-v2-run.sh.new &&
 mv /var/tmp/mydash-v2-run.sh.new /var/tmp/mydash-v2-run.sh || {
  sh "$BASE/native_ui.sh" restore >> "$BASE/app.log" 2>&1;exit 1;
 }
 exec sh /var/tmp/mydash-v2-run.sh "$@"
fi
DIRECT_HOME=no
case "$(cat /tmp/mydash-v2-return 2>/dev/null)" in
 home) DIRECT_HOME=yes;rm -f /tmp/mydash-v2-resume /tmp/mydash-v2-return ;;
 rss) DIRECT_HOME=yes;printf rss > /tmp/mydash-v2-resume;rm -f /tmp/mydash-v2-return ;;
esac
if [ -f /tmp/mydash-v2.pid ]; then
  PID=$(cat /tmp/mydash-v2.pid)
  case "$PID" in ''|*[!0-9]*) ;; *) if kill -0 "$PID" 2>/dev/null && grep -q "$BASE/home.lua" "/proc/$PID/cmdline"; then echo 'MyDash already running'; exit 0; fi ;; esac
fi
mkdir /tmp/mydash-v2-start 2>/dev/null || exit 1
CHILD=
cleanup() {
 sh "$BASE/native_ui.sh" restore >> "$BASE/app.log" 2>&1
 RESTORE_STATUS=$?
 rmdir /tmp/mydash-v2-start 2>/dev/null
 return "$RESTORE_STATUS"
}
trap cleanup EXIT
trap 'if [ -n "$CHILD" ]; then kill -TERM "$CHILD" 2>/dev/null; wait "$CHILD" 2>/dev/null; fi; exit 143' HUP INT TERM
pgrep -f '(^|[ /])reader[.]lua([[:space:]]|$)' >/dev/null && { echo 'KOReader is active; refusing to capture input'; exit 1; }
[ -x /mnt/us/koreader/luajit ] || exit 1
mkdir -p "$BASE/cache"
# The bundled KOReader renderer works on this device; libkh's build crashes during init.
cp /mnt/us/koreader/fbink /var/tmp/mydash-v2-fbink || exit 1
chmod +x /var/tmp/mydash-v2-fbink
/var/tmp/mydash-v2-fbink -e > "$BASE/fbink-state.txt" 2>> "$BASE/app.log" || exit 1
grep -q 'screenWidth=1072;screenHeight=1448;' "$BASE/fbink-state.txt" || { echo 'Unsupported screen geometry'; exit 1; }
export MYDASH_ROOT="$BASE"
export LUA_PATH="$BASE/?.lua;/mnt/us/koreader/common/?.lua;;"
if [ "$DIRECT_HOME" = yes ] && [ -f "${MYDASH_NATIVE_STATE:-/tmp/mydash-v2-native}/reader-handoff" ]; then
 rm -f "${MYDASH_NATIVE_STATE:-/tmp/mydash-v2-native}/reader-handoff"
else
 sh "$BASE/native_ui.sh" restore >> "$BASE/app.log" 2>&1 || exit 1
 lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
 sleep 1
fi
rm -f "$BASE/next_action"
cd /mnt/us/koreader || exit 1
/mnt/us/koreader/luajit "$BASE/home.lua" >> "$BASE/app.log" 2>&1 &
CHILD=$!
wait "$CHILD"
RESULT=$?
CHILD=
ACTION=$(cat "$BASE/next_action" 2>/dev/null)
rm -f "$BASE/next_action"
case "$RESULT:$ACTION" in
 0:bookstore|0:reader|0:readarticle)
  # Keep native UI paused until the reader owns it; traps still restore on failure.
  rmdir /tmp/mydash-v2-start 2>/dev/null ;;
 *)
  cleanup || { echo "Cannot restore native UI: inspect app.log"; exit 1; }
  trap - EXIT HUP INT TERM ;;
esac
if [ "$RESULT" != 0 ]; then
 echo 'MyDash stopped: inspect app.log'
 lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
 exit "$RESULT"
fi
case "$ACTION" in
 bookstore)
  BOOKDIR=/mnt/us/Books
  mkdir -p "$BOOKDIR"
  cd /mnt/us
  MYDASH_MANAGED_READER=1 MYDASH_BOOKSTORE=1 sh /mnt/us/kmc/kpm/packages/koreader/launch.sh --asap "$BOOKDIR" >> "$BASE/koreader.log" 2>&1
  pgrep -f '(^|[ /])reader[.]lua([[:space:]]|$)' >/dev/null && exit 0
  exec sh "$BASE/run.sh" ;;
 reader)
  BOOK=$(cat "$BASE/reader_book" 2>/dev/null)
  rm -f "$BASE/reader_book"
  case "$BOOK" in /mnt/us/Books/*.epub|/mnt/us/Books/*.pdf|/mnt/us/Books/*.mobi) ;; *) exit 1 ;; esac
  case "$BOOK" in */../*|*/./*) exit 1 ;; esac
  [ -f "$BOOK" ] || exit 1
  cd /mnt/us
  MYDASH_MANAGED_READER=1 MYDASH_BOOKSTORE=1 sh /mnt/us/kmc/kpm/packages/koreader/launch.sh --asap "$BOOK" >> "$BASE/koreader.log" 2>&1
  if [ "$(cat /tmp/mydash-v2-return 2>/dev/null)" = home ]; then exec sh "$BASE/run.sh"; fi ;;
 browser) lipc-set-prop com.lab126.appmgrd start app://com.lab126.browser ;;
 readarticle)
  ID=$(cat "$BASE/reader_id" 2>/dev/null)
  case "$ID" in ''|*[!0-9a-f]*) exit 1 ;; esac
  [ "${#ID}" = 24 ] && [ -f "/mnt/us/RSS/$ID.epub" ] || exit 1
  cd /mnt/us
  MYDASH_MANAGED_READER=1 sh /mnt/us/kmc/kpm/packages/koreader/launch.sh --asap "/mnt/us/RSS/$ID.epub" >> "$BASE/koreader.log" 2>&1
  pgrep -f '(^|[ /])reader[.]lua([[:space:]]|$)' >/dev/null && exit 0
  printf rss > /tmp/mydash-v2-resume
  exec sh "$BASE/run.sh" ;;
 native) lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home ;;
esac
