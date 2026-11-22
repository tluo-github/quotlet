import AppKit
import Charts
import SwiftUI

// MARK: - 主面板

struct ContentView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var cloud = Cloud.shared
    @State private var tab: Tab
    @State private var showSettings: Bool
    /// 整个面板的固定高度。高度若在面板打开后再变，macOS 会固定窗口底边，顶边就会离开状态栏出现空隙，
    /// 默认留足三个来源的额度和今日汇总；小屏幕限制在可用高度内，溢出内容仍可滚动。
    static let panelHeight: CGFloat = min(860, (NSScreen.main?.visibleFrame.height ?? 900) - 24)

    init(startInSettings: Bool = false, initialTab: Tab = .usage) {
        _showSettings = State(initialValue: startInSettings)
        _tab = State(initialValue: initialTab)
    }

    enum Tab: String, CaseIterable {
        case usage, sessions, stats, remote

        var title: String {
            switch self {
            case .usage: return L("额度", "Quotas", ja: "使用枠", ko: "한도")
            case .sessions: return L("会话", "Sessions", ja: "セッション", ko: "세션")
            case .stats: return L("统计", "Stats", ja: "統計", ko: "통계")
            case .remote: return L("远程指令", "Remote", ja: "リモート", ko: "원격")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView { showSettings = false }
                    .id(store.language)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Hairline()
                ChipPicker(options: Tab.allCases.map { ($0, $0.title) }, selection: $tab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let err = cloud.errorMessage {
                                Banner(text: L("登录失败：", "Sign-in failed: ", ja: "ログインに失敗しました：", ko: "로그인 실패: ") + err,
                                       actionTitle: L("重试", "Try again", ja: "再試行", ko: "다시 시도")) { cloud.signIn() }
                            }
                            switch tab {
                            case .usage: UsageTab(now: ctx.date, openSettings: { showSettings = true })
                            case .sessions: SessionsTab(now: ctx.date)
                            case .stats: StatsTab(now: ctx.date)
                            case .remote: RemoteTab(openSettings: { showSettings = true })
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .compatScrollBounceBasedOnSize()
                    .id(tab)
                }
                .frame(maxHeight: .infinity)
                .id(store.language)   // 切换语言后整页重建，所有文字立即换成新语言

                Hairline()
                footer
            }
        }
        .frame(width: 360, height: Self.panelHeight)
        .background(Theme.surface)
        .onAppear { store.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Quotlet").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 4)
            Menu {
                Picker(L("状态栏来源", "Menu bar source", ja: "メニューバーのソース", ko: "메뉴 막대 소스"), selection: $store.menuBarSource) {
                    Text("Claude").tag(Source.claude)
                    Text("Codex").tag(Source.codex)
                    Text("Gemini").tag(Source.gemini)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(store.menuBarSource == .claude ? "Claude" : store.menuBarSource.title)
                        .font(.system(size: 10.5, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .semibold))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8).padding(.vertical, 3.5)
                .background(Capsule().fill(Theme.hover))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("选择顶部菜单栏显示的额度来源",
                    "Choose the quota source shown in the menu bar",
                    ja: "メニューバーに表示する使用枠ソースを選択",
                    ko: "메뉴 막대에 표시할 한도 소스 선택"))
            AccountButton(cloud: cloud)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            // 更新时间放底栏：标题栏不挤，也不会和蓝色的重置时间混淆
            if let t = store.lastUpdated {
                Text(L("\(Fmt.time(t)) 更新", "Updated \(Fmt.time(t))", ja: "\(Fmt.time(t)) 更新", ko: "\(Fmt.time(t)) 업데이트"))
                    .font(Theme.caption).foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
            // 刷新紧跟在更新时间后面：“什么时候更新的”和“现在更新”是一件事
            if store.isLoading || store.isScanning {
                ProgressView().controlSize(.mini).frame(width: 24, height: 24)
            } else {
                IconButton(symbol: "arrow.clockwise", help: L("刷新（⌘R）", "Refresh (⌘R)", ja: "更新（⌘R）", ko: "새로 고침(⌘R)")) { store.refreshAll() }
                    .keyboardShortcut("r")
            }
            Spacer()
            FooterButton(title: L("设置", "Settings", ja: "設定", ko: "설정")) { showSettings = true }
                .keyboardShortcut(",")
            FooterButton(title: L("退出", "Quit", ja: "終了", ko: "종료")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// 底栏的文字按钮
struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 右上角的账号入口。没登录：「登录」小按钮；登录后：首字母头像 + 用户名，点开菜单（账号、在网页上查看、退出登录）
struct AccountButton: View {
    @ObservedObject var cloud: Cloud
    @State private var hovering = false
    @State private var showCard = false

    var body: some View {
        if cloud.isBusy {
            ProgressView().controlSize(.mini).frame(width: 24, height: 24)
        } else if let user = cloud.user {
            // 不加 fixedSize：空间不够时名字可以被压缩、显示省略号，不会把顶部撑出面板
            Button { showCard.toggle() } label: { signedInLabel(user) }
                .buttonStyle(.plain)
                .help(user.email ?? "Quotlet Cloud")
                .popover(isPresented: $showCard, arrowEdge: .bottom) { accountCard(user) }
        } else {
            Button { cloud.signIn() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle").font(.system(size: 12, weight: .medium))
                    Text(L("登录", "Sign in", ja: "ログイン", ko: "로그인"))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(hovering ? Theme.hover : .clear))
                .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .fixedSize()
            .help(L("登录 Quotlet Cloud，在网站和手机上查看额度和会话",
                    "Sign in to Quotlet Cloud to see usage and sessions on the web and your phone",
                    ja: "Quotlet Cloud にログインして、Web やスマートフォンで使用量とセッションを確認",
                    ko: "Quotlet Cloud에 로그인해 웹과 휴대폰에서 사용량과 세션 보기"))
        }
    }

    private func displayName(_ user: CloudUser) -> String { user.name ?? user.email ?? "Cloud" }

    private func avatar(_ user: CloudUser, size: CGFloat) -> some View {
        Text(String(displayName(user).prefix(1)).uppercased())
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(Theme.surface)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.ink))
    }

    /// 点开头像后的小卡片：账号信息 + 在网页上查看 + 退出登录
    private func accountCard(_ user: CloudUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                avatar(user, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(user)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let email = user.email, email != displayName(user) {
                        Text(email).font(Theme.caption).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 8) {
                ChipButton(title: L("在网页上查看", "Open on the web", ja: "Web で開く", ko: "웹에서 열기")) {
                    showCard = false
                    cloud.openWebsite()
                }
                ChipButton(title: L("退出登录", "Sign out", ja: "ログアウト", ko: "로그아웃")) {
                    showCard = false
                    cloud.signOut()
                }
            }
        }
        .padding(14)
        .frame(minWidth: 220, alignment: .leading)
    }

    private func signedInLabel(_ user: CloudUser) -> some View {
        let name = displayName(user)
        return HStack(spacing: 5) {
            avatar(user, size: 18)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                // 按名字实际宽度，最多 90pt；顶部挤的时候（英文长标签）还能再压缩
                .frame(maxWidth: min(ceil((name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width) + 1, 90),
                       alignment: .leading)
                .layoutPriority(-1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.text2)
        }
        .padding(.leading, 3).padding(.trailing, 6).padding(.vertical, 3)
        .background(Capsule().fill(hovering ? Theme.hover : .clear))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }
}

// MARK: - 用量

struct UsageTab: View {
    @EnvironmentObject var store: Store
    let now: Date
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.needsProxyHint, store.usage == nil || store.lastUpdated.map({ now.timeIntervalSince($0) > 600 }) == true {
                // 网络不通 / 被地区拒绝：提示去设置代理，带一个直达按钮
                Banner(text: L("连不上 Anthropic。如果你需要代理才能访问，请在设置里开启网络代理。",
                               "Can't reach Anthropic. If you need a proxy to connect, turn it on in Settings.",
                               ja: "Anthropic に接続できません。接続にプロキシが必要な場合は、設定でネットワークプロキシをオンにしてください。",
                               ko: "Anthropic에 연결할 수 없습니다. 프록시가 필요하다면 설정에서 네트워크 프록시를 켜세요."),
                       actionTitle: L("去设置代理", "Set up proxy", ja: "プロキシを設定", ko: "프록시 설정"),
                       action: openSettings)
            } else if !store.needsCredentialAuthorization, let err = store.errorMessage {
                if store.usage != nil, let t = store.lastUpdated {
                    // 数据不到 10 分钟就不打扰；超过 10 分钟才提示数据过时
                    if now.timeIntervalSince(t) > 600 {
                    // 有旧数据就继续显示，只提示一行
                    Banner(text: L("数据停在 \(Fmt.time(t))，稍后自动重试。", "Showing data from \(Fmt.time(t)); will retry shortly.", ja: "\(Fmt.time(t)) 時点のデータを表示中。しばらくして再試行します。", ko: "\(Fmt.time(t)) 기준 데이터를 표시 중입니다. 잠시 후 다시 시도합니다.") + " " + err)
                    }
                } else {
                    Banner(text: err)
                }
            }

            let claudeUsage = store.displayedClaudeUsage(now: Date())
            let claude = claudeUsage?.limits ?? []
            let codex = store.codexLimits(now: now)
            let gemini = store.geminiLimits(now: now)
            if let advice = Advice.make(claude: claude, codex: codex, gemini: gemini, now: now) {
                AdviceCard(advice: advice)
            }

            if let u = claudeUsage, let shared = store.sharedClaude {
                ProviderGroup(name: "Claude", plan: u.plan.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() },
                              source: .claude, limits: u.limits, now: now, sharedFrom: shared)
            } else if !store.hasClaudeQuotaSource {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Theme.text2)
                    Text(L("本地统计模式", "Local stats mode", ja: "ローカル集計モード", ko: "로컬 통계 모드")).font(Theme.bodyMedium)
                    Spacer()
                    ChipButton(title: L("设置", "Settings", ja: "設定", ko: "설정"), action: openSettings)
                }
                .help(L("只读本机日志，不读取 Claude 登录凭证。可在设置中开启免钥匙串 Claude 额度读取。", "Reads local logs without accessing your Claude login. Enable Keychain-free Claude quota in Settings.", ja: "Claude のログイン情報を読まずにローカルログを集計します。キーチェーン不要の Claude 使用枠は設定で有効にできます。", ko: "Claude 로그인 정보에 접근하지 않고 로컬 로그만 읽습니다. 키체인 없는 Claude 한도 조회는 설정에서 켤 수 있습니다."))
            } else if let u = claudeUsage {
                ProviderGroup(name: "Claude", plan: u.plan.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() },
                              source: .claude, limits: u.limits, now: now)
            } else if store.isLoading {
                LoadingState(text: L("正在获取用量…", "Loading usage…", ja: "使用量を取得中…", ko: "사용량을 불러오는 중…"))
            } else if store.claudeStatusLineEnabled {
                Text(L("免钥匙串额度已开启。在 Claude Code 中发一条消息后即自动更新 5 小时和每周额度。",
                       "Keychain-free quota is on. Send a message in Claude Code to populate 5-hour and weekly limits.",
                       ja: "キーチェーン不要の使用枠取得がオンです。Claude Code でメッセージを 1 件送ると 5 時間・週間の使用枠が自動更新されます。",
                       ko: "키체인 없는 한도 조회가 켜져 있습니다. Claude Code에서 메시지를 하나 보내면 5시간 및 주간 한도가 자동으로 업데이트됩니다."))
                    .font(Theme.caption).foregroundStyle(Theme.text2)
            }

            if !codex.isEmpty {
                if !claude.isEmpty { Hairline() }
                ProviderGroup(name: "Codex", plan: store.codexPlan, source: .codex, limits: codex, now: now, sharedFrom: store.sharedCodex)
            } else if store.menuBarSource == .codex {
                Text(L("还没有 Codex 额度记录。使用一次 Codex 后会自动更新。",
                       "No Codex quota recorded yet. It updates after you use Codex.",
                       ja: "Codex の使用枠は未記録です。使用すると自動更新されます。",
                       ko: "아직 Codex 한도 기록이 없습니다. Codex를 사용하면 자동으로 업데이트됩니다."))
                    .font(Theme.caption).foregroundStyle(Theme.text2)
            }

            if !gemini.isEmpty {
                if !claude.isEmpty || !codex.isEmpty { Hairline() }
                ProviderGroup(name: "Gemini", plan: store.geminiPlan, source: .gemini, limits: gemini, now: now, sharedFrom: store.sharedGemini)
            } else if store.menuBarSource == .gemini {
                Text(L("还没有 Gemini 额度记录。打开 Antigravity 后会自动更新。",
                       "No Gemini quota recorded yet. It updates when Antigravity is open.",
                       ja: "Gemini の使用枠は未記録です。Antigravity を開くと自動更新されます。",
                       ko: "아직 Gemini 한도 기록이 없습니다. Antigravity를 열면 자동으로 업데이트됩니다."))
                    .font(Theme.caption).foregroundStyle(Theme.text2)
            }

            if let local = store.local {
                Hairline()
                ThroughputView(snapshot: local, isLoading: false, now: now)
                Hairline()
                TodayBlock(local: local, now: now)
            }

        }
    }
}

