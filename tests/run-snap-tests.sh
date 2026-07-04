#!/bin/zsh
# Snapshot regression tests for Chromeless CLI mode.
# Run locally after ./build.sh, or via GitHub Actions (macos-latest).
set -euo pipefail
cd "${0:a:h}/.."
ROOT="$PWD"
BIN="$ROOT/Chromeless.app/Contents/MacOS/Chromeless"
FIXTURES="$ROOT/tests/fixtures"
GOLDEN="$ROOT/tests/golden"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok()   { echo "✓ $1"; pass=$((pass + 1)) }
bad()  { echo "✗ $1"; fail=$((fail + 1)) }

png_dims() {
  local w h
  w=$(sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ { print $2 }')
  h=$(sips -g pixelHeight "$1" 2>/dev/null | awk '/pixelHeight/ { print $2 }')
  echo "$w $h"
}

# Accept logical WxH at 1x or 2x Retina scale.
assert_logical_dims() {
  local file="$1" lw="$2" lh="$3" desc="$4"
  local w2=$((lw * 2)) h2=$((lh * 2))
  read -r w h <<< "$(png_dims "$file")"
  if { [[ "$w" == "$lw" && "$h" == "$lh" ]] || [[ "$w" == "$w2" && "$h" == "$h2" ]]; }; then
    ok "$desc (${w}x${h} px)"
  else
    bad "$desc (${w}x${h} px, expected ${lw}x${lh} or ${w2}x${h2})"
  fi
}

assert_exit() {
  local desc="$1" expected="$2"
  shift 2
  set +e
  "$@" > "$TMP/stdout.txt" 2> "$TMP/stderr.txt"
  local code=$?
  set -e
  if [[ $code -eq $expected ]]; then
    ok "$desc (exit $code)"
  else
    bad "$desc (exit $code, expected $expected)"
    cat "$TMP/stderr.txt" >&2
  fi
}

assert_golden_sha256() {
  local file="$1" hash_file="$2" desc="$3"
  local expected actual
  expected=$(tr -d '[:space:]' < "$hash_file")
  actual=$(shasum -a 256 "$file" | awk '{print $1}')
  if [[ "$actual" == "$expected" ]]; then
    ok "$desc"
  else
    bad "$desc (sha256 mismatch — run ./tests/update-golden.sh to refresh)"
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
  fi
}

echo "▸ building"
./build.sh

echo "▸ running snapshot tests"
echo

# 1. Help
assert_exit "--help exits 0" 0 "$BIN" --help

# 2. Static fixture — golden snapshot
STATIC="$TMP/static.png"
assert_exit "static fixture snap exits 0" 0 \
  "$BIN" "file://$FIXTURES/static.html" --snap "$STATIC" --size 400x300 --wait 0.25
assert_logical_dims "$STATIC" 400 300 "static fixture dimensions"
assert_golden_sha256 "$STATIC" "$GOLDEN/static-400x300.sha256" "static fixture golden sha256"

# 3. example.com — network snap
EXAMPLE="$TMP/example.png"
assert_exit "example.com snap exits 0" 0 \
  "$BIN" https://example.com --snap "$EXAMPLE" --size 800x600 --wait 1
assert_logical_dims "$EXAMPLE" 800 600 "example.com dimensions"

# 4. Chart fixture — short wait captures loading state (smaller file)
CHART_EARLY="$TMP/chart-early.png"
CHART_LATE="$TMP/chart-late.png"
assert_exit "chart fixture early snap exits 0" 0 \
  "$BIN" "file://$FIXTURES/chart.html" --snap "$CHART_EARLY" --size 400x300 --wait 0.5
assert_exit "chart fixture late snap exits 0" 0 \
  "$BIN" "file://$FIXTURES/chart.html" --snap "$CHART_LATE" --size 400x300 --wait 3
early_size=$(stat -f%z "$CHART_EARLY")
late_size=$(stat -f%z "$CHART_LATE")
if [[ $late_size -gt $early_size ]]; then
  ok "chart fixture late snap larger than early (${early_size}B → ${late_size}B)"
else
  bad "chart fixture late snap larger than early (${early_size}B → ${late_size}B)"
fi

echo
echo "▸ results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
