#!/usr/bin/env python3
"""从 Mac / iOS / Android 源码里的简体中文文案，生成繁体中文（台湾用语）对照表。

App 选繁体时，L() 拿简体文案按这张表转换（最长词优先，查不到的按单字转换），
所以新增或修改中文文案后重新跑一遍即可：

    uv run --with opencc python3 scripts/gen-zh-hant.py

转换用 OpenCC 的 s2twp（简体 → 台湾正体 + 台湾常用词），再套用下面 OVERRIDES 里的产品用语。
生成三个文件（内容相同），不要手改：
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
GENERATED = {'ZhHantData.swift', 'ZhHantData.kt'}
OUT_SWIFT = [ROOT / 'Sources/Quotlet/ZhHantData.swift', ROOT / 'ios/Quotlet/ZhHantData.swift']
OUT_KOTLIN = ROOT / 'android/app/src/main/java/com/quotlet/ZhHantData.kt'

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


def collect_runs() -> set[str]:
    runs: set[str] = set()
    for base, pattern in SOURCES:
        for path in sorted(base.rglob(pattern)):
            if path.name in GENERATED or '/build/' in str(path):
                continue
            for lit in STRING_RE.findall(path.read_text(encoding='utf-8')):
                if KANA_HANGUL_RE.search(lit):
                    continue
                runs.update(RUN_RE.findall(lit))
    return runs


def convert(cc, text: str) -> str:
    out = cc.convert(text)
    for a, b in OVERRIDES:
        out = out.replace(a, b)
    return out


def main():
    cc = make_converter()
    runs = collect_runs()
    chars = {ch for r in runs for ch in r}
    table: dict[str, str] = {}
    # 单字：词表里查不到时按字转换
    for ch in sorted(chars):
        t = cc.convert(ch)
        if t != ch and len(t) == 1:
            table[ch] = t
    # 整段：带上下文的词级转换（例如 设置→設定、网络→網路、内存→記憶體）
    for r in sorted(runs):
        if len(r) < 2:
            continue
        t = convert(cc, r)
        if t != r:
            table[r] = t
    lines = [f'{k}\t{v}' for k, v in sorted(table.items(), key=lambda kv: (len(kv[0]), kv[0]))]
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
    print(f'{len(runs)} 段中文，{len(lines)} 条对照，已写入 {len(OUT_SWIFT) + 1} 个文件')


if __name__ == '__main__':
    main()
