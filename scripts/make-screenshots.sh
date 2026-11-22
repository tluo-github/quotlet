#!/bin/bash
# 重新生成 README 和门户网站用的截图（五种语言），用 -demo YES 把会话标题和项目名换成示例文字。
#   docs/usage-<语言>.png     面板（带展示背景和仿状态栏，3 倍像素）
#   docs/settings-<语言>.png  设置页
#   docs/panel-<语言>.png     深色面板，不带背景（门户首屏）
#   docs/sessions-<语言>.png、docs/stats-<语言>.png  面板的会话、统计页（门户首屏切换）
# 同时输出 panel-<语言>-light.png 和其余页面的 <页面>-<语言>-dark.png，供门户跟随主题。
#   docs/history-<语言>.png   用量历史窗口（含原生工具栏）
# 用法: scripts/make-screenshots.sh [--panels-only]
# --panels-only：只更新面板和设置，用缓存额度。
# 环境变量：LANGS="zh-Hant" 只生成指定语言；OFFLINE=1 全部用缓存额度（不调接口）。
# 所有页面均在屏幕外渲染，无需「屏幕录制」权限。
set -euo pipefail
cd "$(dirname "$0")/.."
PANELS_ONLY=false
if [[ "${1:-}" == "--panels-only" ]]; then PANELS_ONLY=true; fi
./build.sh >/dev/null
BIN=build/Quotlet.app/Contents/MacOS/Quotlet
TMP=$(mktemp -d)

first=1
for l in ${LANGS:-zh zh-Hant en ja ko}; do
    off=(); [[ $first == 1 && $PANELS_ONLY == false && -z "${OFFLINE:-}" ]] || off=(-offline YES); first=0
    "$BIN" --snapshot "$TMP/$l" -stage YES -demo YES -language "$l" -appearance light -scale 3 -snapshotHistoryHeight 820 ${off[@]+"${off[@]}"}
    cp "$TMP/$l/usage-light.png" "docs/usage-$l.png"
    cp "$TMP/$l/settings-light.png" "docs/settings-$l.png"
    cp "$TMP/$l/usage-dark.png" "docs/usage-$l-dark.png"
    cp "$TMP/$l/settings-dark.png" "docs/settings-$l-dark.png"
    "$BIN" --snapshot "$TMP/$l-panel" -snapshotPanelTab usage -demo YES -offline YES -language "$l" -appearance dark -scale 3
    cp "$TMP/$l-panel/usage-dark.png" "docs/panel-$l.png"
    cp "$TMP/$l-panel/usage-light.png" "docs/panel-$l-light.png"
    # 门户首屏可切换的另外两页：会话、统计（浅色 <页面>-<语言>.png，深色 <页面>-<语言>-dark.png）
    for tab in sessions stats; do
        "$BIN" --snapshot "$TMP/$l-$tab" -snapshotPanelTab "$tab" -demo YES -offline YES -language "$l" -appearance dark -scale 3
        cp "$TMP/$l-$tab/$tab-light.png" "docs/$tab-$l.png"
        cp "$TMP/$l-$tab/$tab-dark.png" "docs/$tab-$l-dark.png"
    done

    if [[ $PANELS_ONLY == false ]]; then
        cp "$TMP/$l/history-light.png" "docs/history-$l.png"
        cp "$TMP/$l/history-dark.png" "docs/history-$l-dark.png"
    fi
    echo "done: $l"
done
rm -rf "$TMP"
