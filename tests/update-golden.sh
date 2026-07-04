#!/bin/zsh
# Regenerate golden snapshot hashes after intentional rendering changes.
set -euo pipefail
cd "${0:a:h}/.."
ROOT="$PWD"
BIN="$ROOT/Chromeless.app/Contents/MacOS/Chromeless"
FIXTURES="$ROOT/tests/fixtures"
GOLDEN="$ROOT/tests/golden"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/static-golden.png"

./build.sh
"$BIN" "file://$FIXTURES/static.html" --snap "$OUT" --size 400x300 --wait 0.25
shasum -a 256 "$OUT" | awk '{print $1}' > "$GOLDEN/static-400x300.sha256"
echo "updated $GOLDEN/static-400x300.sha256"
shasum -a 256 "$OUT"
