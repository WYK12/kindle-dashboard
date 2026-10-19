#!/bin/sh
# Follow KOReader's Kindle launcher: hide pillow and pause awesome while drawing.
# Keep ownership flags outside USB storage so exit/crash cleanup can restore them.
STATE=${MYDASH_NATIVE_STATE:-/tmp/mydash-v2-native}
mkdir -p "$STATE" || exit 1
show_native() {
 if [ -f "$STATE/cvm" ]; then
  killall -CONT cvm || return 1
  rm -f "$STATE/cvm"
 fi
 if [ -f "$STATE/awesome" ]; then
  killall -CONT awesome || return 1
  rm -f "$STATE/awesome"
 fi
 if [ -f "$STATE/pillow" ]; then
  lipc-set-prop com.lab126.pillow disableEnablePillow enable || return 1
  rm -f "$STATE/pillow"
 fi
 if [ -f "$STATE/native-touch" ]; then
  /mnt/us/koreader/luajit "${MYDASH_ROOT:-/mnt/us/mydash_v2}/native_touch.lua" restore "$STATE/native-touch" || return 1
 fi
 if [ -f "$STATE/volumd" ]; then
  killall -CONT volumd || return 1
  rm -f "$STATE/volumd"
 fi
}
restore_sleep() {
 if [ -f "$STATE/screensaver" ]; then
  PREVIOUS=$(cat "$STATE/screensaver")
  case "$PREVIOUS" in 0|1) ;; *) return 1 ;; esac
  lipc-set-prop com.lab126.powerd preventScreenSaver "$PREVIOUS" || return 1
  rm -f "$STATE/screensaver"
 fi
}
case "${1:-restore}" in
 hide)
  # Like KOReader, keep USBMS from exporting the partition we execute from.
  # Reassert after reader handoffs, even when we already own the marker.
  if killall -0 volumd 2>/dev/null; then
   : > "$STATE/volumd"
   killall -STOP volumd || exit 1
  fi
  if [ ! -f "$STATE/pillow" ]; then
   : > "$STATE/pillow"
   lipc-set-prop com.lab126.pillow disableEnablePillow disable || exit 1
  fi
  if [ ! -f "$STATE/awesome" ]; then
   : > "$STATE/awesome"
   killall -STOP awesome || exit 1
  fi
  # PW3's Java reader clock can still draw after pillow/awesome are paused.
  if [ ! -f "$STATE/cvm" ] && killall -0 cvm 2>/dev/null; then
   : > "$STATE/cvm"
   killall -STOP cvm || exit 1
  fi
  # Native dialogs leave a display-controller halftone mask outside /dev/fb0.
  # Clear it after pausing the WM, using the same API as its lightbox code.
  DISPLAY=:0 lua -e 'require("liblab126IGL"); local ref=assert(ligl.init()); ligl.apply_halftone(ref,0); ligl.deinit(ref)' || exit 1
  # Keep native input closed across the interval between evdev owners.
  /mnt/us/koreader/luajit "${MYDASH_ROOT:-/mnt/us/mydash_v2}/native_touch.lua" disable "$STATE/native-touch" || exit 1
  ;;
 show) show_native || exit 1 ;;
 awake)
  case "$2" in
   1)
    if [ ! -f "$STATE/screensaver" ]; then
     PREVIOUS=$(lipc-get-prop com.lab126.powerd preventScreenSaver) || exit 1
     case "$PREVIOUS" in 0|1) ;; *) exit 1 ;; esac
     printf '%s\n' "$PREVIOUS" > "$STATE/screensaver" || exit 1
    fi
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 || exit 1
    ;;
   0) restore_sleep || exit 1 ;;
   *) exit 1 ;;
  esac
  ;;
 restore)
  # Try both even if one service is unavailable; keep failed flags for retry.
  RESULT=0
 restore_sleep || RESULT=1
  show_native || RESULT=1
  rm -f "$STATE/reader-handoff"
  rmdir "$STATE" 2>/dev/null
  exit "$RESULT"
  ;;
 *) exit 1 ;;
esac