/// 来源标题与额度分层；长范围名不再占用进度条的水平空间。
struct ProviderGroup: View {
    let name: String
    let plan: String?
    let source: Source
    let limits: [LimitItem]
    let now: Date
    /// 非 nil 表示额度来自另一台 Mac 上报的云端快照
    var sharedFrom: SharedQuota? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                brandIcon.frame(width: 16, height: 16).accessibilityHidden(true)
                Text(name).font(.system(size: 13, weight: .semibold))
                if let plan {
                    Text(plan).font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 8)
                if let sharedFrom {
                    Label(sharedFrom.device_name ?? "Mac", systemImage: "icloud")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.text2).lineLimit(1)
                        .help(L("来自 \(sharedFrom.device_name ?? "Mac") 上报的额度（\(Fmt.time(sharedFrom.observedAt)) 更新）",
                                "Quota reported by \(sharedFrom.device_name ?? "Mac") (updated \(Fmt.time(sharedFrom.observedAt)))",
                                ja: "\(sharedFrom.device_name ?? "Mac") が報告した使用枠（\(Fmt.time(sharedFrom.observedAt)) 更新）",
                                ko: "\(sharedFrom.device_name ?? "Mac")에서 보고한 한도 (\(Fmt.time(sharedFrom.observedAt)) 업데이트)"))
                } else {
                    Text(L("已用", "Used", ja: "使用済み", ko: "사용량"))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.text2)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(limits) { item in
                    LimitRow(item: item, now: now)
                }
            }
        }
    }

    @ViewBuilder private var brandIcon: some View {
        let url = Bundle.main.url(forResource: source.rawValue, withExtension: "png")
            ?? (Bundle.main.bundleURL.pathExtension == "app" ? nil : Bundle.module.url(forResource: source.rawValue, withExtension: "png"))
        if let url, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: source == .claude ? "sun.max.fill" : source == .gemini ? "sparkles" : "terminal.fill")
                .foregroundStyle(source == .claude ? Theme.data : source == .gemini ? Theme.gemini : Theme.codex)
        }
    }
}

