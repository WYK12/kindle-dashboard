#!/bin/sh
set -e
BASE=/mnt/us/mydash_v2
HOOK=/mnt/us/emergency.sh
case "${1:-status}" in
 enable)
  grep -q '/mnt/us/emergency.sh' /etc/upstart/kmc.conf || { echo 'No supported boot hook'; exit 1; }
  if [ -e "$HOOK" ] && ! grep -q '^# MYDASH_V2_OWNED_HOOK$' "$HOOK"; then echo 'Existing emergency.sh preserved; cannot enable automatically'; exit 1; fi
  cat > "$HOOK.tmp" <<'EOF'
#!/bin/sh
# MYDASH_V2_OWNED_HOOK
if [ -f /mnt/us/mydash_v2/boot.sh ] && [ ! -f /mnt/us/MYDASH_SAFE_MODE ]; then
 nohup sh /mnt/us/mydash_v2/boot.sh >/mnt/us/mydash_v2/boot.log 2>&1 </dev/null &
fi
exit 0
EOF
  chmod +x "$HOOK.tmp"
  mv "$HOOK.tmp" "$HOOK"
  rm -f "$BASE/DISABLE_AUTOSTART"
  echo 'Autostart enabled; 45 second boot delay'
  ;;
 disable) : > "$BASE/DISABLE_AUTOSTART"; echo 'Autostart disabled' ;;
 remove)
  : > "$BASE/DISABLE_AUTOSTART"
  if [ -f "$HOOK" ] && grep -q '^# MYDASH_V2_OWNED_HOOK$' "$HOOK"; then rm "$HOOK"; fi
  echo 'Owned hook removed; user data retained' ;;
 status) if [ -f "$HOOK" ] && grep -q '^# MYDASH_V2_OWNED_HOOK$' "$HOOK" && [ ! -f "$BASE/DISABLE_AUTOSTART" ]; then echo enabled; else echo disabled; fi ;;
 *) exit 1 ;;
esac
