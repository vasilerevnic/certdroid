#!/usr/bin/env bash
# Export only public project files; never local CAs, backups, keys or build scratch.
set -euo pipefail
DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$PWD/certdroid.tar.gz"}
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
DEST="$TEMP/certdroid"
mkdir -p "$DEST/cacerts" "$DEST/host" "$DEST/module" "$DEST/tools"
for F in README.md CHANGELOG.md LICENSE; do cp "$DIR/$F" "$DEST/"; done
for F in host-lib.sh prepare-cert.sh install.sh build-trust-test.sh trust-test.sh uninstall-via-adb.sh package.sh; do cp "$DIR/host/$F" "$DEST/host/"; done
for F in module.prop service.sh device-lib.sh namespace.sh user-store.sh deploy.sh uninstall.sh probe.sh teardown.sh; do cp "$DIR/module/$F" "$DEST/module/"; done
for F in README.md TrustTest.java trusttest.dex trusttest.dex.sha256; do cp "$DIR/tools/$F" "$DEST/tools/"; done
touch "$DEST/cacerts/.gitkeep"
COPYFILE_DISABLE=1 tar -C "$TEMP" -czf "$OUT" certdroid
echo "Public archive: $OUT"
