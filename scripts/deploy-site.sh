#!/bin/bash
# 门户网站：把 site/ 和 docs/ 里的截图打包到 build/site，再发布成只放静态文件的 Worker（site/wrangler.jsonc，quotlet.com）。
#   scripts/deploy-site.sh          只打包（本地预览：python3 -m http.server -d build/site 8000）
#   scripts/deploy-site.sh deploy   打包并发布
# 需要 cwebp（brew install webp）；发布用 cloud/ 里装好的 wrangler。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/site
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
# 下载按钮直接指向最新发布的 DMG（改名前的版本叫 Quotabar-x.dmg，之后叫 Quotlet-x.dmg）；查不到就退回 Releases 页面
DMG=$(gh release view --repo tluo-github/quotlet --json assets --jq '.assets[] | select(.name | endswith(".dmg")) | .url' 2>/dev/null | head -1 || true)
DMG=${DMG:-https://github.com/tluo-github/quotlet/releases/latest}
RELEASE=$(gh release view --repo tluo-github/quotlet --json tagName --jq .tagName 2>/dev/null | sed 's/^v//' || true)
VERSION=${RELEASE:-$VERSION}

rm -rf "$OUT"
mkdir -p "$OUT/assets"
cp site/style.css site/main.js site/404.html "$OUT/"
# 版本号和下载链接：下载按钮直接下最新版 DMG
sed -e "s|{{VERSION}}|${VERSION}|g" \
    -e "s|data-download href=\"https://github.com/tluo-github/quotlet/releases/latest\"|data-download href=\"${DMG}\"|g" \
    site/index.html > "$OUT/index.html"
cp docs/icon.png "$OUT/assets/icon.png"
cp Sources/Quotlet/ProviderAssets/*.png "$OUT/assets/"

for lang in en zh ja ko; do
  for page in usage settings panel; do
    cwebp -quiet -q 82 -resize 720 0 "docs/${page}-${lang}.png" -o "$OUT/assets/${page}-${lang}.webp"
  done
  cwebp -quiet -q 82 -resize 1440 0 "docs/history-${lang}.png" -o "$OUT/assets/history-${lang}.webp"
done

du -sh "$OUT"
if [[ "${1:-}" == "deploy" ]]; then
  cloud/node_modules/.bin/wrangler deploy --config site/wrangler.jsonc
fi
