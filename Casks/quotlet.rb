cask "quotlet" do
  version "0.4.1"
  sha256 "c6107235676a7343f0adbcaac917a9717c05f3f8b77d92fbdf191dabe5681717"

  # 0.4.1 及之前发布时还叫 Quotabar，文件名和 app 名沿用旧名；0.5.0 起改成 Quotlet-#{version}.zip 和 Quotlet.app
  url "https://github.com/tluo-github/quotlet/releases/download/v#{version}/Quotabar-#{version}.zip"
  name "Quotlet"
  desc "Claude plan usage limits in the menu bar"
  homepage "https://quotlet.com"

  depends_on macos: ">= :sonoma"

  app "Quotabar.app"

  uninstall quit: "app.quotabar"

  zap trash: [
    "~/Library/Caches/app.quotabar",
    "~/Library/Preferences/app.quotabar.plist",
  ]
end
