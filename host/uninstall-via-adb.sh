#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$DIR/host/host-lib.sh"
ADB=(adb)
SERIAL=; PURGE=
usage() { echo "usage: $0 [-s SERIAL | SERIAL] [--purge-state]"; }
argument_error() { echo "$*" >&2; usage >&2; exit 1; }
select_serial() {
  [[ -n "$1" && "$1" != -* ]] || argument_error 'A nonempty device serial is required.'
  [[ -z "$SERIAL" ]] || argument_error 'Specify only one device serial.'
  SERIAL=$1
}
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0;;
    -s|--serial)
      [[ $# -ge 2 ]] || argument_error 'Missing device serial after -s/--serial.'
      select_serial "$2"; shift 2;;
    --purge-state) PURGE=' --purge-state'; shift;;
    -*) argument_error "Unknown option: $1";;
    *) select_serial "$1"; shift;;
  esac
done
[[ -z "$SERIAL" ]] || ADB+=(-s "$SERIAL")
root_command "sh /data/adb/modules/certdroid/uninstall.sh --delete$PURGE"
echo 'Module removed. Restart apps; reboot to discard cached trust decisions.'
