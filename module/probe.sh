#!/system/bin/sh
# Run the installed copy as root; certificate names are discovered from state.
BB=/data/adb/magisk/busybox
if [ "${CERTDROID_BUSYBOX:-}" != 1 ]; then
  export ASH_STANDALONE=1 CERTDROID_BUSYBOX=1
  exec "$BB" sh "$0" "$@"
fi
MODDIR=/data/adb/modules/certdroid
. "$MODDIR/device-lib.sh"
lock_state
WORK=$(mktemp -d "$STATE/probe.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
[ -d "$STATE/desired" ] || fail 'no activation state found'
walk_namespaces probe "$STATE/desired"
