#!/system/bin/sh
# All callers run using Magisk BusyBox with ASH_STANDALONE=1.
STATE=/data/adb/certdroid
STORES='/system/etc/security/cacerts /apex/com.android.conscrypt/cacerts'
BB=/data/adb/magisk/busybox
fail() { echo "certdroid: $*" >&2; exit 1; }
state_init() {
  [ "$(id -u)" = 0 ] || fail 'root required'
  [ ! -L "$STATE" ] || fail 'state directory must not be a symlink'
  mkdir -p "$STATE" || fail 'cannot create state directory'
  chown root:root "$STATE" && chmod 700 "$STATE" || fail 'cannot secure state directory'
}
lock_state() {
  state_init
  if [ "${CERTDROID_LOCK_HELD:-}" != 1 ]; then
    exec 9>"$STATE/lock"
    flock -n 9 || fail 'another installation, activation or removal is running'
    export CERTDROID_LOCK_HELD=1
  fi
}
store_tag() { case "$1" in /system/etc/security/cacerts) echo system;; /apex/com.android.conscrypt/cacerts) echo apex;; *) return 1;; esac; }
# Return false if any mount exactly at this path belongs to somebody else.
owned_or_unmounted() {
  awk -v path="$1" '$5 == path { for (i=7;i<=NF;i++) if ($i == "-") { if ($(i+1) != "tmpfs" || $(i+2) != "certdroid") bad=1; break } } END { exit bad ? 1 : 0 }' /proc/self/mountinfo
}
valid_name() {
  echo "$1" | grep -qE '^[0-9a-f]{8}\.[0-9]+$'
}
same_store() {
  for F in "$1"/*; do
    [ -f "$F" ] || return 1
    [ -f "$2/${F##*/}" ] || return 1
  done
  for F in "$2"/*; do
    [ -f "$F" ] && [ -f "$1/${F##*/}" ] || return 1
  done
  # Compare bytes in one process instead of forking once per certificate.
  diff -qr "$1" "$2" >/dev/null 2>&1
}
# Compare certificate bytes across PEM/DER, without binary shell variables.
cert_equal() (
  cmp -s "$1" "$2" && exit 0
  [ -s "$1" ] && [ -s "$2" ] || exit 1
  CT=$(mktemp -d "$STATE/cert.XXXXXX") || exit 1
  trap 'rm -rf "$CT"' EXIT
  trap 'exit 1' HUP INT TERM
  decode_cert() {
    if grep -q '^-----BEGIN CERTIFICATE-----' "$1"; then
      sed -n '/^-----BEGIN CERTIFICATE-----/,/^-----END CERTIFICATE-----/p' "$1" |
        sed '/^-----/d' | tr -d '\r\n ' | base64 -d > "$2" || return 1
      [ -s "$2" ]
    else cp "$1" "$2"; fi
  }
  decode_cert "$1" "$CT/a" && decode_cert "$2" "$CT/b" && cmp -s "$CT/a" "$CT/b"
)
# Only trim the end of a contiguous hash chain; interior holes hide later CAs.
trim_tombstones() (
  TD=$1; TH=$2; TN=0
  while [ -e "$TD/$TH.$TN" ] || [ -L "$TD/$TH.$TN" ]; do TN=$((TN + 1)); done
  while [ "$TN" -gt 0 ]; do
    TN=$((TN - 1)); TF="$TD/$TH.$TN"
    [ -f "$TF" ] && [ ! -L "$TF" ] && [ ! -s "$TF" ] || break
    rm "$TF" || exit 1
  done
)
# Preserve every existing filename, allocating consecutive collision slots.
merge_certs() {
  DEST=$1
  for C in "$MODDIR"/cacerts/*; do
    [ -f "$C" ] && [ ! -L "$C" ] || return 1
    NAME=${C##*/}; valid_name "$NAME" || return 1
    HASH=${NAME%.*}; N=0
    while [ -e "$DEST/$HASH.$N" ]; do
      cert_equal "$C" "$DEST/$HASH.$N" && break
      N=$((N + 1))
    done
    [ -e "$DEST/$HASH.$N" ] || cp "$C" "$DEST/$HASH.$N" || return 1
  done
}
rotate_log() {
  # Retain one previous activation log, rotating before another run appends.
  if [ -f "$STATE/certdroid.log" ] && [ "$(wc -c < "$STATE/certdroid.log")" -ge 1048576 ]; then
    mv -f "$STATE/certdroid.log" "$STATE/certdroid.log.1" || return 1
  fi
}
wait_for_boot() {
  while [ "$(getprop sys.boot_completed)" != 1 ]; do
    [ -d "$MODDIR" ] && [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || return 1
    sleep 5
  done
  [ -d "$MODDIR" ] && [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ]
}
purge_state() {
  # Keep the lock inode: removing it could let another operation acquire a
  # different lock while this operation still holds the original descriptor.
  for RETAIN in "$STATE"/work.*/retain; do
    [ ! -e "$RETAIN" ] || fail "recovery data retained at $RETAIN; inspect before purging"
  done
  for MI in /proc/[0-9]*/mountinfo; do
    if [ ! -r "$MI" ]; then [ ! -e "$MI" ] && continue; fail "cannot inspect $MI"; fi
    ACTIVE=$(awk -v p="$STATE/" 'index($5,p)==1 {print "mounted"; exit}' "$MI") || {
      [ ! -e "$MI" ] && continue
      fail "cannot inspect $MI"
    }
    [ -z "$ACTIVE" ] || fail "mounts remain under $STATE; reboot and retry before purging"
  done
  for ENTRY in "$STATE"/* "$STATE"/.[!.]* "$STATE"/..?*; do
    [ -e "$ENTRY" ] || [ -L "$ENTRY" ] || continue
    [ "$ENTRY" = "$STATE/lock" ] && continue
    rm -rf "$ENTRY" || return 1
  done
}
walk_namespaces() {
  ACTION=$1; DESIRED=$2
  SEEN="$WORK/seen"; FAILED="$WORK/failed"; ATTEMPTED="$WORK/attempted"
  : > "$SEEN"; : > "$FAILED"
  visit() {
    VP=$1
    VN=$(readlink "/proc/$VP/ns/mnt" 2>/dev/null) || return 0
    grep -qxF "$VN" "$SEEN" && return 0
    grep -qxF "$VN" "$ATTEMPTED" && return 0
    if nsenter --mount="/proc/$VP/ns/mnt" -- "$BB" sh "$MODDIR/namespace.sh" "$ACTION" "$DESIRED" "$WORK" "$VP"; then
      echo "$VN" >> "$SEEN"
    elif [ "$(readlink "/proc/$VP/ns/mnt" 2>/dev/null)" = "$VN" ]; then
      # Only consume the pass's attempt when this PID still represents the
      # namespace. Otherwise another process can retry it in this same pass.
      echo "$VN" >> "$ATTEMPTED"
      echo "certdroid: $ACTION failed in pid=$VP namespace=$VN" >&2
      echo "$VN" >> "$FAILED"
    fi
  }
  # At most one surviving failure per namespace per pass. An exited or moved
  # representative does not prevent another PID from trying in this pass.
  for PASS in 1 2; do
    : > "$ATTEMPTED"
    visit 1
    for VP in $(pidof zygote64 zygote webview_zygote 2>/dev/null) $(ps -A -o pid,comm | awk 'NR>1 && $2 ~ /zygote/ {print $1}'); do visit "$VP"; done
    for PROC in /proc/[0-9]*; do visit "${PROC##*/}"; done
  done
  BAD=0
  while IFS= read -r VN; do grep -qxF "$VN" "$SEEN" || BAD=1; done < "$FAILED"
  [ -s "$SEEN" ] || BAD=1
  echo "$ACTION completed in $(wc -l < "$SEEN") distinct mount namespaces"
  [ "$BAD" = 0 ]
}
