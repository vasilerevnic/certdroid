#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/device-lib.sh"
ACTION=$1; DESIRED=$2; WORK=$3; PID=$4
# Keep rollback CONTENTS on disk. Temporary bind mounts under a shared /data
# can propagate into other namespaces and undo destination mounts on cleanup.
D=; BACK=; HAD_OWN=0; CHANGED=0
populate() {
  cp "$1"/* "$D"/ && chown root:root "$D" "$D"/* && chmod 755 "$D" && chmod 644 "$D"/* &&
    chcon u:object_r:system_security_cacerts_file:s0 "$D" "$D"/* && same_store "$1" "$D" &&
    mount -o remount,ro "$D"
}
new_store() { mount -t tmpfs -o mode=0755,uid=0,gid=0,nodev,nosuid,noexec certdroid "$D"; }
rollback() {
  [ "$CHANGED" = 1 ] || return 0
  if ! owned_or_unmounted "$D"; then
    echo "CRITICAL: mount changed during rollback at $D; backup: $BACK" >&2
    touch "$WORK/retain"; return 1
  fi
  while mountpoint -q "$D"; do
    umount "$D" || { touch "$WORK/retain"; return 1; }
  done
  if [ "$HAD_OWN" = 1 ]; then
    new_store && populate "$BACK" || {
      echo "CRITICAL: could not restore $D; backup: $BACK" >&2
      touch "$WORK/retain"; return 1
    }
  fi
}
trap rollback EXIT
trap 'exit 1' HUP INT TERM
for D in $STORES; do
  [ -d "$D" ] || continue
  TAG=$(store_tag "$D")
  S="$DESIRED/$TAG"
  if [ "$ACTION" = probe ]; then
    [ -d "$S" ] || { echo "No recorded desired store for $D" >&2; exit 1; }
    same_store "$S" "$D" || { echo "MISMATCH pid=$PID $D" >&2; exit 1; }
    echo "MATCH pid=$PID $D"; continue
  fi
  owned_or_unmounted "$D" || { echo "Refusing foreign/legacy mount at $D; disable conflicting CA-overlay modules before rebooting, or reboot once after a legacy module upgrade." >&2; exit 1; }
  if [ "$ACTION" = teardown ]; then
    while mountpoint -q "$D"; do umount "$D" || exit 1; done
    continue
  fi
  [ "$ACTION" = apply ] && [ -d "$S" ] || exit 1
  LAYERS=$(awk -v path="$D" '$5 == path {n++} END {print n+0}' /proc/self/mountinfo)
  if same_store "$S" "$D" && [ "$LAYERS" -le 1 ]; then continue; fi
  BACK=$(mktemp -d "$WORK/backup-$PID-$TAG.XXXXXX") || exit 1
  cp "$D"/* "$BACK"/ && same_store "$D" "$BACK" || exit 1
  HAD_OWN=0
  mountpoint -q "$D" && HAD_OWN=1
  CHANGED=1
  while mountpoint -q "$D"; do umount "$D" || exit 1; done
  new_store && populate "$S" || exit 1
  CHANGED=0
  echo "APPLIED pid=$PID $D"
done
