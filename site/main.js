// 门户网站：语言切换 + 复制命令。文案都在这里，HTML 里的英文是默认值（也给搜索引擎看）。
'use strict'

const T = {
  en: {
    'meta.title': 'Quotlet — Claude, Codex and Gemini quotas in your menu bar',
    'nav.how': 'How it works', 'nav.features': 'Features', 'nav.cloud': 'Cloud', 'nav.trust': 'Privacy', 'nav.source': 'Source',
    'nav.language': 'Language', 'nav.download': 'Download',
    'cta.copy': 'Copy', 'cta.copied': 'Copied', 'cta.dmg': 'Download .dmg',
    'cta.dmg.arm64': 'Download Apple Silicon', 'cta.dmg.intel': 'Download Intel',
    'install.dmg.arm64': 'Apple Silicon (.dmg)', 'install.dmg.intel': 'Intel (.dmg)',
    'hero.label': 'macOS menu bar · free & open source',
    'hero.title': 'How much quota is left? <em>See it at a glance.</em>',
    'hero.lead': "Quotlet keeps Claude, Codex and Gemini quotas, live tok/s and reset times in your Mac menu bar. When one is about to run out, it warns you early and points you to the one with room to spare.",
    'stat.providers': 'providers in one view', 'stat.refresh': 'local refresh', 'stat.langs': 'languages', 'stat.license': 'open source',
    'hero.meta': 'macOS 13+ · Apple silicon & Intel · signed & notarized',
    'highlight.speed': 'Live throughput & local updates',
    'highlight.pace': "Combined tok/s chart across all local AI, plus local Claude quota estimates between API refreshes.",
    'highlight.project': 'Usage by project', 'highlight.trend': "Compare Claude Code, Codex and Gemini tokens by project, session, model and date.",
    'highlight.local': 'Local by default', 'highlight.sync': 'Codex and Gemini read only from your Mac. Claude quota API and Cloud sync stay off until you enable them.',
    'how.label': 'How it works',
    'how.title': "Local updates between quota refreshes.",
    'how.lead': "Quotlet watches Claude Code, Codex and Antigravity (Gemini) logs on your Mac. Codex quotas come from local logs, Gemini quotas from Antigravity's local service, and optional Claude API readings refresh every 10 minutes with local estimates in between.",
    'how.p1.t': "Local logs & services update fast.", 'how.p1.d': "New session records update tokens, speed and quotas in about a second. Codex reads local logs; Gemini queries Antigravity's local service on 127.0.0.1 and caches the last reading.",
    'how.p2.t': "Claude estimates fill the gaps.", 'how.p2.d': "After at least two valid readings in the same window, new local Claude tokens estimate quota usage with a ≈ mark, corrected on the next API refresh. Models, caching and other devices affect accuracy.",
    'how.p3.t': "Alerts cover all three providers.", 'how.p3.d': "Alerts default to on at 90%, at 100% and after reset across Claude, Codex and Gemini — including Claude estimates. Allow macOS notifications when prompted.",
    'term.resets': 'Resets', 'term.today': 'today 10:30', 'term.sunday': 'Sunday 3:00',
    'term.empty': "≈ Estimated from new local tokens", 'term.bythen': "Claude API refresh · every 10 minutes by default",
    'features.label': 'What it does',
    'features.title': "Throughput, quotas, sessions and stats in one panel.",
    'f1.k': 'Menu bar', 'f1.t': 'Always in sight', 'f1.d': 'Pick Claude, Codex or Gemini for the menu bar: "5h 41% · Wk 62%" or compact "41% 62%". Switch sources right from the panel.',
    'f2.k': 'Limits', 'f2.t': 'Claude, Codex and Gemini, side by side', 'f2.d': "View 5-hour, weekly and model-specific limits for all three providers in one place. When one nears its limit, a banner suggests switching to another with headroom.",
    'f3.k': 'Throughput', 'f3.t': 'Live tok/s across all local AI', 'f3.d': "A real-time speed gauge and 1m / 2m / 5m chart combine concurrent output from Claude, Codex and Gemini, alongside today's tokens and API-equivalent cost.",
    'f4.k': 'Estimates', 'f4.t': 'Updates between refreshes', 'f4.d': "After calibration, new local tokens update Claude quota estimates in the panel and menu bar. The ≈ mark stays until the next API reading corrects the value.",
    'f5.k': 'History', 'f5.t': 'A usage history window', 'f5.d': "Use Sessions and Stats in the panel for recent activity. Open History for stacked Claude, Codex and Gemini charts, project trends, models, daily totals and CSV export. Daily totals stay on your Mac after old logs are cleared.",
    'f6.k': 'Alerts', 'f6.t': 'Notifications, five languages', 'f6.d': "90%, 100% and reset alerts default to on for Claude, Codex and Gemini, including Claude estimates. Choose 80%, 90% or 95% for the early alert. Requires macOS notification permission.",
    'shots.usage': 'Panel', 'shots.sessions': 'Sessions', 'shots.stats': 'Stats', 'shots.settings': 'Settings',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "Optional sync",
    'cloud.title': 'The menu bar stays small. The details live on the web.',
    'cloud.lead': 'Sign in on your Mac, then check everything at app.quotlet.com or in the iPhone app: limits from every Mac, which sessions are running or waiting for you, token trends, and remote commands.',
    'cloud.p1.t': 'Optional, off by default.', 'cloud.p1.d': "Local stats, Codex and Gemini work without external servers. Enabling Claude quota lookup connects to Anthropic. Browser sign-in enables optional Cloud sync.",
    'cloud.p2.t': "Choose what to sync.", 'cloud.p2.d': "Sync limits, token counts and session status. Session-title uploads have their own switch. Prompts and code stay on your Mac.",
    'cloud.p3.t': 'Stop whenever you like.', 'cloud.p3.d': 'Sign out on the Mac, or remove it from the website, and it stops sending anything.',
    'cloud.f1.t': 'Web dashboard', 'cloud.f1.d': 'Quotas for each Mac, live session status, analytics by provider, project and model, 90 days of quota history and in-page alerts. Five languages, light and dark.',
    'cloud.f2.t': 'Remote commands', 'cloud.f2.d': 'Send a prompt to Claude Code, Codex or Antigravity on your Mac from the browser or your phone. Off by default, enabled per Mac, limited to projects from the last 30 days, and every command is logged.',
    'cloud.f3.t': 'iPhone app · coming soon', 'cloud.f3.d': 'Overview, sessions, remote commands, analytics and devices in a native app, coming soon to the App Store. An Android version is in the works.',
    'shots.web-overview': 'Web dashboard', 'shots.ios-overview': 'iPhone · Overview', 'shots.ios-commands': 'iPhone · Remote commands',
    'trust.label': 'Privacy',
    'trust.title': "Don't take our word for it. Check.",
    'trust.lead': "Local logs provide token statistics. Claude quota lookup and Cloud sync are optional connections you control in Settings.",
    't1.t': "Claude quota lookup is optional", 't1.d': "Enable it in Settings to read Claude Code credentials through macOS Keychain and request quotas from Anthropic. Use the dedicated authorization button if the system requires access.",
    't2.t': "Connections you enable", 't2.d': "Local mode reads files on your Mac and queries Antigravity only on 127.0.0.1. Claude quota lookup uses api.anthropic.com. Cloud sign-in and sync use app.quotlet.com.",
    't3.t': 'Your logs stay put', 't3.d': 'Sessions and tokens are read, never written, from the logs Claude Code, Codex and Antigravity already keep on your Mac.',
    't4.t': 'Signed and notarized', 't4.d': "The official download is Developer ID signed and notarized by Apple.",
    't5.t': 'Open source', 't5.d': 'MIT licensed. Every line is on GitHub, and you can build the app yourself in one command.',
    'install.label': 'Install', 'install.title': "Install your way.",
    "install.ai.t": "Ask your AI to install it",
    "install.ai.d": "Copy the prompt into an AI assistant that can run commands on your Mac.",
    "install.ai.copy": "Copy install prompt",
    "install.ai.prompt": "Please install Quotlet on this Mac. The official website is https://quotlet.com and the source and official releases are at https://github.com/tluo-github/quotlet. Check that macOS is version 13 or later, then follow the official installation instructions using Homebrew or the signed and notarized release. Launch Quotlet after installing.",
    'install.dmg.t': 'Download', 'install.dmg.d': 'Choose Apple Silicon or Intel, open the DMG and drag Quotlet into Applications. Signed and notarized, so it opens with a double-click.',
    'install.src.t': 'Build it yourself', 'install.src.d': 'Needs the Xcode command line tools.',
    'install.r1': 'macOS 13 Ventura or later, Apple silicon or Intel',
    'install.r2': "Local Claude Code, Codex or Antigravity (Gemini) logs. Claude quota lookup also needs a Claude subscription login.",
    'install.r3': "Can't see the numbers? macOS may have tucked the icon away. Hold ⌘ and drag it where you want it.",
    'foot.disclaimer': 'Quotlet is an independent open-source project, not affiliated with Anthropic, OpenAI or Google. Claude, Codex and Gemini are trademarks of their respective owners.',
    'foot.renamed': 'Quotlet was called Quotabar before version 0.5.',
    'foot.issues': 'Issues',
    'shots.history': 'Usage history',
  },
  zh: {
    'meta.title': 'Quotlet — 在 Mac 状态栏查看 Claude、Codex 和 Gemini 额度与实时速度',
    'nav.how': '原理', 'nav.features': '功能', 'nav.cloud': '云同步', 'nav.trust': '隐私', 'nav.source': '源码',
    'nav.language': '语言', 'nav.download': '下载',
    'cta.copy': '复制', 'cta.copied': '已复制', 'cta.dmg': '下载 .dmg',
    'cta.dmg.arm64': '下载 Apple 芯片版', 'cta.dmg.intel': '下载 Intel 芯片版',
    'install.dmg.arm64': 'Apple 芯片 (.dmg)', 'install.dmg.intel': 'Intel 芯片 (.dmg)',
    'hero.label': 'macOS 状态栏 · 免费开源',
    'hero.title': '额度还剩多少，<em>一眼就知道。</em>',
    'hero.lead': "Quotlet 在 Mac 状态栏同时盯着 Claude、Codex 和 Gemini 的额度、实时速度（tok/s）和重置时间。哪家快用完了，提前提醒你，并建议换到还有余量的那家接着干。",
    'stat.providers': '家 AI 一起看', 'stat.refresh': '本机刷新', 'stat.langs': '种界面语言', 'stat.license': '开源许可',
    'hero.meta': 'macOS 13+ · Apple 芯片和 Intel · 已签名和公证',
    'highlight.speed': '实时吞吐与即时估算',
    'highlight.pace': "每秒刷新全部本机 AI 的输出速度（tok/s），并在 Claude 接口刷新间隔内按本机 token 估算额度。",
    'highlight.project': '用量花在哪些项目', 'highlight.trend': "按项目、会话、模型和日期对比 Claude Code、Codex 与 Gemini 的 token 用量。",
    'highlight.local': '默认留在本机', 'highlight.sync': 'Codex 和 Gemini 只读取本机数据；Claude 额度接口与云同步默认关闭，按需开启。',
    'how.label': '原理',
    'how.title': "接口刷新之间，本机用量继续更新。",
    'how.lead': "Quotlet 监听本机 Claude Code、Codex 和 Antigravity（Gemini）日志。Codex 额度来自本机日志，Gemini 额度来自本地 Antigravity 服务；开启 Claude 额度查询后默认每 10 分钟获取接口读数，间隔内按本机新增 token 校准估算。",
    'how.p1.t': "本机日志与本地服务即时更新。", 'how.p1.d': "客户端写入新记录后约一秒更新 token、速度与额度。Codex 直接读取本机日志；Gemini 通过本机 127.0.0.1 的 Antigravity 服务查询并本地缓存。",
    'how.p2.t': "Claude 刷新间隔内自动估算。", 'how.p2.d': "同一窗口内取得至少两次有效读数后，用新增 Claude token 推算额度并标记 ≈，下次接口刷新时自动校正。模型、缓存和其他设备用量会影响精度。",
    'how.p3.t': "三家额度统一提醒。", 'how.p3.d': "Claude、Codex 和 Gemini 默认开启 90% 快到上限、100% 已用完和重置恢复提醒，Claude 估算值也会触发。首次使用需允许 macOS 通知。",
    'term.resets': '重置', 'term.today': '今天 10:30', 'term.sunday': '本周日 03:00',
    'term.empty': "≈ 根据本机新增 token 估算", 'term.bythen': "Claude 接口默认每 10 分钟校正一次",
    'features.label': '功能',
    'features.title': "吞吐、额度、会话和统计，都在一个面板。",
    'f1.k': '状态栏', 'f1.t': '一直看得到', 'f1.d': '状态栏可自由选择显示 Claude、Codex 或 Gemini，支持「5h 41% 周 62%」或简洁「41% 62%」，在面板顶部随时切换来源。',
    'f2.k': '额度', 'f2.t': 'Claude、Codex 和 Gemini 放在一起', 'f2.d': "同屏查看三家的 5 小时、每周及细分模型额度。某一家快到上限而其他仍有余量时，顶部自动给出切换建议。",
    'f3.k': '吞吐', 'f3.t': '本机全部 AI 实时速度', 'f3.d': '面板顶部实时仪表与 1 / 2 / 5 分钟曲线汇总 Claude、Codex 和 Gemini 并发输出速度（tok/s），下方同步呈现今日用量与 API 等值费用。',
    'f4.k': "估算", 'f4.t': "刷新间隔内继续更新", 'f4.d': "校准后根据本机新增 token 推算 Claude 额度，面板和状态栏用 ≈ 标记，下一次接口读数到达后自动校正。",
    'f5.k': '历史', 'f5.t': '用量历史窗口', 'f5.d': "面板内的会话和统计页查看近期活动，历史窗口支持三家堆叠柱状图、项目趋势、模型占比、每日汇总和 CSV 导出。旧日志清理后，每日汇总保留在本机。",
    'f6.k': '提醒', 'f6.t': '通知和五种语言', 'f6.d': "Claude、Codex 和 Gemini 默认开启 90%、100% 和重置恢复提醒，Claude 估算值也参与提醒。提前提醒可选 80%、90% 或 95%，需允许 macOS 通知。",
    'shots.usage': '面板', 'shots.sessions': '会话', 'shots.stats': '统计', 'shots.settings': '设置',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "可选同步",
    'cloud.title': '状态栏保持小巧，详细的放到网页上。',
    'cloud.lead': '在 Mac 上登录后，打开 app.quotlet.com 或 iPhone App 就能看全貌：每台 Mac 的额度、哪些会话在执行或等你处理、token 趋势，还能远程下发指令。',
    'cloud.p1.t': '可选，默认关闭。', 'cloud.p1.d': "本地统计、Codex 和 Gemini 无需连接外部服务器。开启 Claude 额度查询后连接 Anthropic；通过浏览器登录后可启用可选云同步。",
    'cloud.p2.t': "选择同步内容。", 'cloud.p2.d': "同步额度、token 数量和会话状态，会话标题有单独的上传开关。提示词和代码保留在本机。",
    'cloud.p3.t': '随时可以停。', 'cloud.p3.d': '在 Mac 上退出登录，或者在网站上移除这台 Mac，它就不再上传任何东西。',
    'cloud.f1.t': '网页后台', 'cloud.f1.d': '按 Mac 查看额度和实时会话状态，按来源、项目和模型分析用量，还有最近 90 天的额度历史和网页内告警。支持五种语言和浅色、深色主题。',
    'cloud.f2.t': '远程指令', 'cloud.f2.d': '在浏览器或手机上给 Mac 上的 Claude Code、Codex 或 Antigravity 发指令。默认关闭，需在那台 Mac 上手动开启，只能在最近 30 天用过的项目里执行，每条指令都有记录。',
    'cloud.f3.t': 'iPhone App · 即将上线', 'cloud.f3.d': '概览、会话、远程指令、用量分析和设备管理都做成了原生 App，即将上架 App Store。Android 版也在开发中。',
    'shots.web-overview': '网页后台', 'shots.ios-overview': 'iPhone · 概览', 'shots.ios-commands': 'iPhone · 远程指令',
    'trust.label': '隐私',
    'trust.title': '不用信我们的话，自己查。',
    'trust.lead': "本机日志提供 token 统计。Claude 额度查询和云同步均为可选连接，可在设置中控制。",
    't1.t': "Claude 额度查询按需开启", 't1.d': "在设置中开启后，通过 macOS 钥匙串读取 Claude Code 凭证，向 Anthropic 查询额度。系统需要授权时，使用专用授权按钮允许访问。",
    't2.t': "按需开启的连接", 't2.d': "本地模式只读取 Mac 本机文件，Gemini 仅连接本机 127.0.0.1。Claude 额度查询连接 api.anthropic.com，云登录和同步连接 app.quotlet.com。",
    't3.t': '日志只读', 't3.d': '会话和 token 只从 Claude Code、Codex 和 Antigravity 本来就存在你 Mac 上的日志里读取，从来不写。',
    't4.t': '签名和公证', 't4.d': "官方下载包使用 Developer ID 签名，并经过 Apple 公证。",
    't5.t': '开源', 't5.d': 'MIT 协议，每一行代码都在 GitHub 上，一条命令就能自己编译。',
    'install.label': '安装', 'install.title': "选一种适合你的安装方式。",
    "install.ai.t": "让你的 AI 帮你安装",
    "install.ai.d": "复制这段提示词，发给能在 Mac 上执行命令的 AI 助手。",
    "install.ai.copy": "复制安装提示词",
    "install.ai.prompt": "请帮我在这台 Mac 上安装 Quotlet。官网是 https://quotlet.com，源码和官方安装包在 https://github.com/tluo-github/quotlet。先确认 macOS 为 13 或更新版本，再按官网说明使用 Homebrew 或已签名公证的正式安装包安装，完成后启动 Quotlet。",
    'install.dmg.t': '下载', 'install.dmg.d': '按芯片选择 Apple 芯片或 Intel 芯片安装包，打开 DMG 把 Quotlet 拖进“应用程序”。已签名和公证，双击就能打开。',
    'install.src.t': '自己编译', 'install.src.d': '需要 Xcode 命令行工具。',
    'install.r1': 'macOS 13 Ventura 或更新，Apple 芯片和 Intel 都支持',
    'install.r2': "本机有 Claude Code、Codex 或 Antigravity（Gemini）日志。查询 Claude 额度还需 Claude 订阅账号登录。",
    'install.r3': '状态栏上看不到数字？可能被系统收进了折叠区。按住 ⌘ 把它拖到想要的位置。',
    'foot.disclaimer': 'Quotlet 是独立的开源项目，与 Anthropic、OpenAI 和 Google 均无关联。Claude、Codex 和 Gemini 分别为各自所有者的商标。',
    'foot.renamed': 'Quotlet 在 0.5 版之前叫 Quotabar。',
    'foot.issues': '反馈问题',
    'shots.history': '用量历史',
  },
  'zh-Hant': {
    'meta.title': 'Quotlet — 在 Mac 選單列檢視 Claude、Codex 和 Gemini 額度與即時速度',
    'nav.how': '原理', 'nav.features': '功能', 'nav.cloud': '雲同步', 'nav.trust': '隱私', 'nav.source': '原始碼',
    'nav.language': '語言', 'nav.download': '下載',
    'cta.copy': '複製', 'cta.copied': '已複製', 'cta.dmg': '下載 .dmg',
    'cta.dmg.arm64': '下載 Apple 晶片版', 'cta.dmg.intel': '下載 Intel 晶片版',
    'install.dmg.arm64': 'Apple 晶片 (.dmg)', 'install.dmg.intel': 'Intel 晶片 (.dmg)',
    'hero.label': 'macOS 選單列 · 免費開源',
    'hero.title': '額度還剩多少，<em>一眼就知道。</em>',
    'hero.lead': "Quotlet 在 Mac 選單列同時盯著 Claude、Codex 和 Gemini 的額度、即時速度（tok/s）與重置時間。哪家快用完了，提前提醒你，並建議換到還有餘量的那家接著做。",
    'stat.providers': '家 AI 一起看', 'stat.refresh': '本機更新', 'stat.langs': '種介面語言', 'stat.license': '開源授權',
    'hero.meta': 'macOS 13+ · Apple 晶片和 Intel · 已簽署和公證',
    'highlight.speed': '即時吞吐與即時估算',
    'highlight.pace': "每秒重新整理全部本機 AI 的輸出速度（tok/s），並在 Claude API 重新整理間隔內按本機 token 估算額度。",
    'highlight.project': '用量花在哪些專案', 'highlight.trend': "按專案、工作階段、模型和日期對比 Claude Code、Codex 與 Gemini 的 token 用量。",
    'highlight.local': '預設留在本機', 'highlight.sync': 'Codex 和 Gemini 只讀取本機資料；Claude 額度 API 與雲同步預設關閉，按需開啟。',
    'how.label': '原理',
    'how.title': "API 重新整理之間，本機用量繼續更新。",
    'how.lead': "Quotlet 監聽本機 Claude Code、Codex 和 Antigravity（Gemini）日誌。Codex 額度來自本機日誌，Gemini 額度來自本地 Antigravity 服務；開啟 Claude 額度查詢後預設每 10 分鐘取得 API 讀數，間隔內按本機新增 token 校準估算。",
    'how.p1.t': "本機日誌與本地服務即時更新。", 'how.p1.d': "用戶端寫入新記錄後約一秒更新 token、速度與額度。Codex 直接讀取本機日誌；Gemini 透過本機 127.0.0.1 的 Antigravity 服務查詢並本地快取。",
    'how.p2.t': "Claude 重新整理間隔內自動估算。", 'how.p2.d': "同一時段內取得至少兩次有效讀數後，用新增 Claude token 推算額度並標記 ≈，下次 API 重新整理時自動校正。模型、快取和其他裝置用量會影響精度。",
    'how.p3.t': "三家額度統一提醒。", 'how.p3.d': "Claude、Codex 和 Gemini 預設開啟 90% 快到上限、100% 已用完和重置恢復提醒，Claude 估算值也會觸發。首次使用需允許 macOS 通知。",
    'term.resets': '重置', 'term.today': '今天 10:30', 'term.sunday': '本週日 03:00',
    'term.empty': "≈ 根據本機新增 token 估算", 'term.bythen': "Claude API 預設每 10 分鐘校正一次",
    'features.label': '功能',
    'features.title': "吞吐、額度、工作階段和統計，都在一個面板。",
    'f1.k': '選單列', 'f1.t': '一直看得到', 'f1.d': '選單列可自由選擇顯示 Claude、Codex 或 Gemini，支援「5h 41% 週 62%」或簡潔「41% 62%」，在面板頂部隨時切換來源。',
    'f2.k': '額度', 'f2.t': 'Claude、Codex 和 Gemini 放在一起', 'f2.d': "同屏檢視三家的 5 小時、每週及細分模型額度。某一家快到上限而其他仍有餘量時，頂部自動給出切換建議。",
    'f3.k': '吞吐', 'f3.t': '本機全部 AI 即時速度', 'f3.d': '面板頂部即時儀表與 1 / 2 / 5 分鐘曲線彙總 Claude、Codex 和 Gemini 並行輸出速度（tok/s），下方同步呈現今日用量與 API 等值費用。',
    'f4.k': "估算", 'f4.t': "重新整理間隔內繼續更新", 'f4.d': "校準後根據本機新增 token 推算 Claude 額度，面板和選單列用 ≈ 標記，下一次 API 讀數到達後自動校正。",
    'f5.k': '歷史', 'f5.t': '用量歷史視窗', 'f5.d': "面板內的工作階段和統計頁檢視近期活動，歷史視窗支援三家堆疊長條圖、專案趨勢、模型佔比、每日彙總和 CSV 匯出。舊日誌清理後，每日彙總保留在本機。",
    'f6.k': '提醒', 'f6.t': '通知和五種語言', 'f6.d': "Claude、Codex 和 Gemini 預設開啟 90%、100% 和重置恢復提醒，Claude 估算值也參與提醒。提前提醒可選 80%、90% 或 95%，需允許 macOS 通知。",
    'shots.usage': '面板', 'shots.sessions': '工作階段', 'shots.stats': '統計', 'shots.settings': '設定',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "可選同步",
    'cloud.title': '選單列保持小巧，詳細的放到網頁上。',
    'cloud.lead': '在 Mac 上登入後，開啟 app.quotlet.com 或 iPhone App 就能看全貌：每台 Mac 的額度、哪些工作階段在執行或等你處理、token 趨勢，還能遠端下發指令。',
    'cloud.p1.t': '可選，預設關閉。', 'cloud.p1.d': "本地統計、Codex 和 Gemini 無需連線外部伺服器。開啟 Claude 額度查詢後連線 Anthropic；透過瀏覽器登入後可啟用可選雲同步。",
    'cloud.p2.t': "選擇同步內容。", 'cloud.p2.d': "同步額度、token 數量和工作階段狀態，工作階段標題有單獨的上傳開關。提示詞和程式碼保留在本機。",
    'cloud.p3.t': '隨時可以停。', 'cloud.p3.d': '在 Mac 上登出，或者在網站上移除這台 Mac，它就不再上傳任何東西。',
    'cloud.f1.t': '網頁後台', 'cloud.f1.d': '按 Mac 檢視額度和即時工作階段狀態，按來源、專案和模型分析用量，還有最近 90 天的額度歷史和網頁內告警。支援五種語言和淺色、深色主題。',
    'cloud.f2.t': '遠端指令', 'cloud.f2.d': '在瀏覽器或手機上給 Mac 上的 Claude Code、Codex 或 Antigravity 發指令。預設關閉，需在那台 Mac 上手動開啟，只能在最近 30 天用過的專案裡執行，每條指令都有記錄。',
    'cloud.f3.t': 'iPhone App · 即將上線', 'cloud.f3.d': '概覽、工作階段、遠端指令、用量分析和裝置管理都做成了原生 App，即將上架 App Store。Android 版也在開發中。',
    'shots.web-overview': '網頁後台', 'shots.ios-overview': 'iPhone · 概覽', 'shots.ios-commands': 'iPhone · 遠端指令',
    'trust.label': '隱私',
    'trust.title': '不用信我們的話，自己查。',
    'trust.lead': "本機日誌提供 token 統計。Claude 額度查詢和雲同步均為可選連線，可在設定中控制。",
    't1.t': "Claude 額度查詢按需開啟", 't1.d': "在設定中開啟後，透過 macOS 鑰匙圈讀取 Claude Code 憑證，向 Anthropic 查詢額度。系統需要授權時，使用專用授權按鈕允許存取。",
    't2.t': "按需開啟的連線", 't2.d': "本地模式只讀取 Mac 本機檔案，Gemini 僅連線本機 127.0.0.1。Claude 額度查詢連線 api.anthropic.com，雲登入和同步連線 app.quotlet.com。",
    't3.t': '日誌唯讀', 't3.d': '工作階段和 token 只從 Claude Code、Codex 和 Antigravity 本來就存在你 Mac 上的日誌裡讀取，從來不寫。',
    't4.t': '簽署和公證', 't4.d': "官方下載檔使用 Developer ID 簽署，並經過 Apple 公證。",
    't5.t': '開源', 't5.d': 'MIT 授權，每一行程式碼都在 GitHub 上，一條命令就能自己編譯。',
    'install.label': '安裝', 'install.title': "選一種適合你的安裝方式。",
    "install.ai.t": "讓你的 AI 幫你安裝",
    "install.ai.d": "複製這段提示詞，發給能在 Mac 上執行命令的 AI 助手。",
    "install.ai.copy": "複製安裝提示詞",
    "install.ai.prompt": "請幫我在這台 Mac 上安裝 Quotlet。官網是 https://quotlet.com，原始碼和官方安裝檔在 https://github.com/tluo-github/quotlet。先確認 macOS 為 13 或更新版本，再按官網說明使用 Homebrew 或已簽署公證的正式安裝檔安裝，完成後啟動 Quotlet。",
    'install.dmg.t': '下載', 'install.dmg.d': '按晶片選擇 Apple 晶片或 Intel 晶片安裝檔，開啟 DMG 把 Quotlet 拖進「應用程式」。已簽署和公證，雙擊就能開啟。',
    'install.src.t': '自己編譯', 'install.src.d': '需要 Xcode 命令列工具。',
    'install.r1': 'macOS 13 Ventura 或更新，Apple 晶片和 Intel 都支援',
    'install.r2': "本機有 Claude Code、Codex 或 Antigravity（Gemini）日誌。查詢 Claude 額度還需 Claude 訂閱帳號登入。",
    'install.r3': '選單列上看不到數字？可能被系統收進了摺疊區。按住 ⌘ 把它拖到想要的位置。',
    'foot.disclaimer': 'Quotlet 是獨立的開源專案，與 Anthropic、OpenAI 和 Google 均無關聯。Claude、Codex 和 Gemini 分別為各自所有者的商標。',
    'foot.renamed': 'Quotlet 在 0.5 版之前叫 Quotabar。',
    'foot.issues': '回饋問題',
    'shots.history': '用量歷史',
  },
  ja: {
    'meta.title': 'Quotlet — Claude・Codex・Gemini の使用枠を Mac のメニューバーに',
    'nav.how': 'しくみ', 'nav.features': '機能', 'nav.cloud': 'クラウド', 'nav.trust': 'プライバシー', 'nav.source': 'ソース',
    'nav.language': '言語', 'nav.download': 'ダウンロード',
    'cta.copy': 'コピー', 'cta.copied': 'コピーしました', 'cta.dmg': '.dmg をダウンロード',
    'cta.dmg.arm64': 'Apple シリコン版をダウンロード', 'cta.dmg.intel': 'Intel 版をダウンロード',
    'install.dmg.arm64': 'Apple シリコン (.dmg)', 'install.dmg.intel': 'Intel (.dmg)',
    'hero.label': 'macOS メニューバー · 無料・オープンソース',
    'hero.title': 'あとどれだけ使える？<em>ひと目でわかる。</em>',
    'hero.lead': "Quotlet は Claude・Codex・Gemini の使用枠、リアルタイム速度（tok/s）、リセット時刻を Mac のメニューバーでまとめて見張ります。どれかが尽きそうになったら早めに知らせ、余裕のある方への切り替えを提案します。",
    'stat.providers': '社の AI を一括表示', 'stat.refresh': 'ローカル更新', 'stat.langs': '言語に対応', 'stat.license': 'オープンソース',
    'hero.meta': 'macOS 13 以降 · Apple シリコンと Intel · 署名・公証済み',
    'highlight.speed': 'リアルタイム速度とローカル更新',
    'highlight.pace': "全ローカル AI の合計 tok/s グラフを毎秒更新。Claude の API 更新間隔もローカルで推定します。",
    'highlight.project': 'プロジェクト別の使用量', 'highlight.trend': "Claude Code・Codex・Gemini のトークンをプロジェクト、セッション、モデル、日付ごとに比較できます。",
    'highlight.local': '既定はローカル完結', 'highlight.sync': 'Codex と Gemini は Mac 内だけで取得。Claude 使用枠 API とクラウド同期は有効にするまでオフです。',
    'how.label': 'しくみ',
    'how.title': "使用枠の更新間隔も、ローカルで更新。",
    'how.lead': "Mac 上の Claude Code・Codex・Antigravity（Gemini）のログを監視します。Codex はローカルログ、Gemini は Antigravity のローカルサービスから使用枠を取得。Claude 使用枠 API を有効にすると既定 10 分ごとに照会し、その間はローカルで推定します。",
    'how.p1.t': "ローカルログとサービスから即座に更新。", 'how.p1.d': "新しい記録の書き込み後、約 1 秒でトークン・速度・使用枠を更新。Codex はローカルログ、Gemini は 127.0.0.1 の Antigravity ローカルサービスから取得しキャッシュします。",
    'how.p2.t': "Claude の更新間隔も推定で補完。", 'how.p2.d': "同じ枠内で有効な値を 2 回以上取得すると、新しい Claude トークンから使用率を推定し ≈ を表示、次の API 応答で補正します。モデル、キャッシュ、ほかの端末の使用が精度に影響します。",
    'how.p3.t': "3 サービスすべてを通知。", 'how.p3.d': "Claude・Codex・Gemini の 90%、100%、リセット後の通知は既定でオン。Claude の推定値も対象です。初回は macOS の通知を許可してください。",
    'term.resets': 'リセット', 'term.today': '今日 10:30', 'term.sunday': '日曜日 3:00',
    'term.empty': "≈ 新しいローカルトークンから推定", 'term.bythen': "Claude API は既定で 10 分ごとに補正",
    'features.label': '機能',
    'features.title': "速度、使用枠、セッション、統計をひとつのパネルに。",
    'f1.k': 'メニューバー', 'f1.t': 'いつでも見える', 'f1.d': 'メニューバーに表示する提供元を Claude・Codex・Gemini から選択。「5h 41% 週 62%」とコンパクトな「41% 62%」に対応し、パネル上部からすぐ切り替えられます。',
    'f2.k': '上限', 'f2.t': 'Claude・Codex・Gemini を並べて', 'f2.d': "3 つの提供元の 5 時間・週間・モデル別の使用枠を一覧表示。いずれかが上限に近づくと、余裕のある別の提供元への切り替えを提案します。",
    'f3.k': 'スループット', 'f3.t': '全ローカル AI のリアルタイム tok/s', 'f3.d': 'リアルタイムの速度メーターと 1 / 2 / 5 分グラフで Claude・Codex・Gemini の並列出力を合算表示。今日のトークン数と API 換算金額も確認できます。',
    'f4.k': "推定", 'f4.t': "更新間隔も使用量を追跡", 'f4.d': "校正後は新しいローカルトークンから Claude 使用枠を推定します。パネルとメニューバーに ≈ を付け、次の API 応答で補正します。",
    'f5.k': '履歴', 'f5.t': '使用量の履歴ウィンドウ', 'f5.d': "パネルのセッションと統計で最近の活動を確認。履歴ウィンドウでは 3 サービス積み上げグラフ、プロジェクト推移、モデル別割合、日ごとの合計と CSV 書き出しを利用できます。古いログの削除後も日ごとの合計は Mac に残ります。",
    'f6.k': '通知', 'f6.t': '通知と 5 言語', 'f6.d': "Claude・Codex・Gemini の 90%、100%、リセット後の通知は既定でオン。Claude の推定値も対象です。早期通知は 80・90・95% から選択でき、macOS の通知許可が必要です。",
    'shots.usage': 'パネル', 'shots.sessions': 'セッション', 'shots.stats': '統計', 'shots.settings': '設定',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "任意の同期",
    'cloud.title': 'メニューバーは小さいまま。詳しくは Web で。',
    'cloud.lead': 'Mac でログインすると、app.quotlet.com や iPhone アプリで全体を確認できます。Mac ごとの使用枠、実行中や対応待ちのセッション、トークンの推移、そしてリモートコマンドまで。',
    'cloud.p1.t': '任意、初期設定はオフ。', 'cloud.p1.d': "ローカル集計・Codex・Gemini は外部サーバー不要で動作します。Claude 使用枠の取得で Anthropic に接続し、ブラウザーログインで任意のクラウド同期を利用できます。",
    'cloud.p2.t': "同期する内容を選択。", 'cloud.p2.d': "使用枠、トークン数、セッションの状態を同期します。セッション名の送信は個別に設定できます。プロンプトとコードは Mac 内に保存されます。",
    'cloud.p3.t': 'いつでもやめられる。', 'cloud.p3.d': 'Mac でログアウトするか、Web からその Mac を削除すれば、何も送らなくなります。',
    'cloud.f1.t': 'Web ダッシュボード', 'cloud.f1.d': 'Mac ごとの使用枠とセッションのリアルタイムな状態、プロバイダー・プロジェクト・モデル別の分析、直近 90 日の使用枠の履歴、ページ内アラート。5 言語とライト・ダークに対応。',
    'cloud.f2.t': 'リモートコマンド', 'cloud.f2.d': 'ブラウザやスマートフォンから Mac の Claude Code・Codex・Antigravity に指示を送れます。既定でオフ、Mac ごとに有効化。直近 30 日のプロジェクトに限定され、すべてのコマンドが記録されます。',
    'cloud.f3.t': 'iPhone アプリ · 近日公開', 'cloud.f3.d': '概要、セッション、リモートコマンド、分析、デバイス管理をネイティブアプリで。まもなく App Store で公開予定です。Android 版も開発中です。',
    'shots.web-overview': 'Web ダッシュボード', 'shots.ios-overview': 'iPhone · 概要', 'shots.ios-commands': 'iPhone · リモートコマンド',
    'trust.label': 'プライバシー',
    'trust.title': '信じなくていい。確かめてください。',
    'trust.lead': "トークン統計はローカルログから取得。Claude 使用枠の照会とクラウド同期は設定で選べます。",
    't1.t': "Claude 使用枠の照会は任意", 't1.d': "設定で有効にすると、macOS キーチェーンから Claude Code の認証情報を読み取り、Anthropic に使用枠を照会します。システムの許可が必要な場合は専用ボタンを使います。",
    't2.t': "選択して有効にする接続", 't2.d': "ローカルモードは Mac 上のファイルを読み取り、Gemini の照会も 127.0.0.1 のローカル通信のみ。Claude 使用枠は api.anthropic.com、クラウドのログインと同期は app.quotlet.com に接続します。",
    't3.t': 'ログは読むだけ', 't3.d': 'セッションとトークンは、Claude Code・Codex・Antigravity がもともと Mac に保存しているログから読み取るだけで、書き込みはしません。',
    't4.t': '署名・公証済み', 't4.d': "公式ダウンロードは Developer ID で署名され、Apple の公証を受けています。",
    't5.t': 'オープンソース', 't5.d': 'MIT ライセンス。コードはすべて GitHub にあり、コマンド 1 つで自分でビルドできます。',
    'install.label': 'インストール', 'install.title': "使いやすい方法でインストール。",
    "install.ai.t": "AI にインストールを頼む",
    "install.ai.d": "Mac でコマンドを実行できる AI アシスタントに、この指示をコピーして送ってください。",
    "install.ai.copy": "インストール指示をコピー",
    "install.ai.prompt": "この Mac に Quotlet をインストールしてください。公式サイトは https://quotlet.com、ソースと公式リリースは https://github.com/tluo-github/quotlet です。macOS 13 以降であることを確認し、公式手順に沿って Homebrew または署名・公証済みのリリースを使ってインストールし、Quotlet を起動してください。",
    'install.dmg.t': 'ダウンロード', 'install.dmg.d': 'Apple シリコン版または Intel 版を選び、DMG を開いて Quotlet をアプリケーションフォルダにドラッグ。署名・公証済みなのでダブルクリックで開けます。',
    'install.src.t': '自分でビルド', 'install.src.d': 'Xcode コマンドラインツールが必要です。',
    'install.r1': 'macOS 13 Ventura 以降、Apple シリコンまたは Intel',
    'install.r2': "Claude Code・Codex・Antigravity（Gemini）のいずれかのローカルログ。Claude 使用枠の取得には Claude サブスクリプションのログインも必要です。",
    'install.r3': '数字が見えない場合は、アイコンが隠れているかもしれません。⌘ を押しながら好きな位置にドラッグしてください。',
    'foot.disclaimer': 'Quotlet は独立したオープンソースプロジェクトであり、Anthropic・OpenAI・Google とは関係ありません。Claude・Codex・Gemini は各社の商標です。',
    'foot.renamed': 'Quotlet はバージョン 0.5 より前は Quotabar という名前でした。',
    'foot.issues': '不具合の報告',
    'shots.history': '使用量の履歴',
  },
  ko: {
    'meta.title': 'Quotlet — Claude, Codex, Gemini 한도를 Mac 메뉴 막대에서',
    'nav.how': '작동 방식', 'nav.features': '기능', 'nav.cloud': '클라우드', 'nav.trust': '개인정보', 'nav.source': '소스',
    'nav.language': '언어', 'nav.download': '다운로드',
    'cta.copy': '복사', 'cta.copied': '복사됨', 'cta.dmg': '.dmg 다운로드',
    'cta.dmg.arm64': 'Apple 실리콘 다운로드', 'cta.dmg.intel': 'Intel 칩 다운로드',
    'install.dmg.arm64': 'Apple 실리콘 (.dmg)', 'install.dmg.intel': 'Intel 칩 (.dmg)',
    'hero.label': 'macOS 메뉴 막대 · 무료 오픈 소스',
    'hero.title': '얼마나 남았을까? <em>한눈에 확인하세요.</em>',
    'hero.lead': "Quotlet은 Claude, Codex, Gemini의 한도와 실시간 속도(tok/s), 재설정 시간을 Mac 메뉴 막대에서 함께 지켜봅니다. 한쪽이 바닥나기 전에 미리 알려 주고, 여유 있는 쪽으로 전환을 제안합니다.",
    'stat.providers': '개 AI 한눈에', 'stat.refresh': '로컬 갱신', 'stat.langs': '개 언어 지원', 'stat.license': '오픈 소스',
    'hero.meta': 'macOS 13 이상 · Apple 실리콘 및 Intel · 서명 및 공증 완료',
    'highlight.speed': '실시간 속도와 로컬 갱신',
    'highlight.pace': "모든 로컬 AI의 합산 tok/s 차트를 매초 갱신하고, Claude API 새로 고침 사이에도 로컬 토큰으로 추정합니다.",
    'highlight.project': '프로젝트별 사용량', 'highlight.trend': "프로젝트, 세션, 모델, 날짜별로 Claude Code, Codex, Gemini 토큰을 비교하세요.",
    'highlight.local': '기본은 로컬 동작', 'highlight.sync': 'Codex와 Gemini는 Mac 로컬에서만 읽습니다. Claude 한도 API와 클라우드 동기화는 켜기 전까지 꺼져 있습니다.',
    'how.label': '작동 방식',
    'how.title': "한도 새로 고침 사이에도 로컬에서 갱신.",
    'how.lead': "Mac의 Claude Code, Codex, Antigravity(Gemini) 로그를 감시합니다. Codex 한도는 로컬 로그에서, Gemini 한도는 로컬 Antigravity 서비스에서 읽습니다. Claude 한도 조회를 켜면 기본 10분마다 API 값을 가져오고 그 사이에는 로컬 사용량으로 추정합니다.",
    'how.p1.t': "로컬 로그와 서비스에서 즉시 갱신.", 'how.p1.d': "새 기록이 저장되면 약 1초 만에 토큰, 속도, 한도를 갱신합니다. Codex는 로컬 로그를 읽고, Gemini는 127.0.0.1의 Antigravity 로컬 서비스에서 조회해 캐시합니다.",
    'how.p2.t': "Claude 새로 고침 사이도 추정으로 보완.", 'how.p2.d': "같은 한도 구간에서 두 번 이상 유효한 값을 얻은 뒤 새 Claude 토큰으로 사용률을 추정해 ≈를 표시하고 다음 API 응답으로 보정합니다. 모델, 캐시, 다른 기기의 사용이 정확도에 영향을 줍니다.",
    'how.p3.t': "세 서비스 모두 알림 지원.", 'how.p3.d': "Claude, Codex, Gemini의 90%, 100%, 재설정 후 알림이 기본으로 켜져 있으며 Claude 추정값도 포함됩니다. 처음에는 macOS 알림 권한을 허용하세요.",
    'term.resets': '재설정', 'term.today': '오늘 10:30', 'term.sunday': '일요일 3:00',
    'term.empty': "≈ 새 로컬 토큰으로 추정", 'term.bythen': "Claude API는 기본 10분마다 보정",
    'features.label': '기능',
    'features.title': "속도, 한도, 세션, 통계를 한 패널에서.",
    'f1.k': '메뉴 막대', 'f1.t': '항상 보이는 한도', 'f1.d': '메뉴 막대에 표시할 소스를 Claude, Codex, Gemini 중 선택하세요. "5h 41% 주 62%" 또는 간단한 "41% 62%" 형식을 지원하며 패널 상단에서 바로 전환할 수 있습니다.',
    'f2.k': '한도', 'f2.t': 'Claude, Codex, Gemini를 나란히', 'f2.d': "세 제공자의 5시간·주간·모델별 한도를 한눈에 확인하세요. 한쪽이 한도에 가까워지면 여유 있는 다른 제공자로 전환을 제안합니다.",
    'f3.k': '처리량', 'f3.t': '모든 로컬 AI의 실시간 tok/s', 'f3.d': '실시간 속도계와 1분 / 2분 / 5분 차트로 Claude, Codex, Gemini의 동시 출력을 합산해 보여 주며, 오늘의 토큰과 API 환산 비용도 함께 확인합니다.',
    'f4.k': "추정", 'f4.t': "새로 고침 사이에도 갱신", 'f4.d': "보정 후 새 로컬 토큰으로 Claude 한도를 추정합니다. 패널과 메뉴 막대에 ≈를 표시하고 다음 API 응답으로 보정합니다.",
    'f5.k': '기록', 'f5.t': '사용량 기록 창', 'f5.d': "패널의 세션과 통계에서 최근 활동을 확인하고, 기록 창에서 Claude·Codex·Gemini 누적 차트, 프로젝트 추이, 모델 비중, 일별 합계와 CSV 내보내기를 사용하세요. 오래된 로그를 지워도 일별 합계는 Mac에 보관됩니다.",
    'f6.k': '알림', 'f6.t': '알림과 5개 언어', 'f6.d': "Claude, Codex, Gemini의 90%, 100%, 재설정 알림은 기본으로 켜져 있으며 Claude 추정값도 포함됩니다. 사전 알림은 80·90·95%에서 고를 수 있고 macOS 알림 권한이 필요합니다.",
    'shots.usage': '패널', 'shots.sessions': '세션', 'shots.stats': '통계', 'shots.settings': '설정',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "선택적 동기화",
    'cloud.title': '메뉴 막대는 작게. 자세한 내용은 웹에서.',
    'cloud.lead': 'Mac에서 로그인하면 app.quotlet.com이나 iPhone 앱에서 전체를 확인할 수 있습니다. Mac별 한도, 실행 중이거나 응답을 기다리는 세션, 토큰 추이, 그리고 원격 명령까지.',
    'cloud.p1.t': '선택 사항, 기본값은 꺼짐.', 'cloud.p1.d': "로컬 통계와 Codex, Gemini는 외부 서버 없이 동작합니다. Claude 한도 조회를 켜면 Anthropic에 연결하며, 브라우저 로그인 후 선택적으로 클라우드 동기화를 켤 수 있습니다.",
    'cloud.p2.t': "동기화할 내용 선택.", 'cloud.p2.d': "한도, 토큰 수, 세션 상태를 동기화합니다. 세션 제목 업로드는 별도로 설정할 수 있습니다. 프롬프트와 코드는 Mac에 보관됩니다.",
    'cloud.p3.t': '언제든 멈출 수 있습니다.', 'cloud.p3.d': 'Mac에서 로그아웃하거나 웹에서 그 Mac을 제거하면 더 이상 아무것도 보내지 않습니다.',
    'cloud.f1.t': '웹 대시보드', 'cloud.f1.d': 'Mac별 한도와 실시간 세션 상태, 제공자·프로젝트·모델별 분석, 최근 90일 한도 기록과 페이지 내 알림. 5개 언어와 라이트·다크 테마를 지원합니다.',
    'cloud.f2.t': '원격 명령', 'cloud.f2.d': '브라우저나 휴대폰에서 Mac의 Claude Code, Codex, Antigravity에 명령을 보낼 수 있습니다. 기본적으로 꺼져 있고 Mac별로 켜며, 최근 30일 프로젝트에서만 실행되고 모든 명령이 기록됩니다.',
    'cloud.f3.t': 'iPhone 앱 · 출시 예정', 'cloud.f3.d': '개요, 세션, 원격 명령, 분석, 기기 관리를 네이티브 앱으로 제공하며 곧 App Store에 출시됩니다. Android 버전도 개발 중입니다.',
    'shots.web-overview': '웹 대시보드', 'shots.ios-overview': 'iPhone · 개요', 'shots.ios-commands': 'iPhone · 원격 명령',
    'trust.label': '개인정보',
    'trust.title': '믿지 말고 확인하세요.',
    'trust.lead': "토큰 통계는 로컬 로그에서 읽습니다. Claude 한도 조회와 클라우드 동기화는 설정에서 선택할 수 있습니다.",
    't1.t': "Claude 한도 조회는 선택 사항", 't1.d': "설정에서 켜면 macOS 키체인으로 Claude Code 자격 증명을 읽고 Anthropic에 한도를 조회합니다. 시스템 권한이 필요하면 전용 승인 버튼을 사용하세요.",
    't2.t': "직접 켜는 연결", 't2.d': "로컬 모드는 Mac의 파일만 읽으며 Gemini 조회도 127.0.0.1 로컬 통신만 사용합니다. Claude 한도 조회는 api.anthropic.com에, 클라우드 로그인과 동기화는 app.quotlet.com에 연결합니다.",
    't3.t': '로그는 읽기만', 't3.d': '세션과 토큰은 Claude Code, Codex, Antigravity가 원래 Mac에 남기는 로그에서 읽기만 하고 쓰지 않습니다.',
    't4.t': '서명 및 공증', 't4.d': "공식 다운로드는 Developer ID로 서명되고 Apple 공증을 받았습니다.",
    't5.t': '오픈 소스', 't5.d': 'MIT 라이선스. 모든 코드가 GitHub에 있으며 명령 하나로 직접 빌드할 수 있습니다.',
    'install.label': '설치', 'install.title': "편한 방법으로 설치하세요.",
    "install.ai.t": "AI에게 설치 부탁하기",
    "install.ai.d": "Mac에서 명령을 실행할 수 있는 AI 도우미에게 이 요청을 복사해 보내세요.",
    "install.ai.copy": "설치 요청 복사",
    "install.ai.prompt": "이 Mac에 Quotlet을 설치해 주세요. 공식 사이트는 https://quotlet.com, 소스와 공식 릴리스는 https://github.com/tluo-github/quotlet 입니다. macOS 13 이상인지 확인한 다음 공식 안내에 따라 Homebrew 또는 서명 및 공증된 공식 패키지로 설치하고 Quotlet을 실행해 주세요.",
    'install.dmg.t': '다운로드', 'install.dmg.d': 'Apple 실리콘 또는 Intel 버전을 선택해 DMG를 열고 Quotlet을 응용 프로그램 폴더로 드래그하세요. 서명 및 공증되어 더블 클릭으로 열립니다.',
    'install.src.t': '직접 빌드', 'install.src.d': 'Xcode 명령줄 도구가 필요합니다.',
    'install.r1': 'macOS 13 Ventura 이상, Apple 실리콘 또는 Intel',
    'install.r2': "Claude Code, Codex 또는 Antigravity(Gemini)의 로컬 로그. Claude 한도 조회에는 Claude 구독 계정 로그인도 필요합니다.",
    'install.r3': '숫자가 보이지 않나요? 아이콘이 숨겨졌을 수 있습니다. ⌘를 누른 채 원하는 위치로 드래그하세요.',
    'foot.disclaimer': 'Quotlet은 독립적인 오픈 소스 프로젝트로, Anthropic, OpenAI, Google과 관련이 없습니다. Claude, Codex, Gemini는 각 소유자의 상표입니다.',
    'foot.renamed': 'Quotlet은 0.5 버전 이전에는 Quotabar라는 이름이었습니다.',
    'foot.issues': '문제 신고',
    'shots.history': '사용량 기록',
  },
}