/// 面板底部的「今天」：Claude Code + Codex + Gemini 今天的输出、输入、请求、速度、峰值和 API 等值费用
struct TodayBlock: View {
    let local: LocalSnapshot
    let now: Date
    @EnvironmentObject var store: Store

    private var sourcesText: String {
        var s: [String] = []
        if local.hasClaude { s.append("Claude Code") }
        if local.hasCodex { s.append("Codex") }
        if local.hasAntigravityCLI { s.append("Antigravity CLI") }
        if local.geminiLimits != nil || local.sessions.contains(where: { $0.source == .gemini && !$0.isAntigravityCLI }) { s.append("Gemini") }
        return s.isEmpty ? "Claude Code" : s.joined(separator: " + ")
    }

    var body: some View {
        let start = Fmt.calendar.startOfDay(for: now)
        let st = UsageStats.of(local.messages.lazy.filter { $0.ts >= start })
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(L("今天", "Today", ja: "今日", ko: "오늘"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L("全部来源", "All providers", ja: "すべての提供元", ko: "모든 제공자"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .help(sourcesText)
                Spacer(minLength: 4)
                Button {
                    HistoryWindowController.shared.show(store: store)
                } label: {
                    Label(L("历史", "History", ja: "履歴", ko: "기록"), systemImage: "clock.arrow.circlepath")
                        .font(Theme.caption)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(L("打开用量历史窗口", "Open usage history", ja: "使用量の履歴を開く", ko: "사용량 기록 열기"))
            }
            VStack(spacing: 7) {
                HStack(spacing: 12) {
                    TodayMetric(label: L("输出", "Output", ja: "出力", ko: "출력"), value: Fmt.tokens(st.tokens.output))
                    TodayMetric(label: L("输入 · 含缓存", "Input · incl. cache", ja: "入力 · キャッシュ込", ko: "입력 · 캐시 포함"), value: Fmt.tokens(st.inputAll))
                    TodayMetric(label: L("请求", "Requests", ja: "リクエスト", ko: "요청"), value: Fmt.count(st.requests))
                }
                Hairline()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    speedSummary(label: L("平均", "Avg", ja: "平均", ko: "평균"), value: st.avgSpeed.map { Fmt.speed($0) } ?? "—")
                    Spacer(minLength: 4)
                    if st.peakSpeed > 0, let at = st.peakAt {
                        speedSummary(label: L("峰值", "Peak", ja: "最高", ko: "최고"), value: Fmt.speed(st.peakSpeed))
                            .help(L("峰值时刻 \(Fmt.time(at))", "Peak at \(Fmt.time(at))", ja: "最高速度の時刻 \(Fmt.time(at))", ko: "최고 속도 시각 \(Fmt.time(at))"))
                    }
                    Spacer(minLength: 4)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(L("API 等值", "API equiv.", ja: "API 換算", ko: "API 환산"))
                        Text((st.unpricedRequests > 0 ? "≥" : "") + Fmt.money(st.cost)).monospacedDigit()
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .help(costHelp(st))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.group))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
            if let all = SharedCloud.shared.todayTotal(now: now) {
                HStack(spacing: 5) {
                    Image(systemName: "icloud")
                    Text(L("全部 \(SharedCloud.shared.macCount) 台 Mac", "All \(SharedCloud.shared.macCount) Macs",
                           ja: "全 \(SharedCloud.shared.macCount) 台の Mac", ko: "Mac \(SharedCloud.shared.macCount)대 전체"))
                    Spacer(minLength: 4)
                    Text(L("输出", "Output", ja: "出力", ko: "출력") + " " + Fmt.tokens(all.tokens.output))
                    Text("·")
                    Text(L("输入", "Input", ja: "入力", ko: "입력") + " " + Fmt.tokens(all.tokens.input + all.tokens.cacheRead + all.tokens.cacheWrite))
                    Text("·")
                    Text(L("请求", "Req", ja: "リクエスト", ko: "요청") + " " + Fmt.count(all.requests ?? 0))
                }
                .font(.system(size: 10.5)).monospacedDigit()
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .help(L("Quotlet Cloud 合并的今日用量：每台 Mac 各自上报，同一会话只算一次。",
                        "Today's usage merged by Quotlet Cloud: each Mac reports its own logs, and a session is counted once.",
                        ja: "Quotlet Cloud で合算した今日の使用量です。各 Mac が自分のログを報告し、同じセッションは 1 回だけ数えます。",
                        ko: "Quotlet Cloud에서 합산한 오늘 사용량입니다. 각 Mac이 자체 로그를 보고하며 같은 세션은 한 번만 계산됩니다."))
            }
        }
        .foregroundStyle(Theme.text)
    }

    private func speedSummary(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
            Text(value).monospacedDigit()
            if value != "—" { Text("tok/s") }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Theme.text2)
        .lineLimit(1)
    }

