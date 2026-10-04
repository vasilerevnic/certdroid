#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$DIR/host/host-lib.sh"
SERIAL=; USERS=0
usage() { echo "usage: $0 [-s SERIAL | SERIAL] [--user ID|all | --no-user-store]"; }
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0;;
    -s|--serial) [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 1; }; SERIAL=$2; shift 2;;
    --user) [[ $# -ge 2 ]] || { usage >&2; exit 1; }; USERS=$2; [[ "$USERS" == all || "$USERS" =~ ^[0-9]+$ ]] || { usage >&2; exit 1; }; shift 2;;
    --no-user-store) USERS=none; shift;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
    *) [[ -z "$SERIAL" ]] || { usage >&2; exit 1; }; SERIAL=$1; shift;;
  esac
done
ADB=(adb); [[ -z "$SERIAL" ]] || ADB+=(-s "$SERIAL")
validate_certs
"${ADB[@]}" shell getprop ro.product.model
root_command 'id -u' | tr -d '\r' | grep -qx 0 || { echo 'Root access required.' >&2; exit 1; }
LOCAL=$(mktemp -d)
REMOTE=
cleanup() {
  rm -rf "$LOCAL"
  if [[ -n "$REMOTE" ]]; then root_command "rm -rf $(shell_quote "$REMOTE")" >/dev/null || :; fi
}
trap cleanup EXIT
FILES=(module.prop service.sh device-lib.sh namespace.sh user-store.sh deploy.sh uninstall.sh)
for F in "${FILES[@]}"; do cp "$DIR/module/$F" "$LOCAL/$F"; done
mkdir "$LOCAL/cacerts" "$LOCAL/tools"
for C in "$DIR"/cacerts/*; do
  [[ -f "$C" && ! -L "$C" ]] || continue
  # Canonical PEM avoids duplicates caused solely by a text trailer.
  openssl x509 -in "$C" -out "$LOCAL/cacerts/${C##*/}"
done
cp "$DIR/module/probe.sh" "$LOCAL/tools/probe.sh"
cp "$DIR/module/teardown.sh" "$LOCAL/tools/teardown.sh"
printf '%s\n' "$USERS" > "$LOCAL/user-store.conf"
REMOTE=$(root_command 'umask 077; test -x /data/adb/magisk/busybox && mktemp -d /data/adb/.certdroid-install.XXXXXX' | tr -d '\r')
[[ "$REMOTE" =~ ^/data/adb/\.certdroid-install\.[a-zA-Z0-9]+$ ]] || { echo 'Could not create private upload directory.' >&2; REMOTE=; exit 1; }
COPYFILE_DISABLE=1 tar -C "$LOCAL" -cf - . | root_command "/data/adb/magisk/busybox tar -xf - -C $(shell_quote "$REMOTE")"
root_command "ASH_STANDALONE=1 CERTDROID_BUSYBOX=1 /data/adb/magisk/busybox sh $(shell_quote "$REMOTE/deploy.sh")"
REMOTE=
echo 'Installed and activated. Restart target apps before testing.'
