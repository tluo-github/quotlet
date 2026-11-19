cask "quotlet" do
  version "0.6.0"
  sha256 "c0426140faf2849919568eae3e9695cf4181c7428febebaec2be1f6bbb8f8cc2"

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