    private func costHelp(_ st: UsageStats) -> String {
        var t = L("按各模型官方 API 价格估算：如果这些用量按 API 付费，大约要花多少钱。包月套餐实际不按这个收费。",
                  "Estimated at each model's official API prices: what this usage would cost if billed through the API. Subscription plans aren't charged this.",
                  ja: "各モデルの公式 API 価格で見積もった、API で支払った場合の金額です。定額プランでは実際にはこの金額はかかりません。",
                  ko: "각 모델의 공식 API 가격으로 추정한 금액으로, API로 결제했다면 드는 비용입니다. 구독 요금제는 실제로 이만큼 청구되지 않습니다.")
        if st.unpricedRequests > 0 {
            t += "\n" + L("其中 \(st.unpricedRequests) 次请求的模型价格未知（如 Codex），没算进去。",
                          "\(st.unpricedRequests) requests use models without a known price (e.g. Codex) and aren't included.",
                          ja: "うち \(st.unpricedRequests) 件は価格不明のモデル（Codex など）のため含まれていません。",
                          ko: "가격을 알 수 없는 모델(예: Codex)의 요청 \(st.unpricedRequests)건은 포함되지 않았습니다.")
        }
        return t
    }
}

/// 今日只把输出、输入和请求作为主指标，速度与费用降为辅助信息。
private struct TodayMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.text2)
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension LimitItem {
    /// 窗口长度：5 小时 / 1 天 / 7 天；其他类型不知道就不画时间刻度、不做预测
    var windowLength: TimeInterval? {
        if kind.hasPrefix("session") { return 5 * 3600 }
        if kind.hasPrefix("daily") { return 86400 }
        if kind.hasPrefix("weekly") { return 7 * 86400 }
        return nil
    }

    /// 紧凑行左边的短标签：「5 小时」「本周」「Opus 周」「Claude / GPT 5 小时」
    static func shortLabel(kind: String, scope: String?) -> String {
        switch kind {
        case "session": return L("5 小时", "5h", ja: "5 時間", ko: "5시간")
        case "session_scoped":
            let s = scope ?? L("指定", "Scoped", ja: "対象", ko: "지정")
            return L("\(s) · 5 小时", "\(s) · 5h", ja: "\(s) · 5 時間", ko: "\(s) · 5시간")
        case "daily_all": return L("今日", "Daily", ja: "本日", ko: "일간")
        case "daily_scoped":
            let s = scope ?? L("指定", "Scoped", ja: "対象", ko: "지정")
            return L("\(s) · 今日", "\(s) · daily", ja: "\(s) · 本日", ko: "\(s) · 일간")
        case "weekly_all": return L("本周", "Week", ja: "今週", ko: "이번 주")
        case "weekly_scoped":
            let s = scope ?? L("指定", "Scoped", ja: "対象", ko: "지정")
            return L("\(s) 周", "\(s) wk", ja: "\(s) 週", ko: "\(s) 주간")
        default: return scope ?? kind
        }
    }

    var shortLabel: String { Self.shortLabel(kind: kind, scope: scope) }
}

/// 标签和重置时间共用说明行，下一行把空间留给长进度条和额度数值。
struct LimitRow: View {
    let item: LimitItem
    let now: Date
    @State private var hovering = false

    private var level: Level { Level(percent: item.percent, severity: item.severity) }

    /// 窗口里已经过去的时间比例，用来画进度条上的竖线。
    private var elapsed: Double? {
        guard let r = item.resetsAt, let w = item.windowLength else { return nil }
        return min(1, max(0, 1 - r.timeIntervalSince(now) / w))
    }

