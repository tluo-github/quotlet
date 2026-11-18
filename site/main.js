// 门户网站：语言切换 + 复制命令。文案都在这里，HTML 里的英文是默认值（也给搜索引擎看）。
'use strict'

const T = {
  en: {
    'meta.title': 'Quotlet — Claude usage limits in your Mac menu bar',
    'nav.how': 'How it works', 'nav.features': 'Features', 'nav.cloud': 'Cloud', 'nav.trust': 'Privacy', 'nav.source': 'Source',
    'nav.language': 'Language', 'nav.download': 'Download',
    'cta.copy': 'Copy', 'cta.copied': 'Copied', 'cta.dmg': 'Download .dmg',
    'hero.label': 'macOS menu bar · free & open source',
    'hero.title': 'How much Claude is left — <em>and how long it will last.</em>',
    'hero.lead': 'Quotlet sits in your menu bar and shows the 5-hour and weekly limits of your Claude plan — the same numbers as /usage — and your Codex limits too, with reset times and a pace forecast that warns you while there\'s still time to slow down.',
    'hero.meta': 'macOS 14+ · Apple silicon & Intel · signed & notarized',
    'panel.alt': 'The Quotlet panel: the 5-hour window at 56% with a warning that it will run out before the reset, and this week at 90%.',
    'stat.host': 'outbound host', 'stat.paste': 'tokens to paste', 'stat.account': 'accounts needed', 'stat.lang': 'languages',
    'how.label': 'How it works',
    'how.title': 'A percentage is only half the answer.',
    'how.lead': "56% sounds fine — unless the window opened an hour ago. Quotlet puts how much you've used next to how much of the window has passed, and works out whether you'll make it to the reset.",
    'how.p1.t': 'The tick is the clock.', 'how.p1.d': "It marks how much of the window has gone by. A bar past its tick means you're spending faster than time is passing.",
    'how.p2.t': 'The forecast is plain arithmetic.', 'how.p2.d': 'Your average pace so far in this window, carried forward to the reset. No history to collect, no model to train — it works from the first refresh.',
    'how.p3.t': 'Quiet until it matters.', 'how.p3.d': "When a limit is on track, you just see where it will land. When it isn't, you get one red line saying when it runs out.",
    'term.resets': 'Resets', 'term.today': 'today 10:30', 'term.sunday': 'Sunday 3:00',
    'term.empty': 'Empty in ~1h 29m — 1h 37m before reset', 'term.bythen': '· ~31% by then',
    'features.label': 'What it does',
    'features.title': 'Everything /usage tells you, without opening a terminal.',
    'f1.k': 'Menu bar', 'f1.t': 'Always in sight', 'f1.d': '"5h 41% · Wk 62%" right in the menu bar, or just "41% 62%" if you like it compact.',
    'f2.k': 'Limits', 'f2.t': 'Claude and Codex, side by side', 'f2.d': 'Every Claude limit and, if you use Codex, its 5-hour and weekly limits, one line each with the reset time and a countdown.',
    'f3.k': 'Forecast', 'f3.t': 'Warns before the wall', 'f3.d': 'Says where each limit will land at the reset, or how long until it runs out if you keep this pace.',
    'f4.k': 'Today', 'f4.t': 'Speed and cost', 'f4.d': 'Today\'s output and input tokens, requests, average and peak tok/s, and what it would cost at API prices.',
    'f5.k': 'History', 'f5.t': 'A usage history window', 'f5.d': 'Daily output and cost by source, a speed trend, weekly-limit history and every session, with CSV export. Daily totals stay on your Mac after Claude Code clears old logs.',
    'f6.k': 'Alerts', 'f6.t': 'Notifications, four languages', 'f6.d': 'A heads-up at 80, 90 or 95% and when a limit is back. English, 简体中文, 日本語 and 한국어; an HTTP proxy for regions that need one.',
    'shots.usage': 'Panel', 'shots.sessions': 'Sessions', 'shots.stats': 'Stats', 'shots.settings': 'Settings',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': 'new in 0.5',
    'cloud.title': 'The menu bar stays small. The details live on the web.',
    'cloud.lead': 'Sign in and open app.quotlet.com for the full picture: limits from every Mac you use, session history, which sessions are running or waiting for you, and token trends — on your phone too.',
    'cloud.p1.t': 'Optional, off by default.', 'cloud.p1.d': 'Without signing in, Quotlet never talks to anything but Anthropic. Cloud only starts after you sign in on that Mac.',
    'cloud.p2.t': 'Numbers, not conversations.', 'cloud.p2.d': 'It sends limits, token counts and session status. Your prompts and code never leave the Mac; session titles can be turned off too.',
    'cloud.p3.t': 'Stop whenever you like.', 'cloud.p3.d': 'Sign out on the Mac, or remove it from the website, and it stops sending anything.',
    'trust.label': 'Privacy',
    'trust.title': "Don't take our word for it. Check.",
    'trust.lead': 'No account, no telemetry, nothing to paste. Each claim below comes with a way to verify it yourself.',
    't1.t': 'Uses the login Claude Code already has', 't1.d': "It reads Claude Code's token from your Keychain with the system security tool. It never refreshes, changes or saves it, and only sends it to Anthropic.",
    't2.t': 'One outbound host', 't2.d': 'api.anthropic.com, to ask for your usage. app.quotlet.com is added only after you sign in to Cloud.',
    't3.t': 'Your logs stay put', 't3.d': 'Sessions and tokens are read, never written, from the logs Claude Code and Codex already keep on your Mac.',
    't4.t': 'Signed and notarized', 't4.d': 'Every release is signed with a Developer ID and notarized by Apple.',
    't5.t': 'Open source', 't5.d': 'MIT licensed. Every line is on GitHub, and you can build the app yourself in one command.',
    'install.label': 'Install', 'install.title': 'Three ways in.',
    'install.dmg.t': 'Download', 'install.dmg.d': 'Open the DMG and drag Quotlet into Applications. Signed and notarized, so it opens with a double-click.',
    'install.src.t': 'Build it yourself', 'install.src.d': 'Needs the Xcode command line tools.',
    'install.r1': 'macOS 14 Sonoma or later, Apple silicon or Intel',
    'install.r2': 'Claude Code installed and signed in with a Claude Pro or Max plan',
    'install.r3': "Can't see the numbers? macOS may have tucked the icon away. Hold ⌘ and drag it where you want it.",
    'foot.disclaimer': 'Quotlet is an independent open-source project. It is not an Anthropic product and is not affiliated with Anthropic. "Claude" is a trademark of Anthropic.',
    'foot.renamed': 'Quotlet was called Quotabar before version 0.5.',
    'foot.issues': 'Issues',
    'shots.history': 'Usage history',
  },
  zh: {
    'meta.title': 'Quotlet — 在 Mac 状态栏查看 Claude 额度',
    'nav.how': '原理', 'nav.features': '功能', 'nav.cloud': '云同步', 'nav.trust': '隐私', 'nav.source': '源码',
    'nav.language': '语言', 'nav.download': '下载',
    'cta.copy': '复制', 'cta.copied': '已复制', 'cta.dmg': '下载 .dmg',
    'hero.label': 'macOS 状态栏 · 免费开源',
    'hero.title': 'Claude 额度还剩多少，<em>还能撑多久。</em>',
    'hero.lead': 'Quotlet 待在状态栏里，显示 Claude 套餐的 5 小时和每周额度（和 /usage 一样的数字），也显示 Codex 的额度，带重置时间，还会按你现在的速度预测：照这样用，会不会在重置前用完。',
    'hero.meta': 'macOS 14+ · Apple 芯片和 Intel · 已签名和公证',
    'panel.alt': 'Quotlet 面板：5 小时额度用了 56%，提示会在重置前用完；本周用了 90%。',
    'stat.host': '个联网地址', 'stat.paste': '次粘贴 token', 'stat.account': '个要注册的账号', 'stat.lang': '种语言',
    'how.label': '原理',
    'how.title': '百分比只说了一半。',
    'how.lead': '用了 56% 听起来还好，可如果这个窗口才开始一小时呢？Quotlet 把「用了多少」和「时间过了多少」放在一起看，算出能不能撑到重置。',
    'how.p1.t': '竖线是时钟。', 'how.p1.d': '它标出这个窗口的时间已经过了多少。进度条跑到竖线前面，说明你用得比时间走得快。',
    'how.p2.t': '预测就是简单的算术。', 'how.p2.d': '用这个窗口里到现在为止的平均速度，推算到重置那一刻。不用攒历史数据，第一次刷新就能用。',
    'how.p3.t': '没事不打扰。', 'how.p3.d': '够用的时候，只告诉你重置时大概用到多少；不够用时，多一行红字告诉你什么时候用完。',
    'term.resets': '重置', 'term.today': '今天 10:30', 'term.sunday': '本周日 03:00',
    'term.empty': '约 1小时29分后用完，比重置早 1小时37分', 'term.bythen': '· 届时约 31%',
    'features.label': '功能',
    'features.title': '/usage 能告诉你的，不开终端也能看到。',
    'f1.k': '状态栏', 'f1.t': '一直看得到', 'f1.d': '状态栏显示「5h 41% 周 62%」，喜欢简洁也可以只显示「41% 62%」。',
    'f2.k': '额度', 'f2.t': 'Claude 和 Codex 放在一起', 'f2.d': 'Claude 的每一条额度，用 Codex 的话还有它的 5 小时和每周额度，一条一行，带重置时间和倒计时。',
    'f3.k': '预测', 'f3.t': '用完之前就提醒', 'f3.d': '告诉你每条额度重置时大概用到多少；照这个速度会提前用完的话，还剩多久。',
    'f4.k': '今天', 'f4.t': '速度和费用', 'f4.d': '今天的输出、输入 token、请求数、平均和峰值 tok/s，以及按 API 价格算大约值多少钱。',
    'f5.k': '历史', 'f5.t': '用量历史窗口', 'f5.d': '按来源看每天的输出和费用、速度走势、每周额度走势和所有会话，可以导出 CSV。每天的汇总存在本机，Claude Code 清理旧日志后也还在。',
    'f6.k': '提醒', 'f6.t': '通知和四种语言', 'f6.d': '用到 80%、90% 或 95% 和额度恢复时提醒你。简体中文、English、日本語、한국어；需要时可以走 HTTP 代理。',
    'shots.usage': '面板', 'shots.sessions': '会话', 'shots.stats': '统计', 'shots.settings': '设置',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': '0.5 新功能',
    'cloud.title': '状态栏保持小巧，详细的放到网页上。',
    'cloud.lead': '登录后打开 app.quotlet.com 看全貌：每台 Mac 的额度、会话记录、哪些会话在执行或等你处理、token 趋势，手机上也能看。',
    'cloud.p1.t': '可选，默认关闭。', 'cloud.p1.d': '不登录的话，Quotlet 除了 Anthropic 不连任何地方。在那台 Mac 上登录之后才开始同步。',
    'cloud.p2.t': '只传数字，不传对话。', 'cloud.p2.d': '上传的是额度、token 数量和会话状态。提示词和代码不会离开你的 Mac；会话标题也可以关掉不传。',
    'cloud.p3.t': '随时可以停。', 'cloud.p3.d': '在 Mac 上退出登录，或者在网站上移除这台 Mac，它就不再上传任何东西。',
    'trust.label': '隐私',
    'trust.title': '不用信我们的话，自己查。',
    'trust.lead': '不用注册、不收集统计、不用粘贴任何东西。下面每一条都附了一个自己验证的方法。',
    't1.t': '用 Claude Code 现成的登录', 't1.d': '用系统自带的 security 命令从钥匙串读取 Claude Code 的 token，不刷新、不改动、不保存，只发给 Anthropic。',
    't2.t': '只连一个地址', 't2.d': 'api.anthropic.com，用来查询用量。登录 Cloud 之后才会多一个 app.quotlet.com。',
    't3.t': '日志只读', 't3.d': '会话和 token 从 Claude Code 和 Codex 本来就存在你 Mac 上的日志里读，从来不写。',
    't4.t': '签名和公证', 't4.d': '每个正式版都用 Developer ID 签名，并经过苹果公证。',
    't5.t': '开源', 't5.d': 'MIT 协议，每一行代码都在 GitHub 上，一条命令就能自己编译。',
    'install.label': '安装', 'install.title': '三种装法。',
    'install.dmg.t': '下载', 'install.dmg.d': '打开 DMG，把 Quotlet 拖进“应用程序”。已签名和公证，双击就能打开。',
    'install.src.t': '自己编译', 'install.src.d': '需要 Xcode 命令行工具。',
    'install.r1': 'macOS 14 Sonoma 或更新，Apple 芯片和 Intel 都支持',
    'install.r2': '已安装 Claude Code，并用 Claude Pro 或 Max 套餐登录',
    'install.r3': '状态栏上看不到数字？可能被系统收进了折叠区。按住 ⌘ 把它拖到想要的位置。',
    'foot.disclaimer': 'Quotlet 是独立的开源项目，不是 Anthropic 官方产品，与 Anthropic 没有关联。“Claude”是 Anthropic 的商标。',
    'foot.renamed': 'Quotlet 在 0.5 版之前叫 Quotabar。',
    'foot.issues': '反馈问题',
    'shots.history': '用量历史',
  },
  ja: {
    'meta.title': 'Quotlet — Claude の使用上限を Mac のメニューバーに',
    'nav.how': 'しくみ', 'nav.features': '機能', 'nav.cloud': 'クラウド', 'nav.trust': 'プライバシー', 'nav.source': 'ソース',
    'nav.language': '言語', 'nav.download': 'ダウンロード',
    'cta.copy': 'コピー', 'cta.copied': 'コピーしました', 'cta.dmg': '.dmg をダウンロード',
    'hero.label': 'macOS メニューバー · 無料・オープンソース',
    'hero.title': 'Claude はあとどれだけ使えて、<em>いつまでもつのか。</em>',
    'hero.lead': 'Quotlet はメニューバーに常駐し、Claude プランの 5 時間枠と週間上限（/usage と同じ数字）と Codex の上限をリセット時刻つきで表示。今のペースだとリセット前に使い切るかどうかも予測します。',
    'hero.meta': 'macOS 14 以降 · Apple シリコンと Intel · 署名・公証済み',
    'panel.alt': 'Quotlet のパネル：5 時間枠は 56% でリセット前に上限に達する見込み、今週は 90%。',
    'stat.host': '接続先', 'stat.paste': '回のトークン貼り付け', 'stat.account': '個の登録アカウント', 'stat.lang': '言語',
    'how.label': 'しくみ',
    'how.title': 'パーセントだけでは半分しかわからない。',
    'how.lead': '56% なら余裕に見えます。でも枠が始まってまだ 1 時間だったら？ Quotlet は「どれだけ使ったか」と「どれだけ時間が過ぎたか」を並べて、リセットまでもつかを計算します。',
    'how.p1.t': '縦線は時計です。', 'how.p1.d': '枠の時間がどれだけ過ぎたかを示します。バーが縦線より先にあれば、時間より速いペースで使っています。',
    'how.p2.t': '予測はただの算数です。', 'how.p2.d': 'この枠でのこれまでの平均ペースをリセット時刻まで延ばすだけ。履歴を集める必要はなく、最初の更新から使えます。',
    'how.p3.t': '必要なときだけ知らせます。', 'how.p3.d': '足りるときはリセット時の見込みだけ。足りないときは、いつ上限に達するかを赤い 1 行で伝えます。',
    'term.resets': 'リセット', 'term.today': '今日 10:30', 'term.sunday': '日曜日 3:00',
    'term.empty': '約1時間29分で上限 · リセットの1時間37分前', 'term.bythen': '· その時点で約 31%',
    'features.label': '機能',
    'features.title': '/usage でわかることを、ターミナルを開かずに。',
    'f1.k': 'メニューバー', 'f1.t': 'いつでも見える', 'f1.d': 'メニューバーに「5h 41% 週 62%」。「41% 62%」だけのコンパクト表示も選べます。',
    'f2.k': '上限', 'f2.t': 'Claude と Codex を並べて', 'f2.d': 'Claude のすべての上限と、Codex を使っていればその 5 時間・週間上限を 1 行ずつ、リセット時刻とカウントダウンつきで。',
    'f3.k': '予測', 'f3.t': '使い切る前に知らせる', 'f3.d': 'リセット時にどこまで使っているか、このペースだとあとどれくらいで上限に達するかを表示。',
    'f4.k': '今日', 'f4.t': '速度と費用', 'f4.d': '今日の出力・入力トークン、リクエスト数、平均とピークの tok/s、API 価格で換算した金額。',
    'f5.k': '履歴', 'f5.t': '使用量の履歴ウィンドウ', 'f5.d': 'ソース別の日ごとの出力と費用、速度の推移、週間上限の推移、すべてのセッション。CSV で書き出せます。日ごとの合計は Mac に残るので、Claude Code が古いログを消しても大丈夫。',
    'f6.k': '通知', 'f6.t': '通知と 4 言語', 'f6.d': '80・90・95% に達したときと上限が戻ったときにお知らせ。English、简体中文、日本語、한국어。必要な地域向けの HTTP プロキシ。',
    'shots.usage': 'パネル', 'shots.sessions': 'セッション', 'shots.stats': '統計', 'shots.settings': '設定',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': '0.5 の新機能',
    'cloud.title': 'メニューバーは小さいまま。詳しくは Web で。',
    'cloud.lead': 'ログインして app.quotlet.com を開けば全体が見えます。すべての Mac の上限、セッション履歴、実行中や対応待ちのセッション、トークンの推移。スマートフォンでも。',
    'cloud.p1.t': '任意、初期設定はオフ。', 'cloud.p1.d': 'ログインしなければ、Quotlet は Anthropic 以外とは通信しません。その Mac でログインしてから同期が始まります。',
    'cloud.p2.t': '送るのは数字だけ。', 'cloud.p2.d': '上限、トークン数、セッションの状態を送ります。プロンプトやコードは Mac から出ません。セッション名の送信もオフにできます。',
    'cloud.p3.t': 'いつでもやめられる。', 'cloud.p3.d': 'Mac でログアウトするか、Web からその Mac を削除すれば、何も送らなくなります。',
    'trust.label': 'プライバシー',
    'trust.title': '信じなくていい。確かめてください。',
    'trust.lead': 'アカウント不要、テレメトリなし、貼り付けるものもなし。それぞれ自分で確かめる方法を添えました。',
    't1.t': 'Claude Code のログインをそのまま使う', 't1.d': 'システムの security コマンドでキーチェーンから Claude Code のトークンを読むだけ。更新・変更・保存はせず、送り先は Anthropic だけです。',
    't2.t': '接続先はひとつ', 't2.d': '使用量を問い合わせる api.anthropic.com だけ。Cloud にログインしたときだけ app.quotlet.com が加わります。',
    't3.t': 'ログは読むだけ', 't3.d': 'セッションとトークンは、Claude Code と Codex がもともと Mac に保存しているログから読み取るだけで、書き込みはしません。',
    't4.t': '署名・公証済み', 't4.d': 'すべてのリリースは Developer ID で署名され、Apple の公証を受けています。',
    't5.t': 'オープンソース', 't5.d': 'MIT ライセンス。コードはすべて GitHub にあり、コマンド 1 つで自分でビルドできます。',
    'install.label': 'インストール', 'install.title': '3 つの方法。',
    'install.dmg.t': 'ダウンロード', 'install.dmg.d': 'DMG を開いて Quotlet をアプリケーションフォルダにドラッグ。署名・公証済みなのでダブルクリックで開けます。',
    'install.src.t': '自分でビルド', 'install.src.d': 'Xcode コマンドラインツールが必要です。',
    'install.r1': 'macOS 14 Sonoma 以降、Apple シリコンまたは Intel',
    'install.r2': 'Claude Code をインストールし、Claude Pro または Max プランでログイン済み',
    'install.r3': '数字が見えない場合は、アイコンが隠れているかもしれません。⌘ を押しながら好きな位置にドラッグしてください。',
    'foot.disclaimer': 'Quotlet は独立したオープンソースプロジェクトであり、Anthropic の製品ではなく、Anthropic とは関係ありません。「Claude」は Anthropic の商標です。',
    'foot.renamed': 'Quotlet はバージョン 0.5 より前は Quotabar という名前でした。',
    'foot.issues': '不具合の報告',
    'shots.history': '使用量の履歴',
  },
  ko: {
    'meta.title': 'Quotlet — Claude 사용 한도를 Mac 메뉴 막대에서',
    'nav.how': '작동 방식', 'nav.features': '기능', 'nav.cloud': '클라우드', 'nav.trust': '개인정보', 'nav.source': '소스',
    'nav.language': '언어', 'nav.download': '다운로드',
    'cta.copy': '복사', 'cta.copied': '복사됨', 'cta.dmg': '.dmg 다운로드',
    'hero.label': 'macOS 메뉴 막대 · 무료 오픈 소스',
    'hero.title': 'Claude가 얼마나 남았는지, <em>언제까지 버틸지.</em>',
    'hero.lead': 'Quotlet은 메뉴 막대에서 Claude 요금제의 5시간·주간 한도(/usage와 같은 숫자)와 Codex 한도를 재설정 시간과 함께 보여 주고, 지금 속도라면 재설정 전에 다 쓸지도 예측합니다.',
    'hero.meta': 'macOS 14 이상 · Apple 실리콘 및 Intel · 서명 및 공증 완료',
    'panel.alt': 'Quotlet 패널: 5시간 한도 56%, 재설정 전에 소진될 것이라는 경고와 이번 주 90%.',
    'stat.host': '개의 접속 주소', 'stat.paste': '번의 토큰 붙여넣기', 'stat.account': '개의 가입 계정', 'stat.lang': '개 언어',
    'how.label': '작동 방식',
    'how.title': '퍼센트는 절반의 답일 뿐입니다.',
    'how.lead': '56%면 괜찮아 보이지만, 창이 열린 지 한 시간밖에 안 됐다면요? Quotlet은 얼마나 썼는지와 시간이 얼마나 지났는지를 나란히 놓고, 재설정까지 버틸 수 있는지 계산합니다.',
    'how.p1.t': '세로선은 시계입니다.', 'how.p1.d': '창의 시간이 얼마나 지났는지 표시합니다. 막대가 세로선보다 앞서 있으면 시간보다 빠르게 쓰고 있다는 뜻입니다.',
    'how.p2.t': '예측은 단순한 산수입니다.', 'how.p2.d': '이 창에서 지금까지의 평균 속도를 재설정 시점까지 늘려 볼 뿐입니다. 기록을 모을 필요 없이 첫 새로 고침부터 작동합니다.',
    'how.p3.t': '필요할 때만 알립니다.', 'how.p3.d': '충분할 때는 재설정 시점의 예상치만, 부족할 때는 언제 소진되는지 빨간 한 줄로 알려 줍니다.',
    'term.resets': '재설정', 'term.today': '오늘 10:30', 'term.sunday': '일요일 3:00',
    'term.empty': '약 1시간 29분 후 소진 · 재설정 1시간 37분 전', 'term.bythen': '· 그때 약 31%',
    'features.label': '기능',
    'features.title': '/usage가 알려 주는 모든 것을 터미널 없이.',
    'f1.k': '메뉴 막대', 'f1.t': '항상 보이는 한도', 'f1.d': '메뉴 막대에 "5h 41% 주 62%". 간단하게 "41% 62%"만 표시할 수도 있습니다.',
    'f2.k': '한도', 'f2.t': 'Claude와 Codex를 나란히', 'f2.d': 'Claude의 모든 한도와, Codex를 쓴다면 그 5시간·주간 한도를 한 줄씩, 재설정 시간과 카운트다운과 함께.',
    'f3.k': '예측', 'f3.t': '다 쓰기 전에 경고', 'f3.d': '재설정 시점에 얼마나 쓸지, 이 속도라면 언제 소진될지 알려 줍니다.',
    'f4.k': '오늘', 'f4.t': '속도와 비용', 'f4.d': '오늘의 출력·입력 토큰, 요청 수, 평균과 최고 tok/s, API 가격으로 환산한 금액.',
    'f5.k': '기록', 'f5.t': '사용량 기록 창', 'f5.d': '소스별 일별 출력과 비용, 속도 추이, 주간 한도 추이, 모든 세션을 보고 CSV로 내보낼 수 있습니다. 일별 합계는 Mac에 남아 Claude Code가 오래된 로그를 지워도 그대로입니다.',
    'f6.k': '알림', 'f6.t': '알림과 4개 언어', 'f6.d': '80, 90, 95%에 닿을 때와 한도가 돌아왔을 때 알려 줍니다. English, 简体中文, 日本語, 한국어. 필요한 지역을 위한 HTTP 프록시.',
    'shots.usage': '패널', 'shots.sessions': '세션', 'shots.stats': '통계', 'shots.settings': '설정',
    'cloud.label': 'Quotlet Cloud', 'cloud.soon': '0.5 새 기능',
    'cloud.title': '메뉴 막대는 작게. 자세한 내용은 웹에서.',
    'cloud.lead': '로그인하고 app.quotlet.com을 열면 전체가 보입니다. 모든 Mac의 한도, 세션 기록, 실행 중이거나 응답을 기다리는 세션, 토큰 추이. 휴대폰에서도.',
    'cloud.p1.t': '선택 사항, 기본값은 꺼짐.', 'cloud.p1.d': '로그인하지 않으면 Quotlet은 Anthropic 외에는 어디에도 연결하지 않습니다. 그 Mac에서 로그인한 뒤에야 동기화가 시작됩니다.',
    'cloud.p2.t': '대화가 아니라 숫자만.', 'cloud.p2.d': '한도, 토큰 수, 세션 상태를 보냅니다. 프롬프트와 코드는 Mac 밖으로 나가지 않으며, 세션 제목 전송도 끌 수 있습니다.',
    'cloud.p3.t': '언제든 멈출 수 있습니다.', 'cloud.p3.d': 'Mac에서 로그아웃하거나 웹에서 그 Mac을 제거하면 더 이상 아무것도 보내지 않습니다.',
    'trust.label': '개인정보',
    'trust.title': '믿지 말고 확인하세요.',
    'trust.lead': '계정도, 원격 측정도, 붙여넣을 것도 없습니다. 각 항목마다 직접 확인하는 방법을 붙였습니다.',
    't1.t': 'Claude Code의 기존 로그인을 사용', 't1.d': '시스템 security 명령으로 키체인에서 Claude Code 토큰을 읽기만 합니다. 갱신·변경·저장하지 않으며 Anthropic에만 보냅니다.',
    't2.t': '접속 주소는 하나', 't2.d': '사용량을 조회하는 api.anthropic.com뿐입니다. Cloud에 로그인해야 app.quotlet.com이 추가됩니다.',
    't3.t': '로그는 읽기만', 't3.d': '세션과 토큰은 Claude Code와 Codex가 원래 Mac에 남기는 로그에서 읽기만 하고 쓰지 않습니다.',
    't4.t': '서명 및 공증', 't4.d': '모든 릴리스는 Developer ID로 서명되고 Apple의 공증을 받습니다.',
    't5.t': '오픈 소스', 't5.d': 'MIT 라이선스. 모든 코드가 GitHub에 있으며 명령 하나로 직접 빌드할 수 있습니다.',
    'install.label': '설치', 'install.title': '세 가지 방법.',
    'install.dmg.t': '다운로드', 'install.dmg.d': 'DMG를 열고 Quotlet을 응용 프로그램 폴더로 드래그하세요. 서명 및 공증되어 더블 클릭으로 열립니다.',
    'install.src.t': '직접 빌드', 'install.src.d': 'Xcode 명령줄 도구가 필요합니다.',
    'install.r1': 'macOS 14 Sonoma 이상, Apple 실리콘 또는 Intel',
    'install.r2': 'Claude Code를 설치하고 Claude Pro 또는 Max 요금제로 로그인',
    'install.r3': '숫자가 보이지 않나요? 아이콘이 숨겨졌을 수 있습니다. ⌘를 누른 채 원하는 위치로 드래그하세요.',
    'foot.disclaimer': 'Quotlet은 독립적인 오픈 소스 프로젝트로, Anthropic 제품이 아니며 Anthropic과 관련이 없습니다. "Claude"는 Anthropic의 상표입니다.',
    'foot.renamed': 'Quotlet은 0.5 버전 이전에는 Quotabar라는 이름이었습니다.',
    'foot.issues': '문제 신고',
    'shots.history': '사용량 기록',
  },
}