const HTML_LANG = { en: 'en', zh: 'zh-CN', 'zh-Hant': 'zh-TW', ja: 'ja', ko: 'ko' }
const PREVIEW = {
  en: ['Appearance', 'System', 'Light', 'Dark', 'The Mac app, as it looks today'],
  zh: ['外观', '跟随系统', '浅色', '深色', 'Mac 客户端实际界面'],
  'zh-Hant': ['外觀', '跟隨系統', '淺色', '深色', 'Mac 用戶端實際介面'],
  ja: ['外観', 'システム', 'ライト', 'ダーク', 'Mac アプリの実際の画面'],
  ko: ['외관', '시스템', '밝게', '어둡게', '실제 Mac 앱 화면'],
}
const PREVIEW_KEYS = ['theme.label', 'theme.system', 'theme.light', 'theme.dark', 'preview.sample']

function pickLang() {
  try { const saved = localStorage.getItem('lang'); if (saved && T[saved]) return saved } catch {}
  const q = new URLSearchParams(location.search).get('lang')
  if (q && T[q]) return q
  for (const l of navigator.languages || [navigator.language]) {
    const s = (l || '').toLowerCase()
    // zh-Hant / zh-TW / zh-HK / zh-MO → 繁体，其他中文 → 简体
    if (s.startsWith('zh')) return /hant|^zh-(tw|hk|mo)/.test(s) && !s.includes('hans') ? 'zh-Hant' : 'zh'
    const p = s.slice(0, 2)
    if (T[p]) return p
  }
  return 'en'
}

