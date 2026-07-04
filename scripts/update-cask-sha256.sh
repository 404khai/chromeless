#!/bin/zsh
# Refresh sha256 lines in Casks/chromeless.rb from dist/*.zip artifacts.
set -euo pipefail
cd "${0:a:h}/.."

version="$(tr -d '[:space:]' < VERSION)"
cask="Casks/chromeless.rb"
arm64_zip="dist/Chromeless-v${version}-macos-arm64.zip"
x86_zip="dist/Chromeless-v${version}-macos-x86_64.zip"

[[ -f "$arm64_zip" && -f "$x86_zip" ]] || {
  echo "run ./scripts/package-release.sh for both arm64 and x86_64 first" >&2
  exit 1
}

arm64_sha="$(shasum -a 256 "$arm64_zip" | awk '{print $1}')"
x86_sha="$(shasum -a 256 "$x86_zip" | awk '{print $1}')"

ruby - "$cask" "$version" "$arm64_sha" "$x86_sha" <<'RUBY'
path, version, arm64_sha, x86_sha = ARGV
text = File.read(path)
text.sub!(/version "[^"]+"/, %(version "#{version}"))
text.sub!(/(on_arm do\n    sha256 ")[^"]+(")/, "\\1#{arm64_sha}\\2")
text.sub!(/(on_intel do\n    sha256 ")[^"]+(")/, "\\1#{x86_sha}\\2")
File.write(path, text)
RUBY

echo "▸ updated $cask"
grep -A1 'on_arm\|on_intel' "$cask"
