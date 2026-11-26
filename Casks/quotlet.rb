cask "quotlet" do
  arch arm: "arm64", intel: "x86_64"

  version "0.9.2"
  sha256 arm:   "12d30c444a707ce70546a90a84ec10510565949fc90c5a8dd4f827177ab51568",
         intel: "fb3345c0abdf71f61c4beb33005235249fd634f606fa3dc72dfe17b3aba60ad6"

  url "https://github.com/tluo-github/quotlet/releases/download/v#{version}/Quotlet-#{version}-#{arch}.zip"
  name "Quotlet"
  desc "Claude, Codex, and Gemini usage limits and live tok/s in the menu bar"
  homepage "https://quotlet.com"

  depends_on macos: :ventura

  app "Quotlet.app"

  uninstall quit: "app.quotabar"

  zap trash: [
    "~/Library/Application Support/Quotlet",
    "~/Library/Caches/app.quotabar",
    "~/Library/Preferences/app.quotabar.plist",
  ]
end
