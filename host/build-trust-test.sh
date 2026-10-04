#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")/../tools" && pwd)
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}}
D8=${D8:-"$SDK/build-tools/37.0.0/d8"}
[[ -x "$D8" ]] || { echo 'Set D8 to an installed Android build-tools d8 executable.' >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then SHA=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then SHA=(shasum -a 256)
else echo 'Install sha256sum or shasum to generate the DEX checksum.' >&2; exit 1; fi
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
javac --release 8 -d "$TEMP" "$DIR/TrustTest.java"
"$D8" --min-api 24 --output "$TEMP" "$TEMP"/*.class
cp "$TEMP/classes.dex" "$DIR/trusttest.dex"
(cd "$DIR" && "${SHA[@]}" trusttest.dex > trusttest.dex.sha256)
echo "Built $DIR/trusttest.dex"
