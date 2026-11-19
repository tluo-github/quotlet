// 门户网站：语言切换 + 复制命令。文案都在这里，HTML 里的英文是默认值（也给搜索引擎看）。
'use strict'

const T = {
  en: {
    'meta.title': 'Quotlet — Claude and Codex quotas in your menu bar',
    'nav.how': 'How it works', 'nav.features': 'Features', 'nav.cloud': 'Cloud', 'nav.trust': 'Privacy', 'nav.source': 'Source',
    'nav.language': 'Language', 'nav.download': 'Download',
    'cta.copy': 'Copy', 'cta.copied': 'Copied', 'cta.dmg': 'Download .dmg',
    'hero.label': 'macOS menu bar · free & open source',
    'hero.title': 'How much quota is left? <em>See it at a glance.</em>',
    'hero.lead': "Track Claude and Codex quotas, reset times and local tokens from your Mac menu bar. Get a suggestion to switch when one provider is running low.",
    'hero.meta': 'macOS 14+ · Apple silicon & Intel · signed & notarized',
    'highlight.pace': "Claude estimates follow new local tokens between API refreshes.",
    'highlight.project': 'Usage by project', 'highlight.trend': "Compare Claude Code and Codex tokens by project, session and date.",
    'highlight.local': 'Local by default', 'highlight.sync': 'Cloud sync is optional. Nothing is reported until you sign in and enable it.',
    'how.label': 'How it works',
    'how.title': "Local updates between quota refreshes.",
    'how.lead': "Quotlet watches Claude Code and Codex session files. Enable Claude quota lookup for server readings every 10 minutes, with calibrated local estimates in between.",
    'how.p1.t': "Session files update the numbers.", 'how.p1.d': "New usage records trigger an update in about a second. Codex quotas also come from its local logs.",
    'how.p2.t': "Estimates use observed changes.", 'how.p2.d': "After at least two valid readings in the same window, new Claude tokens can estimate quota usage. The ≈ mark identifies estimates, and each API response corrects them. Models, caching and other devices affect accuracy.",
    'how.p3.t': "Alerts cover both providers.", 'how.p3.d': "Alerts default to on at 90%, at 100% and after reset. Claude estimates can trigger them too. Allow macOS notifications when prompted.",
    'term.resets': 'Resets', 'term.today': 'today 10:30', 'term.sunday': 'Sunday 3:00',
    'term.empty': "≈ Estimated from new local tokens", 'term.bythen': "Claude API refresh · every 10 minutes by default",
    'features.label': 'What it does',
    'features.title': "Quotas, sessions and statistics in one panel.",
    'f1.k': 'Menu bar', 'f1.t': 'Always in sight', 'f1.d': '"5h 41% · Wk 62%" right in the menu bar, or just "41% 62%" if you like it compact.',
    'f2.k': 'Limits', 'f2.t': 'Claude and Codex, side by side', 'f2.d': "Enable Claude quota lookup for 5-hour, weekly and model-specific limits. Codex quotas come from local logs. A switch suggestion appears when one provider is near its limit and the other has room.",
    'f3.k': "Estimates", 'f3.t': "Updates between refreshes", 'f3.d': "After calibration, new local tokens update Claude quota estimates in the panel and menu bar. The ≈ mark stays until the next API reading corrects the value.",
    'f4.k': 'Today', 'f4.t': 'Speed and cost', 'f4.d': 'Today\'s output and input tokens, requests, average and peak tok/s, and what it would cost at API prices.',
    'f5.k': 'History', 'f5.t': 'A usage history window', 'f5.d': "Use Sessions and Stats in the panel for recent activity. Open History for project trends, models, daily totals and CSV export. Daily totals stay on your Mac after old logs are cleared.",
    'f6.k': 'Alerts', 'f6.t': 'Notifications, four languages', 'f6.d': "90%, 100% and reset alerts default to on for Claude and Codex, including Claude estimates. Choose 80%, 90% or 95% for the early alert. Requires macOS notification permission.",
    'shots.usage': 'Panel', 'shots.sessions': 'Sessions', 'shots.stats': 'Stats', 'shots.settings': 'Settings',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "Optional sync",
    'cloud.title': 'The menu bar stays small. The details live on the web.',
    'cloud.lead': 'Sign in and open app.quotlet.com for the full picture: limits from every Mac you use, session history, which sessions are running or waiting for you, and token trends — on your phone too.',
    'cloud.p1.t': 'Optional, off by default.', 'cloud.p1.d': "Local stats work offline. Enabling Claude quota lookup connects to Anthropic. Browser sign-in enables optional Cloud sync.",
    'cloud.p2.t': "Choose what to sync.", 'cloud.p2.d': "Sync limits, token counts and session status. Session-title uploads have their own switch. Prompts and code stay on your Mac.",
    'cloud.p3.t': 'Stop whenever you like.', 'cloud.p3.d': 'Sign out on the Mac, or remove it from the website, and it stops sending anything.',
    'trust.label': 'Privacy',
    'trust.title': "Don't take our word for it. Check.",
    'trust.lead': "Local logs provide token statistics. Claude quota lookup and Cloud sync are optional connections you control in Settings.",
    't1.t': "Claude quota lookup is optional", 't1.d': "Enable it in Settings to read Claude Code credentials through macOS Keychain and request quotas from Anthropic. Use the dedicated authorization button if the system requires access.",
    't2.t': "Connections you enable", 't2.d': "Local mode reads files on your Mac. Claude quota lookup uses api.anthropic.com. Cloud sign-in and sync use app.quotlet.com.",
    't3.t': 'Your logs stay put', 't3.d': 'Sessions and tokens are read, never written, from the logs Claude Code and Codex already keep on your Mac.',
    't4.t': 'Signed and notarized', 't4.d': "The official download is Developer ID signed and notarized by Apple.",
    't5.t': 'Open source', 't5.d': 'MIT licensed. Every line is on GitHub, and you can build the app yourself in one command.',
    'install.label': 'Install', 'install.title': 'Three ways in.',
    'install.dmg.t': 'Download', 'install.dmg.d': 'Open the DMG and drag Quotlet into Applications. Signed and notarized, so it opens with a double-click.',
    'install.src.t': 'Build it yourself', 'install.src.d': 'Needs the Xcode command line tools.',
    'install.r1': 'macOS 14 Sonoma or later, Apple silicon or Intel',
    'install.r2': "Local Claude Code or Codex session logs. Claude quota lookup also needs a Claude subscription login",
    'install.r3': "Can't see the numbers? macOS may have tucked the icon away. Hold ⌘ and drag it where you want it.",
    'foot.disclaimer': 'Quotlet is an independent open-source project. It is not an Anthropic product and is not affiliated with Anthropic. "Claude" is a trademark of Anthropic.',
    'foot.renamed': 'Quotlet was called Quotabar before version 0.5.',
    'foot.issues': 'Issues',
    'shots.history': 'Usage history',
  },
  zh: {
    'meta.title': 'Quotlet — 在 Mac 状态栏查看 Claude 和 Codex 额度',
    'nav.how': '原理', 'nav.features': '功能', 'nav.cloud': '云同步', 'nav.trust': '隐私', 'nav.source': '源码',
    'nav.language': '语言', 'nav.download': '下载',
    'cta.copy': '复制', 'cta.copied': '已复制', 'cta.dmg': '下载 .dmg',
    'hero.label': 'macOS 状态栏 · 免费开源',
    'hero.title': '额度还剩多少，<em>一眼就知道。</em>',
    'hero.lead': "在 Mac 状态栏查看 Claude 和 Codex 额度、重置时间和本机 token 用量。一家额度紧张时，提示切换到更宽裕的一家。",
    'hero.meta': 'macOS 14+ · Apple 芯片和 Intel · 已签名和公证',
    'highlight.pace': "两次接口刷新之间，Claude 额度随本机新增 token 估算更新。",
    'highlight.project': '用量花在哪些项目', 'highlight.trend': "按项目、会话和日期对比 Claude Code 与 Codex 的 token 用量。",
    'highlight.local': '默认留在本机', 'highlight.sync': '云同步可选，登录并开启后才会上报。',
    'how.label': '原理',
    'how.title': "接口刷新之间，本机用量继续更新。",
    'how.lead': "Quotlet 监听 Claude Code 和 Codex 的 session 文件。开启 Claude 额度查询后，默认每 10 分钟获取接口读数，间隔内使用校准后的本机用量估算。",
    'how.p1.t': "日志写入后更新。", 'how.p1.d': "客户端写入新用量记录后，约一秒触发更新。Codex 的额度也来自本机日志。",
    'how.p2.t': "根据实际变化校准。", 'how.p2.d': "同一窗口内取得至少两次有效读数后，用新增 Claude token 推算额度，带 ≈ 标记，下次接口刷新时校正。模型、缓存和其他设备用量会影响精度。",
    'how.p3.t': "两家额度都提醒。", 'how.p3.d': "默认开启 90% 快到上限、100% 已用完和重置后恢复提醒，Claude 估算值也会触发。首次使用需允许 macOS 通知。",
    'term.resets': '重置', 'term.today': '今天 10:30', 'term.sunday': '本周日 03:00',
    'term.empty': "≈ 根据本机新增 token 估算", 'term.bythen': "Claude 接口默认每 10 分钟校正一次",
    'features.label': '功能',
    'features.title': "额度、会话和统计，都在一个面板。",
    'f1.k': '状态栏', 'f1.t': '一直看得到', 'f1.d': '状态栏显示「5h 41% 周 62%」，喜欢简洁也可以只显示「41% 62%」。',
    'f2.k': '额度', 'f2.t': 'Claude 和 Codex 放在一起', 'f2.d': "开启 Claude 额度查询后查看 5 小时、每周和模型额度。Codex 额度来自本机日志。一家快到上限、另一家宽裕时，显示切换建议。",
    'f3.k': "估算", 'f3.t': "刷新间隔内继续更新", 'f3.d': "校准后根据本机新增 token 推算 Claude 额度，面板和状态栏用 ≈ 标记，下一次接口读数到达后校正。",
    'f4.k': '今天', 'f4.t': '速度和费用', 'f4.d': '今天的输出、输入 token、请求数、平均和峰值 tok/s，以及按 API 价格算大约值多少钱。',
    'f5.k': '历史', 'f5.t': '用量历史窗口', 'f5.d': "面板内的会话和统计页查看近期活动，历史窗口查看项目趋势、模型占比和每日汇总，并导出 CSV。旧日志清理后，每日汇总保留在本机。",
    'f6.k': '提醒', 'f6.t': '通知和四种语言', 'f6.d': "Claude、Codex 默认开启 90%、100% 和重置恢复提醒，Claude 估算值也参与提醒。提前提醒可选 80%、90% 或 95%，需允许 macOS 通知。",
    'shots.usage': '面板', 'shots.sessions': '会话', 'shots.stats': '统计', 'shots.settings': '设置',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "可选同步",
    'cloud.title': '状态栏保持小巧，详细的放到网页上。',
    'cloud.lead': '登录后打开 app.quotlet.com 看全貌：每台 Mac 的额度、会话记录、哪些会话在执行或等你处理、token 趋势，手机上也能看。',
    'cloud.p1.t': '可选，默认关闭。', 'cloud.p1.d': "本地统计可离线使用。开启 Claude 额度查询后连接 Anthropic。通过浏览器登录后，可启用云同步。",
    'cloud.p2.t': "选择同步内容。", 'cloud.p2.d': "同步额度、token 数量和会话状态，会话标题有单独的上传开关。提示词和代码保留在本机。",
    'cloud.p3.t': '随时可以停。', 'cloud.p3.d': '在 Mac 上退出登录，或者在网站上移除这台 Mac，它就不再上传任何东西。',
    'trust.label': '隐私',
    'trust.title': '不用信我们的话，自己查。',
    'trust.lead': "本机日志提供 token 统计。Claude 额度查询和云同步均为可选连接，可在设置中控制。",
    't1.t': "Claude 额度查询按需开启", 't1.d': "在设置中开启后，通过 macOS 钥匙串读取 Claude Code 凭证，向 Anthropic 查询额度。系统需要授权时，使用专用授权按钮允许访问。",
    't2.t': "按需开启的连接", 't2.d': "本地模式读取 Mac 上的文件。Claude 额度查询连接 api.anthropic.com。云登录和同步连接 app.quotlet.com。",
    't3.t': '日志只读', 't3.d': '会话和 token 从 Claude Code 和 Codex 本来就存在你 Mac 上的日志里读，从来不写。',
    't4.t': '签名和公证', 't4.d': "官方下载包使用 Developer ID 签名，并经过 Apple 公证。",
    't5.t': '开源', 't5.d': 'MIT 协议，每一行代码都在 GitHub 上，一条命令就能自己编译。',
    'install.label': '安装', 'install.title': '三种装法。',
    'install.dmg.t': '下载', 'install.dmg.d': '打开 DMG，把 Quotlet 拖进“应用程序”。已签名和公证，双击就能打开。',
    'install.src.t': '自己编译', 'install.src.d': '需要 Xcode 命令行工具。',
    'install.r1': 'macOS 14 Sonoma 或更新，Apple 芯片和 Intel 都支持',
    'install.r2': "本机有 Claude Code 或 Codex session 日志。Claude 额度查询还需 Claude 订阅账号登录",
    'install.r3': '状态栏上看不到数字？可能被系统收进了折叠区。按住 ⌘ 把它拖到想要的位置。',
    'foot.disclaimer': 'Quotlet 是独立的开源项目，不是 Anthropic 官方产品，与 Anthropic 没有关联。“Claude”是 Anthropic 的商标。',
    'foot.renamed': 'Quotlet 在 0.5 版之前叫 Quotabar。',
    'foot.issues': '反馈问题',
    'shots.history': '用量历史',
  },
  ja: {
    'meta.title': 'Quotlet — Claude と Codex の使用上限を Mac のメニューバーに',
    'nav.how': 'しくみ', 'nav.features': '機能', 'nav.cloud': 'クラウド', 'nav.trust': 'プライバシー', 'nav.source': 'ソース',
    'nav.language': '言語', 'nav.download': 'ダウンロード',
    'cta.copy': 'コピー', 'cta.copied': 'コピーしました', 'cta.dmg': '.dmg をダウンロード',
    'hero.label': 'macOS メニューバー · 無料・オープンソース',
    'hero.title': 'あとどれだけ使える？<em>ひと目でわかる。</em>',
    'hero.lead': "Claude と Codex の使用枠、リセット時刻、ローカルのトークンを Mac のメニューバーで確認。片方の枠が少なくなったら、余裕のある方への切り替えを提案します。",
    'hero.meta': 'macOS 14 以降 · Apple シリコンと Intel · 署名・公証済み',
    'highlight.pace': "API 更新の間も、新しいローカルトークンから Claude 使用枠を推定します。",
    'highlight.project': 'プロジェクト別の使用量', 'highlight.trend': "Claude Code と Codex のトークンをプロジェクト、セッション、日付ごとに比較できます。",
    'highlight.local': '既定はローカル保存', 'highlight.sync': 'クラウド同期は任意です。ログインして有効にするまで、データは送信されません。',
    'how.label': 'しくみ',
    'how.title': "使用枠の更新間隔も、ローカルで更新。",
    'how.lead': "Claude Code と Codex の session ファイルを監視します。Claude 使用枠の取得を有効にすると、既定で 10 分ごとに API を照会し、その間は校正したローカル使用量から推定します。",
    'how.p1.t': "ログへの記録後に更新。", 'how.p1.d': "クライアントが新しい使用量を記録すると、約 1 秒で更新を開始します。Codex の使用枠もローカルログから取得します。",
    'how.p2.t': "実際の変化から校正。", 'how.p2.d': "同じ枠内で有効な値を 2 回以上取得した後、新しい Claude トークンから使用率を推定します。≈ が目印で、次の API 応答で補正します。モデル、キャッシュ、ほかの端末の使用が精度に影響します。",
    'how.p3.t': "両方の使用枠を通知。", 'how.p3.d': "90%、100%、リセット後の通知は既定でオンです。Claude の推定値でも通知します。初回は macOS の通知を許可してください。",
    'term.resets': 'リセット', 'term.today': '今日 10:30', 'term.sunday': '日曜日 3:00',
    'term.empty': "≈ 新しいローカルトークンから推定", 'term.bythen': "Claude API は既定で 10 分ごとに補正",
    'features.label': '機能',
    'features.title': "使用枠、セッション、統計をひとつのパネルに。",
    'f1.k': 'メニューバー', 'f1.t': 'いつでも見える', 'f1.d': 'メニューバーに「5h 41% 週 62%」。「41% 62%」だけのコンパクト表示も選べます。',
    'f2.k': '上限', 'f2.t': 'Claude と Codex を並べて', 'f2.d': "Claude 使用枠の取得を有効にすると、5 時間・週間・モデル別の枠を表示。Codex の枠はローカルログから取得します。片方が上限に近く、もう片方に余裕があれば切り替えを提案します。",
    'f3.k': "推定", 'f3.t': "更新間隔も使用量を追跡", 'f3.d': "校正後は新しいローカルトークンから Claude 使用枠を推定します。パネルとメニューバーに ≈ を付け、次の API 応答で補正します。",
    'f4.k': '今日', 'f4.t': '速度と費用', 'f4.d': '今日の出力・入力トークン、リクエスト数、平均とピークの tok/s、API 価格で換算した金額。',
    'f5.k': '履歴', 'f5.t': '使用量の履歴ウィンドウ', 'f5.d': "パネルのセッションと統計で最近の活動を確認。履歴ウィンドウではプロジェクトの推移、モデル別割合、日ごとの合計と CSV 書き出しを利用できます。古いログの削除後も日ごとの合計は Mac に残ります。",
    'f6.k': '通知', 'f6.t': '通知と 4 言語', 'f6.d': "Claude と Codex の 90%、100%、リセット後の通知は既定でオン。Claude の推定値も対象です。早期通知は 80・90・95% から選択でき、macOS の通知許可が必要です。",
    'shots.usage': 'パネル', 'shots.sessions': 'セッション', 'shots.stats': '統計', 'shots.settings': '設定',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "任意の同期",
    'cloud.title': 'メニューバーは小さいまま。詳しくは Web で。',
    'cloud.lead': 'ログインして app.quotlet.com を開けば全体が見えます。すべての Mac の上限、セッション履歴、実行中や対応待ちのセッション、トークンの推移。スマートフォンでも。',
    'cloud.p1.t': '任意、初期設定はオフ。', 'cloud.p1.d': "ローカル集計はオフラインで使えます。Claude 使用枠の取得で Anthropic に接続し、ブラウザーでログインすると任意のクラウド同期を利用できます。",
    'cloud.p2.t': "同期する内容を選択。", 'cloud.p2.d': "使用枠、トークン数、セッションの状態を同期します。セッション名の送信は個別に設定できます。プロンプトとコードは Mac 内に保存されます。",
    'cloud.p3.t': 'いつでもやめられる。', 'cloud.p3.d': 'Mac でログアウトするか、Web からその Mac を削除すれば、何も送らなくなります。',
    'trust.label': 'プライバシー',
    'trust.title': '信じなくていい。確かめてください。',
    'trust.lead': "トークン統計はローカルログから取得。Claude 使用枠の照会とクラウド同期は設定で選べます。",
    't1.t': "Claude 使用枠の照会は任意", 't1.d': "設定で有効にすると、macOS キーチェーンから Claude Code の認証情報を読み取り、Anthropic に使用枠を照会します。システムの許可が必要な場合は専用ボタンを使います。",
    't2.t': "選択して有効にする接続", 't2.d': "ローカルモードは Mac 上のファイルを読み取ります。Claude 使用枠は api.anthropic.com、クラウドのログインと同期は app.quotlet.com に接続します。",
    't3.t': 'ログは読むだけ', 't3.d': 'セッションとトークンは、Claude Code と Codex がもともと Mac に保存しているログから読み取るだけで、書き込みはしません。',
    't4.t': '署名・公証済み', 't4.d': "公式ダウンロードは Developer ID で署名され、Apple の公証を受けています。",
    't5.t': 'オープンソース', 't5.d': 'MIT ライセンス。コードはすべて GitHub にあり、コマンド 1 つで自分でビルドできます。',
    'install.label': 'インストール', 'install.title': '3 つの方法。',
    'install.dmg.t': 'ダウンロード', 'install.dmg.d': 'DMG を開いて Quotlet をアプリケーションフォルダにドラッグ。署名・公証済みなのでダブルクリックで開けます。',
    'install.src.t': '自分でビルド', 'install.src.d': 'Xcode コマンドラインツールが必要です。',
    'install.r1': 'macOS 14 Sonoma 以降、Apple シリコンまたは Intel',
    'install.r2': "Claude Code または Codex のローカル session ログ。Claude 使用枠の取得には Claude サブスクリプションのログインも必要です",
    'install.r3': '数字が見えない場合は、アイコンが隠れているかもしれません。⌘ を押しながら好きな位置にドラッグしてください。',
    'foot.disclaimer': 'Quotlet は独立したオープンソースプロジェクトであり、Anthropic の製品ではなく、Anthropic とは関係ありません。「Claude」は Anthropic の商標です。',
    'foot.renamed': 'Quotlet はバージョン 0.5 より前は Quotabar という名前でした。',
    'foot.issues': '不具合の報告',
    'shots.history': '使用量の履歴',
  },
  ko: {
    'meta.title': 'Quotlet — Claude와 Codex 사용 한도를 Mac 메뉴 막대에서',
    'nav.how': '작동 방식', 'nav.features': '기능', 'nav.cloud': '클라우드', 'nav.trust': '개인정보', 'nav.source': '소스',
    'nav.language': '언어', 'nav.download': '다운로드',
    'cta.copy': '복사', 'cta.copied': '복사됨', 'cta.dmg': '.dmg 다운로드',
    'hero.label': 'macOS 메뉴 막대 · 무료 오픈 소스',
    'hero.title': '얼마나 남았을까? <em>한눈에 확인하세요.</em>',
    'hero.lead': "Mac 메뉴 막대에서 Claude와 Codex의 한도, 재설정 시간, 로컬 토큰을 확인하세요. 한쪽 한도가 부족해지면 여유 있는 쪽으로 전환을 제안합니다.",
    'hero.meta': 'macOS 14 이상 · Apple 실리콘 및 Intel · 서명 및 공증 완료',
    'highlight.pace': "API 새로 고침 사이에도 새 로컬 토큰으로 Claude 한도를 추정합니다.",
    'highlight.project': '프로젝트별 사용량', 'highlight.trend': "프로젝트, 세션, 날짜별로 Claude Code와 Codex 토큰을 비교하세요.",
    'highlight.local': '기본은 로컬 저장', 'highlight.sync': '클라우드 동기화는 선택 사항입니다. 로그인한 뒤 켜야 데이터가 전송됩니다.',
    'how.label': '작동 방식',
    'how.title': "한도 새로 고침 사이에도 로컬에서 갱신.",
    'how.lead': "Claude Code와 Codex의 session 파일을 감시합니다. Claude 한도 조회를 켜면 기본 10분마다 API 값을 가져오고, 그 사이에는 보정한 로컬 사용량으로 추정합니다.",
    'how.p1.t': "로그에 기록되면 갱신.", 'how.p1.d': "클라이언트가 새 사용량을 기록하면 약 1초 후 갱신을 시작합니다. Codex 한도도 로컬 로그에서 읽습니다.",
    'how.p2.t': "실제 변화로 보정.", 'how.p2.d': "같은 한도 구간에서 두 번 이상 유효한 값을 얻은 뒤 새 Claude 토큰으로 사용률을 추정합니다. ≈ 표시로 구분하며 다음 API 응답으로 보정합니다. 모델, 캐시, 다른 기기의 사용이 정확도에 영향을 줍니다.",
    'how.p3.t': "두 서비스 모두 알림.", 'how.p3.d': "90%, 100%, 재설정 후 알림이 기본으로 켜져 있습니다. Claude 추정값도 알림을 보냅니다. 처음에는 macOS 알림 권한을 허용하세요.",
    'term.resets': '재설정', 'term.today': '오늘 10:30', 'term.sunday': '일요일 3:00',
    'term.empty': "≈ 새 로컬 토큰으로 추정", 'term.bythen': "Claude API는 기본 10분마다 보정",
    'features.label': '기능',
    'features.title': "한도, 세션, 통계를 한 패널에서.",
    'f1.k': '메뉴 막대', 'f1.t': '항상 보이는 한도', 'f1.d': '메뉴 막대에 "5h 41% 주 62%". 간단하게 "41% 62%"만 표시할 수도 있습니다.',
    'f2.k': '한도', 'f2.t': 'Claude와 Codex를 나란히', 'f2.d': "Claude 한도 조회를 켜면 5시간·주간·모델별 한도를 표시합니다. Codex 한도는 로컬 로그에서 읽습니다. 한쪽이 한도에 가깝고 다른 쪽이 여유로우면 전환을 제안합니다.",
    'f3.k': "추정", 'f3.t': "새로 고침 사이에도 갱신", 'f3.d': "보정 후 새 로컬 토큰으로 Claude 한도를 추정합니다. 패널과 메뉴 막대에 ≈를 표시하고 다음 API 응답으로 보정합니다.",
    'f4.k': '오늘', 'f4.t': '속도와 비용', 'f4.d': '오늘의 출력·입력 토큰, 요청 수, 평균과 최고 tok/s, API 가격으로 환산한 금액.',
    'f5.k': '기록', 'f5.t': '사용량 기록 창', 'f5.d': "패널의 세션과 통계에서 최근 활동을 확인하고, 기록 창에서 프로젝트 추이, 모델 비중, 일별 합계와 CSV 내보내기를 사용하세요. 오래된 로그를 지워도 일별 합계는 Mac에 보관됩니다.",
    'f6.k': '알림', 'f6.t': '알림과 4개 언어', 'f6.d': "Claude와 Codex의 90%, 100%, 재설정 알림은 기본으로 켜져 있으며 Claude 추정값도 포함됩니다. 사전 알림은 80·90·95%에서 고를 수 있고 macOS 알림 권한이 필요합니다.",
    'shots.usage': '패널', 'shots.sessions': '세션', 'shots.stats': '통계', 'shots.settings': '설정',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': "선택적 동기화",
    'cloud.title': '메뉴 막대는 작게. 자세한 내용은 웹에서.',
    'cloud.lead': '로그인하고 app.quotlet.com을 열면 전체가 보입니다. 모든 Mac의 한도, 세션 기록, 실행 중이거나 응답을 기다리는 세션, 토큰 추이. 휴대폰에서도.',
    'cloud.p1.t': '선택 사항, 기본값은 꺼짐.', 'cloud.p1.d': "로컬 통계는 오프라인으로 사용할 수 있습니다. Claude 한도 조회를 켜면 Anthropic에 연결하며, 브라우저로 로그인한 뒤 선택적으로 클라우드 동기화를 사용할 수 있습니다.",
    'cloud.p2.t': "동기화할 내용 선택.", 'cloud.p2.d': "한도, 토큰 수, 세션 상태를 동기화합니다. 세션 제목 업로드는 별도로 설정할 수 있습니다. 프롬프트와 코드는 Mac에 보관됩니다.",
    'cloud.p3.t': '언제든 멈출 수 있습니다.', 'cloud.p3.d': 'Mac에서 로그아웃하거나 웹에서 그 Mac을 제거하면 더 이상 아무것도 보내지 않습니다.',
    'trust.label': '개인정보',
    'trust.title': '믿지 말고 확인하세요.',
    'trust.lead': "토큰 통계는 로컬 로그에서 읽습니다. Claude 한도 조회와 클라우드 동기화는 설정에서 선택할 수 있습니다.",
    't1.t': "Claude 한도 조회는 선택 사항", 't1.d': "설정에서 켜면 macOS 키체인으로 Claude Code 자격 증명을 읽고 Anthropic에 한도를 조회합니다. 시스템 권한이 필요하면 전용 승인 버튼을 사용하세요.",
    't2.t': "직접 켜는 연결", 't2.d': "로컬 모드는 Mac의 파일을 읽습니다. Claude 한도 조회는 api.anthropic.com에, 클라우드 로그인과 동기화는 app.quotlet.com에 연결합니다.",
    't3.t': '로그는 읽기만', 't3.d': '세션과 토큰은 Claude Code와 Codex가 원래 Mac에 남기는 로그에서 읽기만 하고 쓰지 않습니다.',
    't4.t': '서명 및 공증', 't4.d': "공식 다운로드는 Developer ID로 서명되고 Apple 공증을 받았습니다.",
    't5.t': '오픈 소스', 't5.d': 'MIT 라이선스. 모든 코드가 GitHub에 있으며 명령 하나로 직접 빌드할 수 있습니다.',
    'install.label': '설치', 'install.title': '세 가지 방법.',
    'install.dmg.t': '다운로드', 'install.dmg.d': 'DMG를 열고 Quotlet을 응용 프로그램 폴더로 드래그하세요. 서명 및 공증되어 더블 클릭으로 열립니다.',
    'install.src.t': '직접 빌드', 'install.src.d': 'Xcode 명령줄 도구가 필요합니다.',
    'install.r1': 'macOS 14 Sonoma 이상, Apple 실리콘 또는 Intel',
    'install.r2': "Claude Code 또는 Codex의 로컬 session 로그. Claude 한도 조회에는 Claude 구독 계정 로그인도 필요합니다",
    'install.r3': '숫자가 보이지 않나요? 아이콘이 숨겨졌을 수 있습니다. ⌘를 누른 채 원하는 위치로 드래그하세요.',
    'foot.disclaimer': 'Quotlet은 독립적인 오픈 소스 프로젝트로, Anthropic 제품이 아니며 Anthropic과 관련이 없습니다. "Claude"는 Anthropic의 상표입니다.',
    'foot.renamed': 'Quotlet은 0.5 버전 이전에는 Quotabar라는 이름이었습니다.',
    'foot.issues': '문제 신고',
    'shots.history': '사용량 기록',
  },
}

