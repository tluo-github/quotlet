cask "quotlet" do
  arch arm: "arm64", intel: "x86_64"

  version "0.8.0"
  sha256 arm:   "71c772bbfa92b0375e2a3e68d9f105c7f1cb22b2422d69f2470ffb8ee165e63c",
         intel: "a9098b6cbfcc37f4b8456cb203f5467478e0cd2b9bb7af843d59f0f4fff6ebb3"

  url "https://github.com/tluo-github/quotlet/releases/download/v#{version}/Quotlet-#{version}-#{arch}.zip"
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
