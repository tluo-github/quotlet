// 门户网站：语言切换 + 复制命令。文案都在这里，HTML 里的英文是默认值（也给搜索引擎看）。
'use strict'

const T = {
  en: {
    'nav.features': 'Features', 'nav.install': 'Install', 'nav.source': 'Source', 'nav.language': 'Language',
    'cta.short': 'Download', 'cta.download': 'Download for macOS', 'cta.copy': 'Copy', 'cta.copied': 'Copied',
    'hero.eyebrow': 'For Claude Pro & Max',
    'hero.title': 'Your Claude limits,<br>always in the menu bar.',
    'hero.lead': "See how much of the 5-hour window and weekly limits you've used and when they reset — the same numbers as /usage in Claude Code. Plus your recent sessions and token stats.",
    'hero.fine': 'Free and open source · macOS 14+ · Apple silicon & Intel',
    'features.title': 'Everything you check /usage for, without opening a terminal',
    'f1.t': 'Always visible', 'f1.d': 'The menu bar shows "5h 41% Wk 62%" — the 5-hour window and this week at a glance. A compact "41% 62%" style is available too.',
    'f2.t': 'Every limit, every reset', 'f2.d': 'Each limit on your plan — 5-hour, weekly, per-model weekly — with reset time, countdown and a time-progress marker. Green when fine, amber and red as you get close.',
    'f3.t': 'Notifications', 'f3.d': "Get notified when a limit nears 80, 90 or 95%, when it runs out, and when it's available again after the reset.",
    'f4.t': 'Claude Code sessions', 'f4.d': 'Recent sessions over 24 hours, 7 or 30 days, with a bar showing which ones used the most. Right-click to copy the claude --resume command.',
    'f5.t': 'Token stats', 'f5.d': 'Total tokens, tokens per day and per project, counted from your local Claude Code logs — each reply counted once.',
    'f6.t': 'Four languages, proxy support', 'f6.d': 'English, 简体中文, 日本語 and 한국어; light, dark or auto. Adjustable refresh rate and an HTTP proxy for regions that need one.',
    'shots.title': 'Screenshots', 'shots.usage': 'Usage', 'shots.sessions': 'Sessions', 'shots.stats': 'Stats', 'shots.settings': 'Settings',
    'how.title': 'Local first. Nothing leaves your Mac unless you sign in.',
    'how.d1': "Limits come from the same Anthropic endpoint that /usage uses. Quotabar reads Claude Code's existing login from your keychain with the system security tool — it never refreshes or changes it.",
    'how.d2': "Sessions and tokens are read from Claude Code's logs in ~/.claude/projects on this Mac. The only network request is asking Anthropic for your usage.",
    'cloud.tag': 'Coming soon', 'cloud.title': 'Quotabar Cloud',
    'cloud.d': 'Optional sign-in to see your limits and which sessions are running, waiting for approval or done — on the web and on your phone. Off by default.',
    'install.title': 'Install',
    'install.dmg.t': 'Download', 'install.dmg.d': 'Open the DMG and drag Quotabar into Applications. The app is signed and notarized by Apple.',
    'install.r1': 'macOS 14 Sonoma or later, Apple silicon or Intel',
    'install.r2': 'Claude Code installed and signed in with a Claude Pro or Max plan',
    'install.r3': "Can't see the numbers? macOS may have tucked the icon away. Hold ⌘ and drag it where you want it.",
    'foot.disclaimer': 'Quotabar is an independent open-source project. It is not an Anthropic product and is not affiliated with Anthropic. "Claude" is a trademark of Anthropic.',
    'meta.title': 'Quotabar — Claude usage limits in your Mac menu bar',
  },
  zh: {
    'nav.features': '功能', 'nav.install': '安装', 'nav.source': '源码', 'nav.language': '语言',
    'cta.short': '下载', 'cta.download': '下载 macOS 版', 'cta.copy': '复制', 'cta.copied': '已复制',
    'hero.eyebrow': '适用于 Claude Pro 和 Max',
    'hero.title': 'Claude 额度，<br>一直在状态栏里。',
    'hero.lead': '5 小时窗口和每周额度各用了多少、什么时候重置，和 Claude Code 里的 /usage 一样。点开还能看最近的会话和 token 统计。',
    'hero.fine': '免费开源 · macOS 14+ · Apple 芯片和 Intel',
    'features.title': '不用开终端敲 /usage，额度一眼就看到',
    'f1.t': '状态栏一眼看到', 'f1.d': '状态栏显示「5h 41% 周 62%」，5 小时窗口和本周额度的已用比例。也可以只显示「41% 62%」。',
    'f2.t': '每条额度和重置时间', 'f2.d': '套餐里的每一条额度：5 小时、每周、按模型的每周额度，带重置时间、倒计时和时间进度刻度。正常是绿色，快用完变琥珀色、红色。',
    'f3.t': '通知提醒', 'f3.d': '额度快到上限（80%、90% 或 95%）、已用完、重置后恢复时提醒你。',
    'f4.t': 'Claude Code 会话', 'f4.d': '近 24 小时、7 天、30 天的会话，每行一条比例条，看出哪个会话用得多。右键可以复制 claude --resume 恢复命令。',
    'f5.t': 'token 统计', 'f5.d': '总 token、每天 token、按项目统计，来自本机 Claude Code 日志，同一条回复只算一次。',
    'f6.t': '四种语言，支持代理', 'f6.d': '简体中文、English、日本語、한국어；浅色、深色、自动。刷新频率可调，需要时可以走 HTTP 代理。',
    'shots.title': '截图', 'shots.usage': '用量', 'shots.sessions': '会话', 'shots.stats': '统计', 'shots.settings': '设置',
    'how.title': '数据都在本机，不登录就不会离开你的 Mac。',
    'how.d1': '额度来自 /usage 用的同一个 Anthropic 接口。Quotabar 用系统自带的 security 命令读取 Claude Code 存在钥匙串里的登录信息，不会刷新或改动它。',
    'how.d2': '会话和 token 读的是本机 ~/.claude/projects 下的 Claude Code 日志。唯一的网络请求就是向 Anthropic 查询用量。',
    'cloud.tag': '即将推出', 'cloud.title': 'Quotabar Cloud',
    'cloud.d': '可选登录后，在网站和手机上查看额度，以及哪些会话在执行中、等你授权、已完成。默认关闭。',
    'install.title': '安装',
    'install.dmg.t': '下载', 'install.dmg.d': '打开 DMG，把 Quotabar 拖进“应用程序”。app 已经过苹果签名和公证，双击就能打开。',
    'install.r1': 'macOS 14 Sonoma 或更新，Apple 芯片和 Intel 都支持',
    'install.r2': '已安装 Claude Code，并用 Claude Pro 或 Max 套餐登录',
    'install.r3': '状态栏上看不到数字？可能被系统收进了折叠区。按住 ⌘ 把它拖到想要的位置。',
    'foot.disclaimer': 'Quotabar 是独立的开源项目，不是 Anthropic 官方产品，与 Anthropic 没有关联。“Claude”是 Anthropic 的商标。',
    'meta.title': 'Quotabar — 在 Mac 状态栏查看 Claude 额度',
  },
  ja: {
    'nav.features': '機能', 'nav.install': 'インストール', 'nav.source': 'ソース', 'nav.language': '言語',
    'cta.short': 'ダウンロード', 'cta.download': 'macOS 版をダウンロード', 'cta.copy': 'コピー', 'cta.copied': 'コピーしました',
    'hero.eyebrow': 'Claude Pro・Max 向け',
    'hero.title': 'Claude の使用上限を、<br>いつもメニューバーに。',
    'hero.lead': '5 時間枠と週間上限をどれだけ使ったか、いつリセットされるか。Claude Code の /usage と同じ数字です。最近のセッションやトークン統計も見られます。',
    'hero.fine': '無料・オープンソース · macOS 14 以降 · Apple シリコンと Intel',
    'features.title': 'ターミナルで /usage を打たなくても、ひと目でわかる',
    'f1.t': 'いつでも見える', 'f1.d': 'メニューバーに「5h 41% 週 62%」と表示。5 時間枠と今週の使用率がひと目でわかります。「41% 62%」だけのコンパクト表示も選べます。',
    'f2.t': 'すべての上限とリセット時刻', 'f2.d': 'プランの各上限（5 時間・週間・モデル別の週間）を、リセット時刻、カウントダウン、時間経過の目盛り付きで表示。余裕があれば緑、近づくと琥珀色・赤に。',
    'f3.t': '通知', 'f3.d': '上限が 80・90・95% に近づいたとき、使い切ったとき、リセット後に使えるようになったときにお知らせします。',
    'f4.t': 'Claude Code のセッション', 'f4.d': '24 時間・7 日・30 日のセッションを一覧表示。バーでどれを多く使ったかがわかります。右クリックで claude --resume コマンドをコピー。',
    'f5.t': 'トークン統計', 'f5.d': '合計トークン、日別・プロジェクト別のトークン。この Mac の Claude Code ログから集計し、同じ返信は 1 回だけ数えます。',
    'f6.t': '4 言語・プロキシ対応', 'f6.d': 'English、简体中文、日本語、한국어。ライト・ダーク・自動。更新間隔の変更や HTTP プロキシにも対応。',
    'shots.title': 'スクリーンショット', 'shots.usage': '使用量', 'shots.sessions': 'セッション', 'shots.stats': '統計', 'shots.settings': '設定',
    'how.title': 'データはローカル。ログインしない限り Mac の外には出ません。',
    'how.d1': '上限は /usage と同じ Anthropic のエンドポイントから取得します。Claude Code のログイン情報はシステムの security コマンドでキーチェーンから読み取るだけで、更新や変更はしません。',
    'how.d2': 'セッションとトークンはこの Mac の ~/.claude/projects にある Claude Code のログから読み取ります。ネットワーク通信は Anthropic への使用量の問い合わせだけです。',
    'cloud.tag': '近日公開', 'cloud.title': 'Quotabar Cloud',
    'cloud.d': '任意でログインすると、Web やスマートフォンで上限と、各セッションが実行中・承認待ち・完了のどれかを確認できます。初期設定はオフです。',
    'install.title': 'インストール',
    'install.dmg.t': 'ダウンロード', 'install.dmg.d': 'DMG を開いて Quotabar をアプリケーションフォルダにドラッグ。Apple の署名と公証済みです。',
    'install.r1': 'macOS 14 Sonoma 以降、Apple シリコンまたは Intel',
    'install.r2': 'Claude Code をインストールし、Claude Pro または Max プランでログイン済み',
    'install.r3': '数字が見えない場合は、アイコンが隠れているかもしれません。⌘ を押しながら好きな位置にドラッグしてください。',
    'foot.disclaimer': 'Quotabar は独立したオープンソースプロジェクトであり、Anthropic の製品ではなく、Anthropic とは関係ありません。「Claude」は Anthropic の商標です。',
    'meta.title': 'Quotabar — Claude の使用上限を Mac のメニューバーに',
  },
  ko: {
    'nav.features': '기능', 'nav.install': '설치', 'nav.source': '소스', 'nav.language': '언어',
    'cta.short': '다운로드', 'cta.download': 'macOS용 다운로드', 'cta.copy': '복사', 'cta.copied': '복사됨',
    'hero.eyebrow': 'Claude Pro·Max용',
    'hero.title': 'Claude 사용 한도를<br>항상 메뉴 막대에서.',
    'hero.lead': '5시간 창과 주간 한도를 얼마나 썼는지, 언제 재설정되는지 보여 줍니다. Claude Code의 /usage와 같은 숫자입니다. 최근 세션과 토큰 통계도 볼 수 있습니다.',
    'hero.fine': '무료 오픈 소스 · macOS 14 이상 · Apple 실리콘 및 Intel',
    'features.title': '터미널에서 /usage를 입력하지 않아도 한눈에',
    'f1.t': '항상 보이는 한도', 'f1.d': '메뉴 막대에 "5h 41% 주 62%"로 5시간 창과 이번 주 사용률을 한눈에 보여 줍니다. "41% 62%"만 표시하는 간단한 형식도 있습니다.',
    'f2.t': '모든 한도와 재설정 시간', 'f2.d': '요금제의 모든 한도(5시간, 주간, 모델별 주간)를 재설정 시간, 카운트다운, 시간 진행 표시와 함께 보여 줍니다. 여유가 있으면 초록색, 가까워지면 호박색과 빨간색.',
    'f3.t': '알림', 'f3.d': '한도가 80, 90, 95%에 가까워질 때, 다 썼을 때, 재설정 후 다시 쓸 수 있을 때 알려 줍니다.',
    'f4.t': 'Claude Code 세션', 'f4.d': '최근 24시간, 7일, 30일의 세션과 어떤 세션을 많이 썼는지 보여 주는 막대. 오른쪽 클릭으로 claude --resume 명령을 복사할 수 있습니다.',
    'f5.t': '토큰 통계', 'f5.d': '전체 토큰, 일별·프로젝트별 토큰. 이 Mac의 Claude Code 로그에서 집계하며 같은 응답은 한 번만 셉니다.',
    'f6.t': '4개 언어, 프록시 지원', 'f6.d': 'English, 简体中文, 日本語, 한국어. 라이트, 다크, 자동. 새로 고침 간격 조절과 HTTP 프록시를 지원합니다.',
    'shots.title': '스크린샷', 'shots.usage': '사용량', 'shots.sessions': '세션', 'shots.stats': '통계', 'shots.settings': '설정',
    'how.title': '데이터는 로컬에. 로그인하지 않으면 Mac 밖으로 나가지 않습니다.',
    'how.d1': '한도는 /usage가 쓰는 것과 같은 Anthropic 엔드포인트에서 가져옵니다. Claude Code의 로그인 정보는 시스템 security 명령으로 키체인에서 읽기만 하고, 갱신하거나 바꾸지 않습니다.',
    'how.d2': '세션과 토큰은 이 Mac의 ~/.claude/projects에 있는 Claude Code 로그에서 읽습니다. 네트워크 요청은 Anthropic에 사용량을 조회하는 것뿐입니다.',
    'cloud.tag': '출시 예정', 'cloud.title': 'Quotabar Cloud',
    'cloud.d': '선택적으로 로그인하면 웹과 휴대폰에서 한도와, 어떤 세션이 실행 중·승인 대기·완료인지 확인할 수 있습니다. 기본값은 꺼짐입니다.',
    'install.title': '설치',
    'install.dmg.t': '다운로드', 'install.dmg.d': 'DMG를 열고 Quotabar를 응용 프로그램 폴더로 드래그하세요. Apple의 서명과 공증을 받았습니다.',
    'install.r1': 'macOS 14 Sonoma 이상, Apple 실리콘 또는 Intel',
    'install.r2': 'Claude Code를 설치하고 Claude Pro 또는 Max 요금제로 로그인',
    'install.r3': '숫자가 보이지 않나요? 아이콘이 숨겨졌을 수 있습니다. ⌘를 누른 채 원하는 위치로 드래그하세요.',
    'foot.disclaimer': 'Quotabar는 독립적인 오픈 소스 프로젝트로, Anthropic 제품이 아니며 Anthropic과 관련이 없습니다. "Claude"는 Anthropic의 상표입니다.',
    'meta.title': 'Quotabar — Claude 사용 한도를 Mac 메뉴 막대에서',
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

function apply(lang) {
  const t = T[lang]
  document.documentElement.lang = HTML_LANG[lang]
  document.title = t['meta.title']
  document.querySelectorAll('[data-i18n]').forEach((e) => { const v = t[e.dataset.i18n]; if (v) e.textContent = v })
  // 标题里只有 <br>，文案是自己写的常量
  document.querySelectorAll('[data-i18n-html]').forEach((e) => { const v = t[e.dataset.i18nHtml]; if (v) e.innerHTML = v })
  document.querySelectorAll('[data-shot]').forEach((img) => {
    img.src = `/assets/${img.dataset.shot}-${lang}.webp`
    img.alt = t['shots.' + img.dataset.shot]
  })
  const video = document.getElementById('demo')
  const src = `/assets/demo-${lang}.mp4`
  if (!video.currentSrc.endsWith(src)) {
    video.poster = `/assets/usage-${lang}.webp`
    video.querySelector('source').src = src
    video.load()
    video.play().catch(() => {})
  }
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

// 不想看动画的人：停在第一帧
if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const v = document.getElementById('demo'); v.removeAttribute('autoplay'); v.pause()
}
