cask "quotlet" do
  version "0.7.0"
  sha256 "0d7269141298aee8a1e6a6c07c75d159757880b979dd4023d1fd3c4077f1527e"

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
