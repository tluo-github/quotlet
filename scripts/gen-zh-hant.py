#!/usr/bin/env python3
"""从 Mac / iOS / Android 源码里的简体中文文案，生成繁体中文（台湾用语）对照表。

App 选繁体时，L() 拿简体文案按这张表转换（最长词优先，查不到的按单字转换）；
官网 site/main.js 的繁体文案（'zh-Hant'）也由简体那份（zh）整块转换生成，
README.zh-TW.md 由 README.zh-CN.md 转换生成，
网页后台的繁体对照表 cloud/web/static/zh-hant.js 只收网页后台自己的文案。
新增或修改中文文案后重新跑一遍即可：

    uv run --with opencc python3 scripts/gen-zh-hant.py

转换用 OpenCC 的 s2twp（简体 → 台湾正体 + 台湾常用词），再套用下面 OVERRIDES 里的产品用语。
生成三个文件（内容相同），更新 site/main.js 里的繁体文案和 README.zh-TW.md，这些都不要手改：
    Sources/Quotlet/ZhHantData.swift
    ios/Quotlet/ZhHantData.swift
    android/app/src/main/java/com/quotlet/ZhHantData.kt
"""

import re
import sys
from pathlib import Path

import opencc

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [
    (ROOT / 'Sources', '*.swift'),
    (ROOT / 'ios' / 'Quotlet', '*.swift'),
    (ROOT / 'android' / 'app' / 'src' / 'main' / 'java', '*.kt'),
]
GENERATED = {'ZhHantData.swift', 'ZhHantData.kt', 'zh-hant.js', 'i18n.js'}
WEB_SOURCES = [(ROOT / 'cloud' / 'web' / 'static', '*.js'), (ROOT / 'cloud' / 'web' / 'static', '*.html')]
OUT_WEB = ROOT / 'cloud/web/static/zh-hant.js'
OUT_SWIFT = [ROOT / 'Sources/Quotlet/ZhHantData.swift', ROOT / 'ios/Quotlet/ZhHantData.swift']
OUT_KOTLIN = ROOT / 'android/app/src/main/java/com/quotlet/ZhHantData.kt'
SITE_JS = ROOT / 'site/main.js'
README_HANS = ROOT / 'README.zh-CN.md'
README_HANT = ROOT / 'README.zh-TW.md'
LANG_LINE = '[English](README.md) | [简体中文](README.zh-CN.md) | 繁體中文 | [日本語](README.ja.md) | [한국어](README.ko.md)'

# OpenCC 转换之前先替换的简体用语（按这个产品里的实际意思消歧义）
PRE_OVERRIDES = [
    ('同一窗口', '同一时段'),   # 额度的时间窗口，不是界面窗口（界面窗口转成「視窗」是对的）
]
API_MARK = '\uE000'  # 「接口」在这里都指 API，先换成占位符，转完再按前后文补空格

# OpenCC 转完之后再替换的产品用语（繁体 → 繁体），按台湾软件界面的习惯
OVERRIDES = [
    ('登錄', '登入'),
    ('會話', '工作階段'),
    ('吊銷', '撤銷'),
    ('設備', '裝置'),
    ('消息', '訊息'),
    ('信息', '資訊'),
    ('令牌', '權杖'),
    ('菜單欄', '選單列'),
    ('菜單', '選單'),
    ('項目', '專案'),
    ('上報', '回報'),
    ('鏈接', '連結'),
    ('數據', '資料'),
    ('質量', '品質'),
    ('默認', '預設'),
    ('緩存', '快取'),
    ('文件夾', '資料夾'),
    ('實時', '即時'),
    ('二維碼', 'QR 碼'),
    ('賬號', '帳號'),
    ('賬戶', '帳戶'),
    ('退出登入', '登出'),
    ('郵箱', '電子郵件'),
    ('獲取', '取得'),
    ('訪問', '存取'),
    ('新建', '新增'),
    # macOS 繁体中文的系统用语
    ('狀態列', '選單列'),
    ('狀態欄', '選單列'),
    ('鑰匙串', '鑰匙圈'),
    ('簽名', '簽署'),
    ('反饋', '回饋'),
    # 台湾更常用的说法
    ('通過', '透過'),
    ('臺', '台'),
    ('客戶端', '用戶端'),
    ('併發', '並行'),
    ('柱狀圖', '長條圖'),
    ('安裝包', '安裝檔'),
    ('下載包', '下載檔'),
    ('MIT 協議', 'MIT 授權'),
    ('日誌只讀', '日誌唯讀'),
    ('周', '週'),            # 这个产品里的「周」都是星期
    ('退出', '結束'),        # 退出程序；「退出登录」已在前面换成「登出」
    ('選單欄', '選單列'),
    ('倉庫', '儲存庫'),
    ('許可證', '授權條款'),
    ('套餐', '方案'),
    ('倒計時', '倒數計時'),
    ('許可權', '權限'),
]

