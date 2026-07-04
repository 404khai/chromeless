cask "chromeless" do
  version "1.0.0"

  on_arm do
    sha256 "b4a67b16639dfe08e9e3dc98192107188b62fb6b58b9c46f869fc8f1010536e8"

    url "https://github.com/antiwork/chromeless/releases/download/v#{version}/Chromeless-v#{version}-macos-arm64.zip"
  end
  on_intel do
    sha256 "ed2cebfeeb70043a6548ba48c7ccfe33ad777f5ba06bb2c11da432451d9216cf"

    url "https://github.com/antiwork/chromeless/releases/download/v#{version}/Chromeless-v#{version}-macos-x86_64.zip"
  end

  name "Chromeless"
  desc "Zero-chrome browser for clean screenshots and fullscreen video"
  homepage "https://github.com/antiwork/chromeless"

  depends_on macos: :ventura

  app "Chromeless.app"

  zap trash: "~/Library/WebKit/com.chromeless.app"
end
