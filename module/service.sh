#!/system/bin/sh
BB=/data/adb/magisk/busybox
[ -x "$BB" ] || { echo 'Magisk BusyBox is required.' >&2; exit 1; }
if [ "${CERTDROID_BUSYBOX:-}" != 1 ]; then
  export ASH_STANDALONE=1 CERTDROID_BUSYBOX=1
  exec "$BB" sh "$0" "$@"
fi
MODDIR=${0%/*}
. "$MODDIR/device-lib.sh"
# Magisk's boot service waits without holding the operation lock. Disabling or
# removing the module cancels the wait; a slow boot never exhausts a timer.
case "${1:-}" in
  --activate-now) [ "$(getprop sys.boot_completed)" = 1 ] || fail 'Android is still booting; rerun activation after boot completes';;
  '') if ! wait_for_boot; then
        MESSAGE='Boot activation cancelled: module disabled, marked for removal, or removed.'
        echo "certdroid: $MESSAGE" >&2
        # Log to Android without reopening or recreating purged module state.
        log -p i -t certdroid "$MESSAGE" 2>/dev/null || :
        exit 0
      fi;;
  *) fail 'unknown activation option';;
esac
lock_state
[ -d "$MODDIR" ] && [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || fail 'module disabled or removed; activation cancelled'
rotate_log || fail 'cannot rotate activation log'
exec >>"$STATE/certdroid.log" 2>&1
echo "=== certdroid $(date) ==="
WORK=$(mktemp -d "$STATE/work.XXXXXX") || fail 'cannot create work directory'
# Never recursively remove a directory containing a mount left by failed cleanup.
cleanup() {
  if [ -f "$WORK/retain" ] || awk -v p="$WORK/" 'index($5,p)==1 {found=1} END {exit found ? 0 : 1}' /proc/self/mountinfo; then
    echo "Temporary mounts remain under $WORK; retained for inspection." >&2
  else rm -rf "$WORK"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
pidof zygote64 zygote >/dev/null || fail 'no zygote found; retry after Android starts'
BOOT=$(cat /proc/sys/kernel/random/boot_id) || fail 'cannot read boot id'
BASE="$STATE/baseline"
if [ ! -f "$BASE/boot-id" ] || [ "$(cat "$BASE/boot-id")" != "$BOOT" ]; then
  mkdir "$WORK/baseline" || exit 1
  for D in $STORES; do
    [ -d "$D" ] || continue
    # A first-run live overlay is not a trustworthy baseline. Do not unmount it.
    mountpoint -q "$D" && fail "existing CA-store mount at $D; disable conflicting CA-overlay modules before rebooting. For a legacy module upgrade, reboot once before retrying"
    TAG=$(store_tag "$D")
    mkdir "$WORK/baseline/$TAG" && cp "$D"/* "$WORK/baseline/$TAG"/ || fail "could not copy stock store $D"
    same_store "$D" "$WORK/baseline/$TAG" || fail "stock store changed while copying $D"
  done
  [ -d "$WORK/baseline/system" ] || fail 'system store missing'
  echo "$BOOT" > "$WORK/baseline/boot-id" || exit 1
  rm -rf "$BASE" && mv "$WORK/baseline" "$BASE" || exit 1
fi
mkdir "$WORK/desired" || exit 1
for D in $STORES; do
  [ -d "$D" ] || continue
  TAG=$(store_tag "$D")
  [ -d "$BASE/$TAG" ] || fail "store $D appeared after baseline creation; reboot required"
  mkdir "$WORK/desired/$TAG" && cp "$BASE/$TAG"/* "$WORK/desired/$TAG"/ || fail "cannot stage $D"
  same_store "$BASE/$TAG" "$WORK/desired/$TAG" || fail "incomplete staging of $D"
  merge_certs "$WORK/desired/$TAG" || fail 'invalid or unreadable module certificate'
done
# Retain the desired set so probe can compare contents, including removed CAs.
rm -rf "$STATE/desired"
mv "$WORK/desired" "$STATE/desired" || exit 1
walk_namespaces apply "$STATE/desired" || fail 'activation incomplete; see namespace errors above'
walk_namespaces probe "$STATE/desired" || fail 'final namespace verification failed'
"$BB" sh "$MODDIR/user-store.sh" install || fail 'user store reconciliation failed'
echo 'Activation successful.'