    private var rowHelp: String {
        item.detail.map { "\(item.title)\n\($0)" } ?? item.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 4) {
                    Text(item.shortLabel)
                        .font(Theme.bodyMedium)
                        .lineLimit(1)
                    if item.detail != nil {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9.5))
                            .foregroundStyle(hovering ? Theme.text : Theme.text2.opacity(0.65))
                    }
                }
                .layoutPriority(1)
                .help(rowHelp)
                Spacer(minLength: 4)
                if let r = item.resetsAt {
                    resetLine(r)
                        .foregroundStyle(Theme.text2)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(resetLine(r))
                }
            }
            HStack(spacing: 10) {
                // 竖线 = 时间已过多少
                UsageBar(fraction: item.percent / 100, marker: elapsed, color: level.color, height: 7)
                    .help([item.detail, elapsedText].compactMap { $0 }.joined(separator: "\n"))
                Text(item.percentText)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level == .normal ? Theme.text : level.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 56, alignment: .trailing)
                    .help(item.isEstimated
                          ? L("根据本机新增 token 估算，下次接口刷新时校正。",
                              "Estimated from new local tokens. Corrected at the next quota refresh.",
                              ja: "ローカルの新規トークンから推定。次の API 更新時に補正します。",
                              ko: "새 로컬 토큰으로 추정합니다. 다음 한도 새로 고침 시 보정됩니다.")
                          : rowHelp)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering && item.detail != nil ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .overlay(alignment: .topLeading) {
            if hovering, let detail = item.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.group))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.divider, lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .alignmentGuide(.top) { $0[.bottom] + 4 }
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, -6)
        .padding(.vertical, -3)
        .zIndex(hovering ? 10 : 0)
    }

    private func resetLine(_ r: Date) -> Text {
        if r <= now { return Text(Fmt.countdown(to: r, now: now)) }
        let moment = Text(Fmt.resetMoment(r, now: now))
        var line: Text
        switch Lang.current {
        case .zh: line = moment + Text(" 重置")
        case .en: line = Text("Resets ") + moment
        case .ja: line = moment + Text(" にリセット")
        case .ko: line = moment + Text(" 재설정")
        }
        return line
    }

    private var elapsedText: String? {
        elapsed.map { e in
            let p = Int((e * 100).rounded())
            return L("竖线：时间已过 \(p)%", "Marker: \(p)% of window elapsed", ja: "縦線：経過 \(p)%", ko: "세로선: \(p)% 경과")
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var cloud = Cloud.shared
    @ObservedObject private var sync = CloudSync.shared
    @ObservedObject private var hooks = HookManager.shared
    @ObservedObject private var statusLine = ClaudeStatusLineManager.shared
    @ObservedObject private var remote = RemoteCommandManager.shared
    let onBack: () -> Void
    @State private var portText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(L("返回", "Back", ja: "戻る", ko: "뒤로"))
                    }
                    .font(Theme.body)
                    .foregroundStyle(Theme.text2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Spacer()
                Text(L("设置", "Settings", ja: "設定", ko: "설정")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Hairline()

            ScrollView {
                // 只在分组之间画线，组内各行靠留白区分
                VStack(alignment: .leading, spacing: 11) {
                    generalGroup
                    RowDivider()
                    apiGroup
                    RowDivider()
                    cloudGroup
                    RowDivider()
                    proxyGroup
                    RowDivider()
                    notificationGroup
                    RowDivider()
                    identity
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { portText = String(store.proxyPort) }
    }

    // MARK: 分组

    /// 不带标题的常用设置：语言、外观、开机启动、刷新频率
    private var generalGroup: some View {
        SettingsGroup(title: nil) {
            SettingsRow {
                SettingsLabel(L("界面语言", "Language", ja: "言語", ko: "언어"), icon: "globe")
                Spacer(minLength: 4)
                ChipPicker(options: [("", L("自动", "Auto", ja: "自動", ko: "자동")),
                                     ("zh", "中文"), ("en", "EN"), ("ja", "日本語"), ("ko", "한국어")],
                           selection: $store.language, compact: true)
                    .fixedSize()
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("外观", "Appearance", ja: "外観", ko: "화면 모드"), icon: "circle.lefthalf.filled")
                Spacer()
                ChipPicker(options: [("", L("自动", "Auto", ja: "自動", ko: "자동")),
                                     ("light", L("浅色", "Light", ja: "ライト", ko: "라이트")),
                                     ("dark", L("深色", "Dark", ja: "ダーク", ko: "다크"))],
                           selection: $store.appearance)
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("状态栏来源", "Menu bar source", ja: "メニューバーのソース", ko: "메뉴 막대 소스"), icon: "menubar.rectangle")
                Spacer()
                ChipPicker(options: [(Source.claude, "Claude"), (.codex, "Codex"), (.gemini, "Gemini")], selection: $store.menuBarSource)
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("状态栏", "Menu bar", ja: "メニューバー", ko: "메뉴 막대"), icon: "menubar.rectangle")
                Spacer(minLength: 4)
                ChipPicker(options: [("full", L("5h 41% 周 62%", "5h 41% Wk 62%", ja: "5h 41% 週 62%", ko: "5h 41% 주 62%")),
                                     ("compact", "41% 62%")],
                           selection: $store.menuBarStyle)
                    .fixedSize()
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("额度刷新", "Refresh", ja: "更新間隔", ko: "새로 고침"), icon: "arrow.clockwise",
                              inline: L("分钟", "min", ja: "分", ko: "분"))
                Spacer(minLength: 4)
                ChipPicker(options: Store.refreshChoices.map { ($0, "\($0)") }, selection: $store.refreshMinutes, compact: true)
                    .fixedSize()
            }
            .disabled(!store.usageAPIEnabled)
            .opacity(store.usageAPIEnabled ? 1 : 0.45)
            RowGap()
            SettingsRow {
                SettingsLabel(L("开机自动启动", "Launch at login", ja: "ログイン時に起動", ko: "로그인 시 실행"), icon: "power")
                Spacer()
                SwitchToggle(isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            }
        }
    }

    private var statusLineStatus: (String, Bool)? {
        if let err = statusLine.lastError { return (err, false) }
        guard store.claudeStatusLineEnabled else { return nil }
        if let latest = statusLine.latest {
            return (L("已同步 · \(Fmt.time(latest.observedAt))",
                      "Synced · \(Fmt.time(latest.observedAt))",
                      ja: "同期済み · \(Fmt.time(latest.observedAt))",
                      ko: "동기화됨 · \(Fmt.time(latest.observedAt))"), true)
        }
        return (L("等待 Claude Code 对话更新…",
                  "Waiting for next Claude Code message…",
                  ja: "Claude Code の更新待ち…",
                  ko: "Claude Code 업데이트 대기 중…"), true)
    }

    private var apiGroup: some View {
        SettingsGroup(title: L("Claude 额度", "Claude quota", ja: "Claude 使用枠", ko: "Claude 한도"),
                      footer: L("推荐使用免钥匙串模式（依赖 Claude Code 2.1.80+ statusLine，不访问钥匙串、不弹窗、不额外联网；若你已有自定义 statusLine 会自动透明保留）。",
                                "Keychain-free mode is recommended (uses Claude Code 2.1.80+ statusLine with zero Keychain prompts and no extra network calls; existing custom statusLine commands are preserved).",
                                ja: "キーチェーン不要モードを推奨します（Claude Code 2.1.80+ の statusLine を使用し、キーチェーン確認なし・追加通信なし。既存の statusLine も自動保持されます）。",
                                ko: "키체인 없는 모드를 권장합니다(Claude Code 2.1.80+ statusLine 사용, 키체인 팝업 및 추가 네트워크 요청 없음, 기존 statusLine 자동 유지).")) {
            SettingsRow {
                SettingsLabel(L("免钥匙串读取额度（推荐）", "Keychain-free quota (Recommended)", ja: "キーチェーン不要で取得（推奨）", ko: "키체인 없이 한도 읽기(권장)"),
                              icon: "checkmark.shield",
                              detail: L("使用 Claude Code 时自动获取 5 小时和每周额度",
                                        "Captures 5-hour and weekly quotas while using Claude Code",
                                        ja: "Claude Code 使用中に 5 時間・週間枠を自動取得",
                                        ko: "Claude Code 사용 중 5시간·주간 한도 자동 수집"),
                              status: statusLineStatus)
                Spacer()
                SwitchToggle(isOn: Binding(get: { store.claudeStatusLineEnabled }, set: { store.setClaudeStatusLineEnabled($0) }))
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("通过钥匙串接口主动查询", "Active API polling (Keychain)", ja: "キーチェーン API で定期取得", ko: "키체인 API 능동 조회"),
                              icon: "network",
                              detail: L("可选。后台定时请求 Anthropic 接口，支持分模型明细与超额费用",
                                        "Optional. Polls Anthropic in the background for per-model breakdown & extra usage",
                                        ja: "任意。Anthropic API を定期取得（モデル別内訳・超過利用に対応）",
                                        ko: "선택 사항. 백그라운드에서 Anthropic API를 주기적으로 조회합니다"))
                Spacer()
                SwitchToggle(isOn: $store.usageAPIEnabled)
            }
            if store.needsCredentialAuthorization {
                RowGap()
                SettingsRow {
                    SettingsLabel(L("读取 Claude Code 凭证", "Read Claude Code credentials", ja: "Claude Code の認証情報を読む", ko: "Claude Code 자격 증명 읽기"), icon: "key")
                    Spacer(minLength: 4)
                    ChipButton(title: L("允许钥匙串访问", "Allow Keychain Access", ja: "アクセスを許可", ko: "키체인 접근 허용")) { store.authorizeClaudeQuota() }
                        .fixedSize()
                        .disabled(store.isLoading)
                        .help(L("授权方式由系统和 Claude Code 凭证的保护设置决定，可能需要输入登录钥匙串密码。",
                                "Authentication follows the system and the credential's protection settings. Your login Keychain password may be required.",
                                ja: "認証方法はシステムと認証情報の保護設定で決まります。ログインキーチェーンのパスワードが必要な場合があります。",
                                ko: "인증 방식은 시스템과 자격 증명의 보호 설정에 따라 결정됩니다. 로그인 키체인 암호가 필요할 수 있습니다."))
                }
            }
        }
    }

    /// 云同步：没登录只有一个登录按钮；登录后是上报开关和“上传会话标题”
    private var cloudGroup: some View {
        SettingsGroup(title: L("云同步", "Cloud sync", ja: "クラウド同期", ko: "클라우드 동기화")) {
            if cloud.isSignedIn {
                SettingsRow {
                    SettingsLabel(L("上报额度和会话", "Upload usage & sessions", ja: "使用量とセッションを送信", ko: "사용량과 세션 업로드"),
                                  icon: "icloud.and.arrow.up", status: syncStatus)
                    Spacer()
                    SwitchToggle(isOn: $sync.enabled)
                }
                RowGap()
                SettingsRow {
                    SettingsLabel(L("上传会话标题", "Upload session titles", ja: "セッション名を送信", ko: "세션 제목 업로드"),
                                  icon: "text.alignleft",
                                  detail: L("关掉后只显示项目名", "Off: only project names are shown", ja: "オフ：プロジェクト名だけを表示", ko: "끄면 프로젝트 이름만 표시"))
                    Spacer()
                    SwitchToggle(isOn: $sync.uploadTitles)
                }
                .disabled(!sync.enabled)
                .opacity(sync.enabled ? 1 : 0.45)
                RowGap()
                SettingsRow {
                    SettingsLabel(L("精确的会话状态", "Exact session status", ja: "正確なセッション状態", ko: "정확한 세션 상태"),
                                  icon: "bolt.horizontal",
                                  detail: hooksDetailText,
                                  status: hooksStatus)
                    Spacer()
                    SwitchToggle(isOn: Binding(get: { hooks.enabled }, set: { hooks.setEnabled($0) }))
                }
                RowGap()
                SettingsRow {
                    SettingsLabel(L("允许远程指令", "Allow remote commands", ja: "リモートコマンドを許可", ko: "원격 명령 허용"),
                                  icon: "terminal",
                                  detail: remoteDetailText,
                                  status: remoteStatus)
                    Spacer()
                    ChipButton(title: L("日志", "Logs", ja: "ログ", ko: "로그")) {
                        RemoteCommandLogWindowController.shared.show()
                    }
                    .fixedSize()
                    SwitchToggle(isOn: Binding(get: { remote.enabled }, set: { remote.setEnabled($0) }))
                }
                if remote.enabled {
                    RowGap()
                    SettingsRow {
                        SettingsLabel(L("执行前本机弹窗确认", "Confirm on this Mac first", ja: "実行前にこの Mac で確認", ko: "실행 전 이 Mac에서 확인"),
                                      icon: "checkmark.shield",
                                      detail: L("每条远程指令运行前都需要点击允许", "Ask before running each remote command", ja: "各コマンドの実行前に許可を求めます", ko: "각 원격 명령 실행 전에 허용 여부를 묻습니다"))
                        Spacer()
                        SwitchToggle(isOn: $remote.requireConfirmation)
                    }
                }
            } else {
                SettingsRow {
                    SettingsLabel(L("在网站和手机上查看", "View on the web and phone", ja: "Web とスマホで見る", ko: "웹과 휴대폰에서 보기"), icon: "icloud")
                    Spacer()
                    ChipButton(title: L("登录", "Sign in", ja: "ログイン", ko: "로그인")) { cloud.signIn() }
                }
            }
        }
    }

    private var syncStatus: (String, Bool)? {
        guard sync.enabled else { return nil }
        if let err = sync.lastError { return (err, false) }
        if let t = sync.lastSyncAt {
            return (L("已同步 · \(Fmt.time(t))", "Synced · \(Fmt.time(t))", ja: "同期済み · \(Fmt.time(t))", ko: "동기화됨 · \(Fmt.time(t))"), true)
        }
        return nil
    }

    private var hooksDetailText: String {
        L("向 settings.json 安装 hooks（重写时可能重排 JSON 键顺序），退出登录自动清理",
          "Installs hooks in settings.json (may reformat JSON keys); removed on sign-out",
          ja: "settings.json に hooks を追加（JSON の並び順が変わる場合があります）。ログアウト時に自動削除",
          ko: "settings.json에 hooks를 설치합니다(JSON 키 순서가 바뀔 수 있음). 로그아웃 시 자동 제거")
    }

    private var hooksStatus: (String, Bool)? {
        if let err = hooks.lastError { return (err, false) }
        guard hooks.enabled else { return nil }
        let targets = hooks.installedTargets.isEmpty ? "Claude Code" : hooks.installedTargets.joined(separator: " · ")
        return (L("已安装 · \(targets)", "Installed · \(targets)", ja: "導入済み · \(targets)", ko: "설치됨 · \(targets)"), true)
    }

    private var remoteDetailText: String {
        var base = L("仅允许在近 30 天使用过的项目目录中执行，默认关闭",
                     "Only runs in project folders used in the last 30 days. Off by default.",
                     ja: "直近 30 日間に使ったプロジェクトのみ許可。既定でオフ",
                     ko: "최근 30일간 사용한 프로젝트 폴더에서만 실행됩니다. 기본값 꺼짐")
        if let caps = remote.capabilities {
            let items = [
                "Claude " + (caps.claude.available ? "✓" : "—"),
                "Codex " + (caps.codex.available ? "✓" : "—"),
                "Antigravity " + (caps.gemini.available ? "✓" : "—"),
            ].joined(separator: " · ")
            base += " · \(items)"
        }
        return base
    }

    private var remoteStatus: (String, Bool)? {
        if let err = remote.lastError { return (err, false) }
        guard remote.enabled else { return nil }
        if remote.pendingOutboxCount > 0 {
            return (L("队列轮询中 · 待重传 \(remote.pendingOutboxCount) 条结果",
                      "Polling queue · \(remote.pendingOutboxCount) result(s) retrying",
                      ja: "ポーリング中 · 未送信 \(remote.pendingOutboxCount) 件",
                      ko: "큐 폴링 중 · 재전송 대기 \(remote.pendingOutboxCount)건"), false)
        }
        if remote.pollConnected {
            return (L("队列轮询已连通", "Queue polling active", ja: "キューポーリング稼働中", ko: "큐 폴링 연결됨"), true)
        }
        return (L("正在连接云端队列…", "Connecting to command queue…", ja: "キューへ接続中…", ko: "명령 큐 연결 중…"), false)
    }

    private var proxyGroup: some View {
        SettingsGroup(title: L("网络代理", "Network proxy", ja: "ネットワークプロキシ", ko: "네트워크 프록시")) {
            SettingsRow {
                SettingsLabel(L("使用 HTTP 代理", "Use HTTP proxy", ja: "HTTP プロキシを使う", ko: "HTTP 프록시 사용"), icon: "network")
                Spacer()
                SwitchToggle(isOn: $store.proxyEnabled)
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("代理地址", "Proxy address", ja: "プロキシアドレス", ko: "프록시 주소"), icon: "link")
                Spacer()
                HStack(spacing: 4) {
                    TextField("127.0.0.1", text: $store.proxyHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 104)
                    Text(":").foregroundStyle(Theme.text2)
                    TextField("7890", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                        .compatOnChange(of: portText) { new in
                            let digits = new.filter(\.isNumber)
                            if digits != new { portText = digits }
                            if let p = Int(digits), (1...65535).contains(p) { store.proxyPort = p }
                        }
                }
                .font(Theme.number)
            }
            .disabled(!store.proxyEnabled)
            .opacity(store.proxyEnabled ? 1 : 0.45)
            RowGap()
            SettingsRow {
                SettingsLabel(L("测试连接", "Test connection", ja: "接続テスト", ko: "연결 테스트"), icon: "checkmark.seal",
                              status: store.connectionTest.map { ($0.text, $0.ok) })
                Spacer()
                if store.isTesting { ProgressView().controlSize(.mini) }
                ChipButton(title: L("测试", "Test", ja: "テスト", ko: "테스트")) { store.testConnection() }
                    .disabled(store.isTesting || !store.usageAPIEnabled)
            }
            if !store.usageAPIEnabled {
                Text(L("开启 Claude 额度接口后可测试连接。", "Enable the Claude quota API to test the connection.", ja: "接続テストには Claude 使用枠 API を有効にしてください。", ko: "연결을 테스트하려면 Claude 한도 API를 켜세요."))
                    .font(Theme.caption).foregroundStyle(Theme.text2)
            }
        }
    }

    private var notificationGroup: some View {
        SettingsGroup(title: L("通知", "Notifications", ja: "通知", ko: "알림"), trailing: AnyView(notificationTestControl)) {
            SettingsRow {
                SettingsLabel(L("快到上限", "Nearing limit", ja: "上限が近い", ko: "한도 임박"), icon: "bell", inline: "%")
                Spacer(minLength: 4)
                ChipPicker(options: Notifier.thresholdChoices.map { ($0, "\($0)") }, selection: $store.notifyThreshold, compact: true)
                    .fixedSize()
                    .disabled(!store.notifyLow)
                    .opacity(store.notifyLow ? 1 : 0.4)
                SwitchToggle(isOn: $store.notifyLow)
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("已用完", "Limit reached", ja: "上限に到達", ko: "한도 도달"), icon: "exclamationmark.circle", inline: "100%")
                Spacer()
                SwitchToggle(isOn: $store.notifyFull)
            }
            RowGap()
            SettingsRow {
                SettingsLabel(L("已恢复", "Available again", ja: "利用再開", ko: "다시 사용 가능"), icon: "arrow.uturn.backward.circle",
                              inline: L("额度重置后", "after reset", ja: "リセット後", ko: "재설정 후"))
                Spacer()
                SwitchToggle(isOn: $store.notifyReset)
            }
        }
    }

    /// 「发送测试」：结果显示在按钮原位，不占新行；固定高度，切换时界面不抖动
    private var notificationTestControl: some View {
        notificationTestContent.frame(height: 22)
    }

    @ViewBuilder
    private var notificationTestContent: some View {
        switch store.notificationTest {
        case .some(true):
            Label(L("已发送", "Sent", ja: "送信しました", ko: "보냄"), systemImage: "checkmark.circle.fill")
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.live)
        case .some(false):
            ChipButton(title: L("去开启通知", "Allow notifications", ja: "通知を許可", ko: "알림 허용")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
            .help(L("通知被关闭，请在系统设置 → 通知里允许 Quotlet", "Notifications are off. Allow Quotlet in System Settings → Notifications.", ja: "通知がオフです。システム設定 → 通知 で Quotlet を許可してください。", ko: "알림이 꺼져 있습니다. 시스템 설정 → 알림에서 Quotlet를 허용하세요."))
        case .none:
            ChipButton(title: L("发送测试", "Send test", ja: "テスト送信", ko: "테스트 보내기")) { store.sendTestNotification() }
        }
    }

    /// 顶部身份区：图标 + 名字 + 版本 + GitHub
    private var identity: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Quotlet").font(.system(size: 13, weight: .semibold))
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版", "dev", ja: "開発版", ko: "개발 버전"))
                        .font(Theme.caption).foregroundStyle(Theme.text2)
                }
                Link(destination: URL(string: "https://github.com/tluo-github/quotlet")!) {
                    HStack(spacing: 3) {
                        Text("GitHub")
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                    }
                    .font(Theme.caption)
                }
            }
            Spacer()
        }
    }
}