// 「原理」一节的示例额度条和估算说明，说明行随界面语言切换。
function termHTML(t) {
  const e = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;')
  const resets = (when) => t['term.resets'] === 'Resets'
    ? `<span class="dim">Resets</span> <span class="time">${e(when)}</span>`
    : `<span class="time">${e(when)}</span> <span class="dim">${e(t['term.resets'])}</span>`
  return [
    '<span class="dim">5h  </span> <span class="ok">██████████</span><span class="tick">│</span><span class="ok">█</span><span class="track">░░░░░░░</span>  <b>≈56.4%</b>   <span class="dim">3h 6m</span>',
    '      ' + resets(t['term.today']),
    '      <span class="dim">' + e(t['term.empty']) + '</span>',
    '',
    '<span class="dim">week</span> <span class="bad">█████████</span><span class="tick">│</span><span class="bad">██████</span><span class="track">░░░</span>  <b>≈90.2%</b>   <span class="dim">3d 19h</span>',
    '      ' + resets(t['term.sunday']),
    '',
    '<span class="dim">' + e(t['term.bythen']) + '</span>',
  ].join('\n')
}

function apply(lang) {
  const t = { ...T[lang], ...Object.fromEntries(PREVIEW_KEYS.map((key, index) => [key, PREVIEW[lang][index]])) }
  document.documentElement.lang = HTML_LANG[lang]
  document.title = t['meta.title']
  document.querySelectorAll('[data-i18n]').forEach((el) => { const v = t[el.dataset.i18n]; if (v) el.textContent = v })
  // 标题里只有 <em>，文案是自己写的常量
  document.querySelectorAll('[data-i18n-html]').forEach((el) => { const v = t[el.dataset.i18nHtml]; if (v) el.innerHTML = v })
  document.querySelectorAll('[data-shot]').forEach((img) => {
    img.alt = t['shots.' + img.dataset.shot] || t['shots.usage']
  })
  updateThemeColor()
  document.querySelector('.term').innerHTML = termHTML(t)
  document.getElementById('lang').value = lang
}