const HTML_LANG = { en: 'en', zh: 'zh-CN', ja: 'ja', ko: 'ko' }
const PREVIEW = {
  en: ['Appearance', 'System', 'Light', 'Dark', 'Use Codex for now · 88% left in the 5-hour window', '5 hours', 'Week', 'Menu bar preview · Example data'],
  zh: ['外观', '跟随系统', '浅色', '深色', '先用 Codex · 5 小时额度还剩 88%', '5 小时', '本周', '状态栏预览 · 示例数据'],
  ja: ['外観', 'システム', 'ライト', 'ダーク', '今は Codex を使用 · 5 時間枠の残り 88%', '5 時間', '今週', 'メニューバーのプレビュー · サンプルデータ'],
  ko: ['외관', '시스템', '밝게', '어둡게', '지금은 Codex 사용 · 5시간 한도 88% 남음', '5시간', '이번 주', '메뉴 막대 미리보기 · 예시 데이터'],
}
const PREVIEW_KEYS = ['theme.label', 'theme.system', 'theme.light', 'theme.dark', 'preview.advice', 'preview.hours', 'preview.week', 'preview.sample']

function pickLang() {
  try { const saved = localStorage.getItem('lang'); if (saved && T[saved]) return saved } catch {}
  const q = new URLSearchParams(location.search).get('lang')
  if (q && T[q]) return q
  for (const l of navigator.languages || [navigator.language]) {
    const p = (l || '').toLowerCase().slice(0, 2)
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
    img.src = `/assets/${img.dataset.shot}-${lang}.webp`
    img.alt = t['shots.' + img.dataset.shot]
  })
  document.querySelector('.term').innerHTML = termHTML(t)
  document.getElementById('lang').value = lang
}

let lang = pickLang()
apply(lang)

const themePicker = document.getElementById('theme')
const systemDark = matchMedia('(prefers-color-scheme: dark)')
function updateThemeColor() {
  const theme = document.documentElement.dataset.theme
  const isDark = theme === 'dark' || (!theme && systemDark.matches)
  document.querySelector('meta[name="theme-color"]').content = isDark ? '#101915' : '#f7f6ef'
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
updateThemeColor()

document.getElementById('lang').addEventListener('change', (e) => {
  lang = e.target.value
  try { localStorage.setItem('lang', lang) } catch {}
  apply(lang)
})

// 复制 brew 命令
document.querySelectorAll('[data-copy]').forEach((b) => {
  b.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy) } catch { return }
    const label = b.querySelector('.copy') || b
    label.textContent = T[lang]['cta.copied']
    setTimeout(() => { label.textContent = T[lang]['cta.copy'] }, 1600)
  })
})
