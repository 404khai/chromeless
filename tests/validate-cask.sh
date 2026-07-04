#!/bin/zsh
# Validate Homebrew Cask syntax and required fields.
set -euo pipefail
cd "${0:a:h}/.."

cask="Casks/chromeless.rb"
[[ -f "$cask" ]] || { echo "missing $cask" >&2; exit 1 }

echo "▸ ruby syntax"
ruby -c "$cask"

echo "▸ required fields"
ruby - "$cask" <<'RUBY'
path = ARGV[0]
text = File.read(path)
required = %w[cask version sha256 url name desc homepage app]
required.each do |field|
  abort "missing #{field}" unless text.match?(/\b#{field}\b/)
end
abort "missing on_arm" unless text.include?("on_arm")
abort "missing on_intel" unless text.include?("on_intel")
version = File.read("VERSION").strip
abort "cask version mismatch" unless text.include?(%(version "#{version}"))
puts "✓ cask looks valid for VERSION=#{version}"
RUBY

if command -v brew >/dev/null; then
  echo "▸ brew style"
  brew style "$cask"
fi

echo "✓ validate-cask passed"
