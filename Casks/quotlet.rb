cask "quotlet" do
  version "0.7.1"
  sha256 "349c5b9b57bc95e70892f9ece54469b22297bf2843c6d3573b2b0a819d5fc243"

  url "https://github.com/tluo-github/quotlet/releases/download/v#{version}/Quotlet-#{version}.zip"
  name "Quotlet"
  desc "Claude, Codex, and Gemini usage limits and live tok/s in the menu bar"
  homepage "https://quotlet.com"

  depends_on macos: :sonoma

  app "Quotlet.app"

  uninstall quit: "app.quotabar"

  zap trash: [
    "~/Library/Application Support/Quotlet",
    "~/Library/Caches/app.quotabar",
    "~/Library/Preferences/app.quotabar.plist",
  ]
end
