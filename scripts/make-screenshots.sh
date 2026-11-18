#!/bin/bash
# 重新生成 README 和门户网站用的截图（四种语言），用 -demo YES 把会话标题和项目名换成示例文字。
#   docs/usage-<语言>.png     面板（带展示背景和仿状态栏，3 倍像素）
#   docs/settings-<语言>.png  设置页
#   docs/panel-<语言>.png     深色面板，不带背景（门户首屏）
#   docs/history-<语言>.png   用量历史窗口（真实窗口截图，含工具栏）
# 用法: scripts/make-screenshots.sh
# 截历史窗口时会短暂打开开发版窗口；需要给终端「屏幕录制」权限。
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null
BIN=build/Quotlet.app/Contents/MacOS/Quotlet
TMP=$(mktemp -d)

first=1
for l in zh en ja ko; do
    off=(); [[ $first == 1 ]] || off=(-offline YES); first=0   # 第一种语言取一次最新额度，其余用缓存保证数字一致
    "$BIN" --snapshot "$TMP/$l" -stage YES -demo YES -language "$l" -appearance light -scale 3 ${off[@]+"${off[@]}"}
    cp "$TMP/$l/usage-light.png" "docs/usage-$l.png"
    cp "$TMP/$l/settings-light.png" "docs/settings-$l.png"
    "$BIN" --snapshot "$TMP/$l-panel" -demo YES -offline YES -language "$l" -appearance dark -scale 3
    cp "$TMP/$l-panel/usage-dark.png" "docs/panel-$l.png"

    "$BIN" -openHistory YES -demo YES -offline YES -language "$l" -appearance light >/dev/null 2>&1 &
    pid=$!
    sleep 8
    wid=$(swift scripts/window-id.swift "$pid" 2>/dev/null | head -1)
    if [[ -n "$wid" ]]; then screencapture -x -o -l "$wid" "docs/history-$l.png"; else echo "没找到历史窗口（${l}）" >&2; fi
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "done: $l"
done
rm -rf "$TMP"
