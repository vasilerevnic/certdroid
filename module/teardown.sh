#!/system/bin/sh
# Removes only this module's tagged overlays. User certificates remain installed.
BB=/data/adb/magisk/busybox
if [ "${CERTDROID_BUSYBOX:-}" != 1 ]; then
  export ASH_STANDALONE=1 CERTDROID_BUSYBOX=1
  exec "$BB" sh "$0" "$@"
fi
MODDIR=/data/adb/modules/certdroid
. "$MODDIR/device-lib.sh"
lock_state
WORK=$(mktemp -d "$STATE/teardown.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
walk_namespaces teardown "$STATE/desired"
