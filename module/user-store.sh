#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/device-lib.sh"
lock_state
MODE=${1:-install}
USERS=none
if [ "$MODE" = install ]; then
  USERS=$(cat "$MODDIR/user-store.conf") || exit 1
  case "$USERS" in
    all) # Binder shell commands cannot inherit our private log FD under SELinux.
         USER_LIST=$(pm list users 2>&1) || fail "cannot enumerate Android users: $USER_LIST"
         USERS=$(printf '%s\n' "$USER_LIST" | sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p')
         [ -n "$USERS" ] || fail 'cannot enumerate Android users';;
    none) :;;
    *[!0-9]*|'') fail 'invalid user-store configuration';;
  esac
elif [ "$MODE" != remove ]; then fail 'unknown user-store action'; fi
mkdir -p "$STATE/users" || exit 1
# Delete only unchanged files for which this module recorded ownership.
for UDIR in "$STATE/users"/*; do
  [ -d "$UDIR" ] || continue
  U=${UDIR##*/}; D="/data/misc/user/$U/cacerts-added"
  SELECTED=0
  for ID in $USERS; do [ "$ID" = "$U" ] && SELECTED=1; done
  for RECORD in "$UDIR"/*; do
    [ -f "$RECORD" ] || continue
    KEEP=0
    if [ "$SELECTED" = 1 ]; then
      for C in "$MODDIR"/cacerts/*; do cmp -s "$C" "$RECORD" && KEEP=1; done
    fi
    NAME=${RECORD##*/}
    if [ "$KEEP" = 1 ] && cmp -s "$RECORD" "$D/$NAME"; then continue; fi
    if [ -e "$D/$NAME" ]; then
      if cmp -s "$RECORD" "$D/$NAME"; then
        # A zero-length tombstone preserves hash-chain lookup for later slots.
        : > "$D/$NAME" || exit 1
      else echo "Preserving externally changed user certificate: $D/$NAME" >&2; fi
    fi
    trim_tombstones "$D" "${NAME%.*}" || exit 1
    rm "$RECORD" || exit 1
  done
  rmdir "$UDIR" 2>/dev/null || :
done
[ "$USERS" != none ] || exit 0
for U in $USERS; do
  [ -d "/data/misc/user/$U" ] || fail "user $U is unavailable; unlock/start that user first"
  D="/data/misc/user/$U/cacerts-added"
  OWNER=$((U * 100000 + 1000))
  if [ ! -d "$D" ]; then
    mkdir "$D" && chown "$OWNER:$OWNER" "$D" && chmod 775 "$D" && chcon u:object_r:misc_user_data_file:s0 "$D" || exit 1
  fi
  mkdir -p "$STATE/users/$U" || exit 1
  for C in "$MODDIR"/cacerts/*; do
    NAME=${C##*/}; valid_name "$NAME" || exit 1
    HASH=${NAME%.*}; N=0; FOUND=0
    while [ -e "$D/$HASH.$N" ] || [ -L "$D/$HASH.$N" ]; do
      cert_equal "$C" "$D/$HASH.$N" && { FOUND=1; break; }
      N=$((N + 1))
    done
    [ "$FOUND" = 0 ] || continue
    TMP=$(mktemp "$D/.certdroid.XXXXXX") || exit 1
    if ! { cp "$C" "$TMP" && chown "$OWNER:$OWNER" "$TMP" && chmod 644 "$TMP" && chcon u:object_r:misc_user_data_file:s0 "$TMP"; }; then rm -f "$TMP"; exit 1; fi
    # Never unlink an existing slot during installation: Android does not share
    # our lock, so an empty-file check cannot make replacement safe.
    if ! ln "$TMP" "$D/$HASH.$N"; then
      rm -f "$TMP"; fail 'user store changed concurrently; rerun activation'
    fi
    if ! cp "$C" "$STATE/users/$U/$HASH.$N"; then
      cmp -s "$TMP" "$D/$HASH.$N" && : > "$D/$HASH.$N"
      rm -f "$TMP"; exit 1
    fi
    rm "$TMP" || exit 1
    echo "Installed user $U CA: $HASH.$N"
  done
done