HAN = r'㐀-䶿一-鿿豈-﫿'
STRING_RE = re.compile(r'"(?:[^"\\\n]|\\.)*"')
RUN_RE = re.compile(f'[{HAN}]+')
# 日文假名、韩文：含这些字符的字符串不是简体文案，跳过（避免把日文汉字收进表里）
KANA_HANGUL_RE = re.compile(r'[぀-ヿ가-힯]')


def make_converter():
    for name in ('s2twp', 's2twp.json'):
        try:
            return opencc.OpenCC(name)
        except Exception:
            continue
    sys.exit('无法加载 OpenCC s2twp 配置')


def collect_runs(sources=SOURCES, whole_file=False) -> set[str]:
    """whole_file=True：整个文件里的中文都收（网页 JS 用单引号、反引号写字符串，按双引号提取会漏）"""
    runs: set[str] = set()
    for base, pattern in sources:
        for path in sorted(base.rglob(pattern)):
            if path.name in GENERATED or '/build/' in str(path):
                continue
            text = path.read_text(encoding='utf-8')
            if whole_file:
                # 同一行里常有 L('简体', 'English', '日本語', '한국어')：只去掉含假名、韩文的字符串，简体留下
                any_lit = re.compile(r"(['\"`])(?:\\.|(?!\1).)*\1")
                for line in text.split('\n'):
                    line = any_lit.sub(lambda m: '' if KANA_HANGUL_RE.search(m.group(0)) else m.group(0), line)
                    runs.update(RUN_RE.findall(line))
                continue
            for lit in STRING_RE.findall(text):
                if KANA_HANGUL_RE.search(lit):
                    continue
                runs.update(RUN_RE.findall(lit))
    return runs


def convert(cc, text: str) -> str:
    for a, b in PRE_OVERRIDES:
        text = text.replace(a, b)
    text = text.replace('接口', API_MARK)
    out = cc.convert(text)
    for a, b in OVERRIDES:
        out = out.replace(a, b)
    # API 和中文之间留一个空格；挨着标点、空格或字符串边界时不加
    out = re.sub(f' ?{API_MARK} ?', ' API ', out)
    out = re.sub(r'(^|[\s（「『，。、：；！？("\'])\s*API', r'\1API', out)
    out = re.sub(r'API\s*($|[\s」』），。、：；！？)"\'])', r'API\1', out)
    return out


def update_site(cc):
    """把 site/main.js 里简体文案块（zh）转成繁体块（'zh-Hant'），已有就整块替换"""
    js = SITE_JS.read_text(encoding='utf-8')

    def hant_block(m: re.Match) -> str:
        body = convert(cc, m.group(2)).replace('“', '「').replace('”', '」')
        head = m.group(1).replace('zh:', "'zh-Hant':")
        return head + body + m.group(3)

    # 文案表：「  zh: {」到对应的「  },」
    dict_re = re.compile(r"(\n  zh: \{\n)(.*?)(\n  \},\n)", re.S)
    m = dict_re.search(js)
    if not m:
        sys.exit('site/main.js 里找不到 zh 文案块')
    new_block = hant_block(m)[1:]  # 去掉开头换行
    old_re = re.compile(r"  'zh-Hant': \{\n.*?\n  \},\n", re.S)
    if old_re.search(js):
        js = old_re.sub(lambda _: new_block, js, count=1)
    else:
        js = js[:m.end()] + new_block + js[m.end():]

    # 预览区的一行小文案：「  zh: [...],」
    line_re = re.compile(r"\n  zh: (\[.*?\]),\n")
    lm = line_re.search(js)
    if lm:
        hant_line = f"  'zh-Hant': {convert(cc, lm.group(1))},\n"
        old_line = re.compile(r"  'zh-Hant': \[.*?\],\n")
        if old_line.search(js):
            js = old_line.sub(lambda _: hant_line, js, count=1)
        else:
            js = js[:lm.end()] + hant_line + js[lm.end():]
    SITE_JS.write_text(js, encoding='utf-8')