const HTML_LANG = { en: 'en', zh: 'zh-CN', ja: 'ja', ko: 'ko' }

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

// 「原理」一节里用等宽字符画的额度条。左边的 5h / week / opus 不翻译（翻成中日韩字符等宽会对不齐），说明行跟着语言走。
function termHTML(t) {
  const e = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;')
  const resets = (when) => t['term.resets'] === 'Resets'
    ? `<span class="dim">Resets</span> <span class="time">${e(when)}</span>`
    : `<span class="time">${e(when)}</span> <span class="dim">${e(t['term.resets'])}</span>`
  return [
    '<span class="dim">5h  </span> <span class="ok">██████████</span><span class="tick">│</span><span class="ok">█</span><span class="track">░░░░░░░</span>  <b>56%</b>   <span class="dim">3h 6m</span>',
    '      ' + resets(t['term.today']),
    '      <span class="bad">' + e(t['term.empty']) + '</span>',
    '',
    '<span class="dim">week</span> <span class="bad">█████████</span><span class="tick">│</span><span class="bad">██████</span><span class="track">░░░</span>  <b>90%</b>   <span class="dim">3d 19h</span>',
    '      ' + resets(t['term.sunday']),
    '',
    '<span class="dim">opus</span> <span class="ok">███</span><span class="track">░░░░░░</span><span class="tick">│</span><span class="track">░░░░░░░░</span>  <b>18%</b>   <span class="dim">3d 19h</span>',
    '      ' + resets(t['term.sunday']) + ' <span class="dim">' + e(t['term.bythen']) + '</span>',
  ].join('\n')
}

function apply(lang) {
  const t = T[lang]
  document.documentElement.lang = HTML_LANG[lang]
  document.title = t['meta.title']
  document.querySelectorAll('[data-i18n]').forEach((el) => { const v = t[el.dataset.i18n]; if (v) el.textContent = v })
  // 标题里只有 <em>，文案是自己写的常量
  document.querySelectorAll('[data-i18n-html]').forEach((el) => { const v = t[el.dataset.i18nHtml]; if (v) el.innerHTML = v })
  document.querySelectorAll('[data-shot]').forEach((img) => {
    img.src = `/assets/${img.dataset.shot}-${lang}.webp`
    img.alt = t['shots.' + img.dataset.shot]
  })
  const panel = document.getElementById('panel')
  panel.src = `/assets/panel-${lang}.webp`
  panel.alt = t['panel.alt']
  document.querySelector('.term').innerHTML = termHTML(t)
  document.getElementById('lang').value = lang
}

let lang = pickLang()
apply(lang)

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