let lang = pickLang()

const themePicker = document.getElementById('theme')
const systemDark = matchMedia('(prefers-color-scheme: dark)')
function updateThemeColor() {
  const theme = document.documentElement.dataset.theme
  const isDark = theme === 'dark' || (!theme && systemDark.matches)
  document.querySelector('meta[name="theme-color"]').content = isDark ? '#0b1018' : '#f5f7f9'
  document.querySelectorAll('[data-shot]').forEach((img) => {
    img.src = `/assets/${img.dataset.shot}-${lang}-${isDark ? 'dark' : 'light'}.webp`
  })
}
themePicker.value = document.documentElement.dataset.theme || 'system'
themePicker.addEventListener('change', (event) => {
  const theme = event.target.value
  if (theme === 'system') delete document.documentElement.dataset.theme
  else document.documentElement.dataset.theme = theme
  try { localStorage.setItem('quotlet-theme', theme) } catch {}
  updateThemeColor()
})
systemDark.addEventListener('change', updateThemeColor)
apply(lang)

document.getElementById('lang').addEventListener('change', (e) => {
  lang = e.target.value
  try { localStorage.setItem('lang', lang) } catch {}
  apply(lang)
})

// 按当前语言复制安装命令或 AI 提示词
document.querySelectorAll('[data-copy], [data-copy-key]').forEach((b) => {
  b.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(b.dataset.copyKey ? T[lang][b.dataset.copyKey] : b.dataset.copy) } catch { return }
    const label = b.querySelector('.copy') || b
    label.textContent = T[lang]['cta.copied']
    setTimeout(() => { label.textContent = T[lang][b.dataset.i18n || 'cta.copy'] }, 1600)
  })
})
