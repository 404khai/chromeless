#!/bin/zsh
# Build Chromeless.app for a target arch and zip it for GitHub Releases.
# Usage: ./scripts/package-release.sh arm64|x86_64
set -euo pipefail
cd "${0:a:h}/.."

arch="${1:?usage: package-release.sh arm64|x86_64}"
case "$arch" in
  arm64|aarch64) target=arm64 ;;
  x86_64|intel)  target=x86_64 ;;
  *) echo "package-release.sh: unknown arch $arch" >&2; exit 1 ;;
esac

version="$(tr -d '[:space:]' < VERSION)"
export ARCH="$target"

rm -rf Chromeless.app
./build.sh

mkdir -p dist
zip="dist/Chromeless-v${version}-macos-${target}.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent Chromeless.app "$zip"

echo "▸ packaged $zip"
shasum -a 256 "$zip"
