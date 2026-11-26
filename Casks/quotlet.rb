cask "quotlet" do
  arch arm: "arm64", intel: "x86_64"

  version "0.9.3"
  sha256 arm:   "4037c8b7ede7ec5ec130ab60b612cffb652523e465a170e120bcdb21223735a8",
         intel: "465c3d0eadc625558d05eb9060bea4edad30a0530ae40896815bbcb7eae79b87"

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
