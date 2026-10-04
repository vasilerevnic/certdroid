#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")/.." && pwd)
TOOLS="$DIR/tools"
. "$DIR/host/host-lib.sh"
SERIAL=; CA=
usage() { echo "usage: $0 [-s SERIAL] [--ca CERT] [proxy-host proxy-port [https-url]]"; }
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0;;
    -s|--serial) [[ $# -ge 2 ]] || { usage >&2; exit 1; }; SERIAL=$2; shift 2;;
    --ca) [[ $# -ge 2 ]] || { usage >&2; exit 1; }; CA=$2; shift 2;;
    -*) usage >&2; exit 1;;
    *) break;;
  esac
done
[[ $# == 0 || $# == 2 || $# == 3 ]] || { usage >&2; exit 1; }
HOST=${1:-}; PORT=${2:-}; URL=${3:-https://example.com/}
ADB=(adb); [[ -z "$SERIAL" ]] || ADB+=(-s "$SERIAL")
if [[ -z "$CA" ]]; then
  CERTS=()
  for C in "$DIR"/cacerts/*; do [[ -f "$C" ]] && CERTS+=("$C"); done
  [[ ${#CERTS[@]} == 1 ]] || { echo 'Specify --ca when there is not exactly one prepared CA.' >&2; exit 1; }
  CA=${CERTS[0]}
fi
openssl x509 -in "$CA" -noout >/dev/null
if [[ -z "$HOST" ]]; then
  G=$("${ADB[@]}" shell settings get global http_proxy | tr -d '\r')
  if [[ "$G" == *:* && "$G" != ':0' ]]; then HOST=${G%:*}; PORT=${G##*:}; fi
  if [[ -z "$HOST" ]]; then
    WIFI=$("${ADB[@]}" shell dumpsys wifi)
    read -r HOST PORT < <(printf '%s\n' "$WIFI" | sed -nE 's/.*HttpProxy: \[([^]]+)\] ([0-9]+).*/\1 \2/p' | head -1) || :
  fi
fi
[[ -n "$HOST" && "$PORT" =~ ^[0-9]{1,5}$ ]] && ((10#$PORT >= 1 && 10#$PORT <= 65535)) || { echo 'Specify a valid proxy host and port.' >&2; exit 1; }
[[ "$URL" == https://* ]] || { echo 'HTTPS URL required.' >&2; exit 1; }
REMOTE=$("${ADB[@]}" shell 'mktemp -d /data/local/tmp/certdroid-test.XXXXXX' | tr -d '\r')
[[ "$REMOTE" =~ ^/data/local/tmp/certdroid-test\.[a-zA-Z0-9]+$ ]] || { echo 'Could not create test directory.' >&2; exit 1; }
trap '"${ADB[@]}" shell "rm -rf $(shell_quote "$REMOTE")" >/dev/null || :' EXIT
"${ADB[@]}" push "$TOOLS/trusttest.dex" "$REMOTE/trusttest.dex" >/dev/null
"${ADB[@]}" push "$CA" "$REMOTE/expected.pem" >/dev/null
COMMAND="CLASSPATH=$(shell_quote "$REMOTE/trusttest.dex") app_process /system/bin TrustTest $(shell_quote "$HOST") $(shell_quote "$PORT") $(shell_quote "$URL") $(shell_quote "$REMOTE/expected.pem")"
echo "using proxy $HOST:$PORT"
set +e
OUTPUT=$("${ADB[@]}" shell "$COMMAND" 2>&1)
STATUS=$?
set -e
printf '%s\n' "$OUTPUT"
((STATUS == 0)) && printf '%s\n' "$OUTPUT" | grep -q '^RESULT=TRUSTED ' || exit 1