/// 设置分组：标题 + 圆角容器，组内各行之间由调用方放 Hairline 分隔
struct SettingsGroup<Content: View>: View {
    let title: String?
    var footer: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title).font(Theme.label).foregroundStyle(Theme.text2)
                    Spacer()
                    if let trailing { trailing }
                }
            }
            VStack(alignment: .leading, spacing: 0) { content }
            if let footer {
                Text(footer).font(Theme.caption).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .font(Theme.body)
            .frame(minHeight: 26)
            .padding(.vertical, 4)
    }
}

/// 设置行左侧：标题，可带一行灰色说明或一行彩色状态（成功绿 / 失败红）
struct SettingsLabel: View {
    let title: String
    var icon: String? = nil
    var detail: String? = nil
    var inline: String? = nil
    var status: (String, Bool)? = nil

    init(_ title: String, icon: String? = nil, detail: String? = nil, inline: String? = nil, status: (String, Bool)? = nil) {
        self.title = title
        self.icon = icon
        self.detail = detail
        self.inline = inline
        self.status = status
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                    if let inline { Text(inline).font(Theme.caption).foregroundStyle(Theme.text2) }
                }
                if let (text, ok) = status {
                    Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(ok ? Theme.live : Theme.critical)
                        .lineLimit(2)
                } else if let detail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.text2).lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 分割线（设置页只用在分组之间）
