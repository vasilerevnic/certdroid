#!/usr/bin/env bash
# Usage: ./host/prepare-cert.sh <cert.der|cert.pem>
set -euo pipefail
if [[ $# != 1 || ! -f "$1" ]]; then echo "usage: $0 <cert.der|cert.pem>" >&2; exit 1; fi
SRC=$1
DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$DIR/host/host-lib.sh"
OUT="$DIR/cacerts"
mkdir -p "$OUT"
TEMP=$(mktemp -d "$OUT/.prepare.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT
if openssl x509 -inform DER -in "$SRC" -out "$TEMP/cert.pem" 2>/dev/null; then FORM=DER
elif openssl x509 -inform PEM -in "$SRC" -out "$TEMP/cert.pem" 2>/dev/null; then FORM=PEM
else echo "Not a valid certificate: $SRC" >&2; exit 1; fi
TEXT=$(certificate_constraints "$TEMP/cert.pem")
[[ "$TEXT" == *CA:TRUE* ]] || { echo 'Certificate must have CA:TRUE.' >&2; exit 1; }
openssl x509 -in "$TEMP/cert.pem" -checkend 0 -noout >/dev/null || { echo 'Certificate is expired.' >&2; exit 1; }
openssl x509 -in "$TEMP/cert.pem" -checkend 2592000 -noout >/dev/null || echo 'Warning: CA expires within 30 days.' >&2
HASH=$(openssl x509 -in "$TEMP/cert.pem" -subject_hash_old -noout)
FP=$(openssl x509 -in "$TEMP/cert.pem" -fingerprint -sha256 -noout)
# Deduplicate by certificate identity, even if an existing file has a text trailer.
for CERT in "$OUT/$HASH".*; do
  [[ -f "$CERT" ]] || continue
  if [[ "$(openssl x509 -in "$CERT" -fingerprint -sha256 -noout)" == "$FP" ]]; then
    echo "already prepared: $CERT"; exit 0
  fi
done
N=0
# A hard link publishes the complete file without overwriting another invocation.
while ! ln "$TEMP/cert.pem" "$OUT/$HASH.$N" 2>/dev/null; do
  [[ -e "$OUT/$HASH.$N" || -L "$OUT/$HASH.$N" ]] || { echo 'Cannot publish certificate.' >&2; exit 1; }
  N=$((N + 1))
done
chmod 644 "$OUT/$HASH.$N"
echo "form: $FORM"
openssl x509 -in "$TEMP/cert.pem" -noout -subject -dates -fingerprint -sha256
echo "written: $OUT/$HASH.$N"
