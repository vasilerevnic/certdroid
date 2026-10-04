#!/system/bin/sh
# Executed from a private, root-owned upload directory.
MODDIR=${0%/*}
. "$MODDIR/device-lib.sh"
lock_state
TARGET=/data/adb/modules/certdroid
BACK="$STATE/module.previous"
[ ! -e "$BACK" ] || fail "previous deployment backup exists at $BACK; inspect before retrying"
chown -R root:root "$MODDIR" && find "$MODDIR" -type d -exec chmod 755 {} \; && find "$MODDIR" -type f -exec chmod 644 {} \; && chmod 755 "$MODDIR/service.sh" "$MODDIR/uninstall.sh" && chcon -R u:object_r:system_file:s0 "$MODDIR" || exit 1
mkdir -p /data/adb/modules || exit 1
[ ! -e "$TARGET" ] || mv "$TARGET" "$BACK" || exit 1
if ! mv "$MODDIR" "$TARGET"; then
  [ ! -e "$BACK" ] || mv "$BACK" "$TARGET"
  exit 1
fi
rm -rf "$BACK"
echo 'Module installed. Activating; log: /data/adb/certdroid/certdroid.log'
if "$BB" sh "$TARGET/service.sh" --activate-now; then
  tail -10 "$STATE/certdroid.log"
else
  tail -30 "$STATE/certdroid.log" >&2
  echo 'Activation failed. Module remains installed; review the log before retrying.' >&2
  exit 1
fi
