#!/bin/bash
# 重新生成 README 用的截图和演示视频（四种语言），全部离线渲染，不动鼠标、不录屏。
#   截图：3 倍像素 1260×2010 PNG（docs/<页面>-<语言>.png）
#   视频：3 倍像素 60fps MP4（docs/demo-<语言>.mp4）+ 2 倍 GIF（docs/demo-<语言>.gif）
# 用法: scripts/make-demo.sh        需要 ffmpeg
# 界面布局改了以后，下面每种语言的点击坐标（点，面板左上为原点）可能要跟着调。
set -euo pipefail
cd "$(dirname "$0")/.."
# 正在运行的 Quotlet 和截图共用同一份设置（当前标签页等），先退出，结束后再打开
WAS_RUNNING=0; pgrep -x Quotlet >/dev/null && WAS_RUNNING=1 && pkill -x Quotlet || true
./build.sh >/dev/null
TMP=$(mktemp -d)
swiftc -O scripts/make-demo.swift -o "$TMP/make-demo" 2>/dev/null
BIN=build/Quotlet.app/Contents/MacOS/Quotlet

# 语言  用量tab x  会话tab x  统计tab x  深色按钮 x
LANGS="zh 66 108 150 345
en 72 134 190 344
ja 71 136 198 340
ko 70 110 153 347"

first=1
while read -r l tu ts tt dx; do
    off=(); [[ $first == 1 ]] || off=(-offline YES); first=0   # 第一种语言取一次最新额度，其余用缓存保证数字一致
    "$BIN" --snapshot "$TMP/$l" -stage YES -demo YES -language "$l" -scale 3 ${off[@]+"${off[@]}"}
    "$BIN" --snapshot "$TMP/$l-dark" -stage YES -demo YES -offline YES -language "$l" -appearance dark -scale 3
    for p in usage sessions stats settings; do cp "$TMP/$l/$p-light.png" "docs/$p-$l.png"; done
    "$TMP/make-demo" "$TMP/$l" "$TMP/$l-dark" "$tu" "$ts" "$tt" "$dx" \
      | tee >(ffmpeg -v error -y -f rawvideo -pix_fmt rgba -s 1260x2010 -r 60 -i - \
                -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -profile:v high -movflags +faststart "docs/demo-$l.mp4") \
      | ffmpeg -v error -y -f rawvideo -pix_fmt rgba -s 1260x2010 -r 60 -i - \
          -vf "fps=25,scale=840:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
          "docs/demo-$l.gif"
    echo "done: $l"
done <<< "$LANGS"
rm -rf "$TMP"
[[ $WAS_RUNNING == 1 ]] && open -a Quotlet || true
