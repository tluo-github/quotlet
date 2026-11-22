cask "quotlet" do
  arch arm: "arm64", intel: "x86_64"

  version "0.9.1"
  sha256 arm:   "97a825cbafd5b755aa2cff02f936a632fd51a730a6d25659942f13af21427713",
         intel: "34a2ec74836ff33b96e39c0d6d13fae5d68daab07059335005f42f7871ffc86d"

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
