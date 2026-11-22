cask "quotlet" do
  arch arm: "arm64", intel: "x86_64"

  version "0.8.1"
  sha256 arm:   "56b420d54e53360b7642b44433bbaa0776eee5197331560347dc9d1e61a5a525",
         intel: "3269e9ea92f4c05ad2098acb6c3432457e74ddd41a0ec823d240128108c12f82"

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
