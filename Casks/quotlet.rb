cask "quotlet" do
  version "0.5.0"
  sha256 "b3a850c9276e7199462b0b7233c3997f3226d1a81182334013365881f3f6f0df"

  url "https://github.com/tluo-github/quotlet/releases/download/v#{version}/Quotlet-#{version}.zip"
  name "Quotlet"
  desc "Claude and Codex usage limits in the menu bar"
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