struct RowDivider: View {
    var body: some View { Rectangle().fill(Theme.divider).frame(height: 1) }
}

/// 组内两行之间：不画线，只留一点间距
struct RowGap: View {
    var body: some View { Color.clear.frame(height: 0) }
}

struct SwitchToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.toggle)   // 绿色留给额度状态
    }
}

// MARK: - 小组件

/// 「输入 x · 输出 y · 缓存读 z · 缓存写 w」
func tokenBreakdown(_ t: TokenCount) -> String {
    L("输入 \(Fmt.tokens(t.input)) · 输出 \(Fmt.tokens(t.output)) · 缓存读 \(Fmt.tokens(t.cacheRead)) · 缓存写 \(Fmt.tokens(t.cacheWrite))", "In \(Fmt.tokens(t.input)) · Out \(Fmt.tokens(t.output)) · Cache read \(Fmt.tokens(t.cacheRead)) · Cache write \(Fmt.tokens(t.cacheWrite))", ja: "入力 \(Fmt.tokens(t.input)) · 出力 \(Fmt.tokens(t.output)) · キャッシュ読込 \(Fmt.tokens(t.cacheRead)) · キャッシュ書込 \(Fmt.tokens(t.cacheWrite))", ko: "입력 \(Fmt.tokens(t.input)) · 출력 \(Fmt.tokens(t.output)) · 캐시 읽기 \(Fmt.tokens(t.cacheRead)) · 캐시 쓰기 \(Fmt.tokens(t.cacheWrite))")
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct ChipPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 1 : 4) {
            ForEach(options, id: \.0) { value, title in
                let on = selection == value
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? Theme.surface : Theme.text2)
                        .padding(.horizontal, compact ? 6 : 9).padding(.vertical, 3)
                        .frame(minWidth: compact ? 24 : 0)
                        .background(Capsule().fill(on ? Theme.ink : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 胶囊样式的小按钮，和 ChipPicker 同一套外观
struct ChipButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(enabled ? Color.primary : Theme.text2)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct UsageBar: View {
    let fraction: Double
    let marker: Double?
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let f = max(0, min(1, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: height)
                Capsule().fill(color).frame(width: f > 0 ? max(height, f * w) : 0, height: height)
                if let m = marker {
                    Rectangle()
                        .fill(Theme.marker)
                        .frame(width: 1, height: height + 6)
                        .offset(x: min(w - 1, max(0, m * w - 0.5)))
                }
            }
            .frame(height: g.size.height)
        }
        .frame(height: marker == nil ? height : height + 6)
    }
}

/// 标题旁边的总体状态：健康 / 用量偏高 / 接近上限

struct HealthBadge: View {
    let level: Level

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(level.color).frame(width: 6, height: 6)
            Text(level.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .fixedSize()  // 英文 "Running high" 较长，别被挤成两行
        .foregroundStyle(level.color)
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .background(Capsule().fill(level.color.opacity(0.12)))
    }
}

struct SectionBlock<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(Theme.label)
                if let note {
                    Text(note).font(Theme.caption)
                }
            }
            content
        }
    }
}

struct KVRow: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.body).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(Theme.number)
            if let detail {
                Text(detail).font(Theme.caption).foregroundStyle(Theme.text2).monospacedDigit()
            }
        }
    }
}

struct Tile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.value).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(Theme.caption).foregroundStyle(Theme.text2) }
            }
            if let detail { Text(detail).font(Theme.caption).foregroundStyle(Theme.text2).monospacedDigit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LoadingState: View {
    let text: String
    var spinner = true

    var body: some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().controlSize(.small) }
            Text(text).font(Theme.body)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct Banner: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(Theme.caption).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    ChipButton(title: actionTitle, action: action)
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