def update_readme(cc):
    """README.zh-CN.md → README.zh-TW.md：整篇转换，截图换成繁体界面，语言切换行单独写"""
    lines = []
    for line in README_HANS.read_text(encoding='utf-8').split('\n'):
        if line.startswith('[English](README.md)'):
            lines.append(LANG_LINE)
            continue
        out = convert(cc, line).replace('“', '「').replace('”', '」')
        out = re.sub(r'(docs/[a-z-]+?)-zh(-dark)?\.png', r'\1-zh-Hant\2.png', out)
        lines.append(out)
    header = '<!-- 自动生成，不要手改：改 README.zh-CN.md 后运行 uv run --with opencc python3 scripts/gen-zh-hant.py -->\n'
    README_HANT.write_text(header + '\n'.join(lines), encoding='utf-8')


def build_table(cc, runs: set[str]) -> list[str]:
    """单字 + 整段的对照，按长度排序，每行「简体\t繁体」"""
    chars = {ch for r in runs for ch in r}
    table: dict[str, str] = {}
    # 单字：词表里查不到时按字转换
    for ch in sorted(chars):
        t = convert(cc, ch)
        if t != ch and len(t) == 1:
            table[ch] = t
    # 整段：带上下文的词级转换（例如 设置→設定、网络→網路、内存→記憶體）
    for r in sorted(runs):
        if len(r) < 2:
            continue
        t = convert(cc, r)
        if t != r:
            table[r] = t
    return [f'{k}\t{v}' for k, v in sorted(table.items(), key=lambda kv: (len(kv[0]), kv[0]))]


def write_web(cc):
    """网页后台用的对照表（只含网页后台的文案）"""
    lines = build_table(cc, collect_runs(WEB_SOURCES, whole_file=True))
    blob = '\n'.join(lines)
    assert '`' not in blob and '${' not in blob and '\\' not in blob
    OUT_WEB.write_text(
        "'use strict'\n"
        '// 自动生成，不要手改：uv run --with opencc python3 scripts/gen-zh-hant.py\n'
        f'// 网页后台的简体 → 繁体（台湾）对照表，共 {len(lines)} 条，preferences.js 的 hant() 使用。\n'
        f'const ZH_HANT_PAIRS = `{blob}`\n',
        encoding='utf-8',
    )
    return len(lines)


def main():
    cc = make_converter()
    runs = collect_runs()
    lines = build_table(cc, runs)
    blob = '\n'.join(lines)
    assert '"""' not in blob and '$' not in blob and '\\' not in blob

    header = '// 自动生成，不要手改：uv run --with opencc python3 scripts/gen-zh-hant.py\n'
    header += f'// 简体 → 繁体（台湾）对照表，共 {len(lines)} 条，每行「简体\\t繁体」。\n\n'
    swift = header + 'enum ZhHantData {\n    static let pairs = #"""\n' + blob + '\n"""#\n}\n'
    for p in OUT_SWIFT:
        p.write_text(swift, encoding='utf-8')
    # JVM 单个字符串常量不能超过 64KB（UTF-8），分段写
    chunks = ['\n'.join(lines[i:i + 500]) for i in range(0, len(lines), 500)]
    body = ',\n'.join(f'        """\n{c}\n"""' for c in chunks)
    kotlin = header + 'package com.quotlet\n\ninternal object ZhHantData {\n    val PARTS = listOf(\n' + body + ',\n    )\n}\n'
    OUT_KOTLIN.write_text(kotlin, encoding='utf-8')
    update_site(cc)
    update_readme(cc)
    web_count = write_web(cc)
    print(f'{len(runs)} 段中文，{len(lines)} 条对照，已写入 {len(OUT_SWIFT) + 1} 个文件，网页后台 {web_count} 条，并更新 site/main.js 和 README.zh-TW.md')


if __name__ == '__main__':
    main()
