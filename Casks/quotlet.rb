cask "quotlet" do
  arch arm: "arm64", intel: "x86_64"

  version "0.9.0"
  sha256 arm:   "8d7bf1e7b65415de5e6feedfb9b6ba10f1ff355dcb3764867267548faee9cd94",
         intel: "3f8eba091ef752ba75087eabaae4bc6a500bf46b85c385531340dd53872ffd68"

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
