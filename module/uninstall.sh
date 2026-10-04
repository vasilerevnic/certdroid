#!/system/bin/sh
# Magisk uninstall hook; also called by host/uninstall-via-adb.sh on the host.
BB=/data/adb/magisk/busybox
if [ "${CERTDROID_BUSYBOX:-}" != 1 ]; then
  export ASH_STANDALONE=1 CERTDROID_BUSYBOX=1
  exec "$BB" sh "$0" "$@"
fi
MODDIR=${0%/*}
. "$MODDIR/device-lib.sh"
DELETE=0; PURGE=0
for ARG in "$@"; do
  case "$ARG" in --delete) DELETE=1;; --purge-state) PURGE=1;; *) fail 'unknown uninstall option';; esac
done
lock_state
# Disable boot activation even if an unavailable namespace prevents cleanup.
touch "$MODDIR/disable" || exit 1
STATUS=0
"$BB" sh "$MODDIR/tools/teardown.sh" || STATUS=1
"$BB" sh "$MODDIR/user-store.sh" remove || STATUS=1
[ "$STATUS" = 0 ] || { echo 'Cleanup incomplete; module disabled. Reboot and retry removal.' >&2; exit 1; }
echo 'Owned overlays and unchanged owned user CAs removed.'
[ "$PURGE" = 0 ] || purge_state || exit 1
if [ "$DELETE" = 1 ]; then
  rm -rf "$MODDIR" || exit 1
fi
