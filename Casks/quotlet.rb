cask "quotlet" do
  version "0.6.1"
  sha256 "ee9b3d83b2d4ccf5b85c5bca74545839d85a87ce613ff28cafc8645db6bf0d68"

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
