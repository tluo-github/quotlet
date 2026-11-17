import AppKit
import Charts
import SwiftUI

// MARK: - 主面板

struct ContentView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var cloud = Cloud.shared
    @AppStorage("tab") private var tab: Tab = .usage
    @State private var showSettings: Bool
    /// 整个面板的固定高度：正好放下用量页（三条额度 + 来源 + 本机消耗 + 额外用量）。
    static let panelHeight: CGFloat = 600

    init(startInSettings: Bool = false) {
        _showSettings = State(initialValue: startInSettings)
    }

    enum Tab: String, CaseIterable {
        case usage, sessions, stats

        var title: String {
            switch self {
            case .usage: return L("用量", "Usage", ja: "使用量", ko: "사용량")
            case .sessions: return L("会话", "Sessions", ja: "セッション", ko: "세션")
            case .stats: return L("统计", "Stats", ja: "統計", ko: "통계")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView { showSettings = false }
                    .id(store.language)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    TabBar(selection: $tab)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 0)

                Hairline()

                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    // 面板固定高度（见 panelHeight）。高度若在面板打开后再变，macOS 会固定窗口底边，
                    // 顶边就会离开状态栏出现空隙，所以不做动态高度。内容多的页（会话）在里面滚动。
                    ScrollView {
                        if let err = cloud.errorMessage {
                            Banner(text: L("登录失败：", "Sign-in failed: ", ja: "ログインに失敗しました：", ko: "로그인 실패: ") + err,
                                   actionTitle: L("重试", "Try again", ja: "再試行", ko: "다시 시도")) { cloud.signIn() }
                                .padding([.horizontal, .top], 14)
                        }
                        switch tab {
                        case .usage: page(UsageTab(now: ctx.date, openSettings: { showSettings = true }))
                        case .sessions: page(SessionsTab(now: ctx.date))
                        case .stats: page(StatsTab(now: ctx.date))
                        }
                    }
                    .scrollIndicators(.automatic)
                }
                .frame(maxHeight: .infinity)
                .id(store.language)   // 切换语言后整页重建，所有文字立即换成新语言

                Hairline()
                footer
            }
        }
        .frame(width: 340, height: Self.panelHeight)
        .background(Theme.surface)
        .onAppear { store.refreshIfStale() }
    }

    private func page(_ content: some View) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L("Claude 用量", "Claude Usage", ja: "Claude 使用量", ko: "Claude 사용량")).font(.system(size: 13, weight: .semibold))
                .lineLimit(1).fixedSize()
            if let plan = store.usage?.plan {
                Text(plan.prefix(1).uppercased() + plan.dropFirst().lowercased())
                    .font(Theme.label)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1).fixedSize()
            }
            if let u = store.usage {
                HealthBadge(level: u.overallLevel)
            }
            Spacer(minLength: 4)
            AccountButton(cloud: cloud)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "gearshape", help: L("设置", "Settings", ja: "設定", ko: "설정")) { showSettings = true }
            IconButton(symbol: "globe", help: L("在浏览器打开 claude.ai 用量页", "Open claude.ai usage page", ja: "claude.ai の使用量ページを開く", ko: "claude.ai 사용량 페이지 열기")) {
                NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
            }
            // 更新时间放底栏：标题栏不挤，也不会和蓝色的重置时间混淆
            if let t = store.lastUpdated {
                Text(L("\(Fmt.time(t)) 更新", "Updated \(Fmt.time(t))", ja: "\(Fmt.time(t)) 更新", ko: "\(Fmt.time(t)) 업데이트"))
                    .font(Theme.caption).foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }
            // 刷新紧跟在更新时间后面：“什么时候更新的”和“现在更新”是一件事
            if store.isLoading || store.isScanning {
                ProgressView().controlSize(.mini).frame(width: 24, height: 24)
            } else {
                IconButton(symbol: "arrow.clockwise", help: L("刷新（⌘R）", "Refresh (⌘R)", ja: "更新（⌘R）", ko: "새로 고침(⌘R)")) { store.refreshAll() }
                    .keyboardShortcut("r")
            }
            Spacer()
            Button(L("退出", "Quit", ja: "終了", ko: "종료")) { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.caption)
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 8)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
                .help(user.email ?? "Quotabar Cloud")
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
            .help(L("登录 Quotabar Cloud，在网站和手机上查看额度和会话",
                    "Sign in to Quotabar Cloud to see usage and sessions on the web and your phone",
                    ja: "Quotabar Cloud にログインして、Web やスマートフォンで使用量とセッションを確認",
                    ko: "Quotabar Cloud에 로그인해 웹과 휴대폰에서 사용량과 세션 보기"))
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
        VStack(alignment: .leading, spacing: 16) {
            if store.needsProxyHint, store.usage == nil || store.lastUpdated.map({ now.timeIntervalSince($0) > 600 }) == true {
                // 网络不通 / 被地区拒绝：提示去设置代理，带一个直达按钮
                Banner(text: L("连不上 Anthropic。如果你需要代理才能访问，请在设置里开启网络代理。",
                               "Can't reach Anthropic. If you need a proxy to connect, turn it on in Settings.",
                               ja: "Anthropic に接続できません。接続にプロキシが必要な場合は、設定でネットワークプロキシをオンにしてください。",
                               ko: "Anthropic에 연결할 수 없습니다. 프록시가 필요하다면 설정에서 네트워크 프록시를 켜세요."),
                       actionTitle: L("去设置代理", "Set up proxy", ja: "プロキシを設定", ko: "프록시 설정"),
                       action: openSettings)
            } else if let err = store.errorMessage {
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

            if let u = store.usage {
                let roomy = u.limits.count <= 2
                VStack(spacing: 0) {
                    ForEach(Array(u.limits.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Hairline() }
                        // 第一张卡顶部不再加边距：页面已有 14pt，叠加会比其他页空一倍
                        LimitCard(item: item, now: now, roomy: roomy)
                            .padding(.top, i == 0 ? 0 : (roomy ? 16 : 12))
                            .padding(.bottom, roomy ? 16 : 12)
                    }
                }
                Hairline()

                if let l = store.local {
                    SectionBlock(title: L("本机 Claude Code", "Claude Code on this Mac", ja: "この Mac の Claude Code", ko: "이 Mac의 Claude Code"),
                                 note: L("估算", "estimate", ja: "推定", ko: "추정")) {
                        HStack(alignment: .top, spacing: 16) {
                            if let s = u.session?.resetsAt {
                                let r = l.tokens(since: s.addingTimeInterval(-5 * 3600))
                                Tile(label: L("5 小时窗口", "5-hour window", ja: "5 時間枠", ko: "5시간 구간"),
                                     value: Fmt.tokens(r.tokens.total), unit: "token",
                                     detail: L("\(r.requests) 次请求", "\(r.requests) requests", ja: "\(r.requests) 件のリクエスト", ko: "요청 \(r.requests)회"))
                            }
                            if let w = u.weekly?.resetsAt {
                                let r = l.tokens(since: w.addingTimeInterval(-7 * 86400))
                                Tile(label: L("本周", "This week", ja: "今週", ko: "이번 주"),
                                     value: Fmt.tokens(r.tokens.total), unit: "token",
                                     detail: L("\(r.requests) 次请求", "\(r.requests) requests", ja: "\(r.requests) 件のリクエスト", ko: "요청 \(r.requests)회"))
                            }
                        }
                    }
                }

                // 用量来源压成一行；额外用量只在开启时显示
                VStack(alignment: .leading, spacing: 4) {
                    if let line = sourcesLine(u.breakdown) {
                        Text(line)
                    }
                    if let e = u.extra, e.enabled {
                        let used = e.used.map { String(format: "$%.2f", $0) } ?? "—"
                        let limit = e.limit.map { String(format: "$%.2f", $0) } ?? "—"
                        Text(L("额外用量：本月 \(used) / \(limit)", "Extra usage: \(used) of \(limit) this month", ja: "追加使用量：今月 \(used) / \(limit)", ko: "추가 사용량: 이번 달 \(used) / \(limit)"))
                    }
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.text2)
            } else if store.isLoading {
                LoadingState(text: L("正在获取用量…", "Loading usage…", ja: "使用量を取得中…", ko: "사용량을 불러오는 중…"))
            }
        }
    }
}

/// 「本周用量全部来自 Claude Code」或「本周来源：Claude Code 70% · 网页 / App 聊天 30%」
func sourcesLine(_ rows: [BreakdownRow]) -> String? {
    let used = rows.filter { $0.percent > 0 }.sorted { $0.percent > $1.percent }
    guard !used.isEmpty else { return nil }
    if used.count == 1, used[0].percent >= 99.5 {
        let n = used[0].name
        return L("本周用量全部来自 \(n)", "All usage this week is from \(n)", ja: "今週の使用はすべて \(n) から", ko: "이번 주 사용량은 모두 \(n)에서 발생")
    }
    let parts = used.map { "\($0.name) \(Fmt.percent($0.percent))" }.joined(separator: " · ")
    return L("本周来源：", "This week: ", ja: "今週の内訳：", ko: "이번 주 사용처: ") + parts
}

struct LimitCard: View {
    let item: LimitItem
    let now: Date
    var roomy = false   // 额度少（≤2 条）时数字更大、间距更松

    private var level: Level { Level(percent: item.percent, severity: item.severity) }

    private var windowLength: TimeInterval? {
        if item.kind == "session" { return 5 * 3600 }
        if item.kind.hasPrefix("weekly") { return 7 * 86400 }
        return nil
    }

    /// 窗口里已经过去的时间比例，用来画进度条上的竖线。
    private var elapsed: Double? {
        guard let r = item.resetsAt, let w = windowLength else { return nil }
        return min(1, max(0, 1 - r.timeIntervalSince(now) / w))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: roomy ? 8 : 6) {
            Text(item.title).font(Theme.label).foregroundStyle(Theme.text2)

            // 百分比 + 进度条同一行。状态文字只在标题栏显示一次（HealthBadge），这里靠颜色表达。
            // 百分比列按「100%」的宽度占位，几张卡的进度条左端对齐。
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .leading) {
                    Text("100%").hidden()
                    Text(Fmt.percent(item.percent)).foregroundStyle(level.color)
                }
                .font(roomy ? Theme.heroLarge : Theme.hero)
                // 进度条粗细按重要程度：额度 6 / 项目 4 / 会话 2；竖线 = 时间已过多少
                UsageBar(fraction: item.percent / 100, marker: elapsed, color: level.color, height: 6)
                    .help(elapsedText ?? "")
            }

            if let r = item.resetsAt {
                resetLine(r).font(Theme.caption).foregroundStyle(Theme.text2).lineLimit(1)
            }
        }
    }

    /// 一句话：「今天 18:50 重置 · 还有 49分钟」，时间用蓝色半粗体
    private func resetLine(_ r: Date) -> Text {
        let countdown = Fmt.countdown(to: r, now: now)
        if r <= now { return Text(countdown) }
        let moment = Text(Fmt.resetMoment(r, now: now)).fontWeight(.semibold).foregroundColor(Theme.time)
        switch Lang.current {
        case .zh: return moment + Text(" 重置 · \(countdown)")
        case .en: return Text("Resets ") + moment + Text(" · \(countdown)")
        case .ja: return moment + Text(" にリセット · \(countdown)")
        case .ko: return moment + Text(" 재설정 · \(countdown)")
        }
    }

    private var elapsedText: String? {
        elapsed.map { e in
            let p = Int((e * 100).rounded())
            return L("竖线：时间已过 \(p)%", "Marker: \(p)% of window elapsed", ja: "縦線：経過 \(p)%", ko: "세로선: \(p)% 경과")
        }
    }
}

// MARK: - 会话

struct SessionsTab: View {
    @EnvironmentObject var store: Store
    let now: Date
    @AppStorage("sessionRange") private var range: Range = .day

    enum Range: String, CaseIterable {
        case day, week, month

        var title: String {
            switch self {
            case .day: return L("24 小时", "24 hours", ja: "24 時間", ko: "24시간")
            case .week: return L("7 天", "7 days", ja: "7 日", ko: "7일")
            case .month: return L("30 天", "30 days", ja: "30 日", ko: "30일")
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .day: return 86400
            case .week: return 7 * 86400
            case .month: return 30 * 86400
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipPicker(options: Range.allCases.map { ($0, $0.title) }, selection: $range)

            if let l = store.local {
                let list = l.sessions(since: now.addingTimeInterval(-range.seconds))
                let total = list.reduce(0) { $0 + $1.tokens.total }
                let active = list.filter { $0.isActive(now: now) }.count
                let maxTokens = list.map(\.tokens.total).max() ?? 1
                let mainModel = Dictionary(grouping: list, by: \.mainModel).max { $0.value.count < $1.value.count }?.key

                // 一行概览，不再用三个大数字抢列表的风头
                Text(summary(count: list.count, tokens: total, active: active))
                    .font(Theme.caption).foregroundStyle(Theme.text2)

                if list.isEmpty {
                    LoadingState(text: L("这段时间没有 Claude Code 会话", "No Claude Code sessions in this period", ja: "この期間の Claude Code セッションはありません", ko: "이 기간에는 Claude Code 세션이 없습니다"), spinner: false)
                }

                ForEach(groupByDay(list), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(Fmt.dayLabel(group.day, now: now)).font(Theme.label).foregroundStyle(Theme.text2)
                            Spacer()
                            Text(Fmt.tokens(group.items.reduce(0) { $0 + $1.tokens.total }))
                                .font(Theme.caption).foregroundStyle(Theme.text2).monospacedDigit()
                        }
                        .padding(.horizontal, 6).padding(.bottom, 2)
                        ForEach(group.items) {
                            SessionRow(session: $0, now: now, maxTokens: maxTokens, mainModel: mainModel)
                        }
                    }
                    // 行内留 6pt 给悬停背景，整体向外让出，让文字和其他页一样对齐到左边距
                    .padding(.horizontal, -6)
                }

                if !list.isEmpty {
                    Text(L("右键会话可以复制恢复命令", "Right-click a session to copy its resume command", ja: "セッションを右クリックすると再開コマンドをコピーできます", ko: "세션을 오른쪽 클릭하면 재개 명령을 복사할 수 있습니다")).font(Theme.caption).foregroundStyle(Theme.text2)
                }
            } else {
                LoadingState(text: L("正在读取本机会话日志…", "Reading local session logs…", ja: "ローカルのセッションログを読み込み中…", ko: "로컬 세션 로그를 읽는 중…"))
            }
        }
    }

    private func summary(count: Int, tokens: Int, active: Int) -> String {
        var t = L("\(count) 个会话 · \(Fmt.tokens(tokens)) token", "\(count) sessions · \(Fmt.tokens(tokens)) tokens",
                  ja: "\(count) セッション · \(Fmt.tokens(tokens)) トークン", ko: "세션 \(count)개 · 토큰 \(Fmt.tokens(tokens))")
        if active > 0 { t += L(" · \(active) 个进行中", " · \(active) active", ja: " · 進行中 \(active)", ko: " · 진행 중 \(active)") }
        return t
    }

    private func groupByDay(_ list: [SessionSummary]) -> [(day: Date, items: [SessionSummary])] {
        var order: [Date] = []
        var map: [Date: [SessionSummary]] = [:]
        for s in list {
            let d = Fmt.calendar.startOfDay(for: s.end)
            if map[d] == nil { order.append(d) }
            map[d, default: []].append(s)
        }
        return order.map { ($0, map[$0]!) }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let now: Date
    var maxTokens: Int = 1
    var mainModel: String? = nil
    @State private var hovering = false

    var body: some View {
        let s = session
        let active = s.isActive(now: now)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if active {
                        Circle().fill(Theme.live).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.5 }
                            .padding(.trailing, 6)
                    }
                    Text(s.title).font(Theme.bodyMedium).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.tokens(s.tokens.total)).font(Theme.number)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(meta).font(Theme.caption).foregroundStyle(Theme.text2).lineLimit(1)
                    Spacer(minLength: 8)
                    // 进行中只靠标题前的绿点表示，这里和其他会话一样显示时长
                    Text(Fmt.compactDuration(s.end.timeIntervalSince(s.start)))
                        .font(Theme.caption).foregroundStyle(Theme.text2).monospacedDigit()
                }
                // 用量比例条：一眼看出哪个会话用得多
                UsageBar(fraction: Double(s.tokens.total) / Double(max(1, maxTokens)), marker: nil,
                         color: Theme.data, height: 2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(Self.tokenDetail(s) + "\n" + L("会话 ID：", "Session ID: ", ja: "セッション ID：", ko: "세션 ID: ") + s.id)
        .contextMenu {
            Button(L("复制恢复命令", "Copy resume command", ja: "再開コマンドをコピー", ko: "재개 명령 복사")) {
                copy(s.cwd.map { "cd \(shellQuote($0)) && claude --resume \(s.id)" } ?? "claude --resume \(s.id)")
            }
            Button(L("复制会话 ID", "Copy session ID", ja: "セッション ID をコピー", ko: "세션 ID 복사")) { copy(s.id) }
            if let cwd = s.cwd {
                Button(L("在访达中打开项目目录", "Open project folder in Finder", ja: "プロジェクトフォルダを Finder で開く", ko: "Finder에서 프로젝트 폴더 열기")) { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
            }
        }
    }

    /// 「项目 · 12:09–15:27」，模型和主要模型不同时才标出来
    private var meta: String {
        let s = session
        var parts = [s.project, "\(Fmt.sessionTime(s.start, now: s.end))–\(Fmt.time(s.end))"]
        if let mainModel, s.mainModel != mainModel { parts.append(Fmt.modelName(s.mainModel)) }
        return parts.joined(separator: " · ")
    }

    static func tokenDetail(_ s: SessionSummary) -> String {
        var text = Fmt.modelName(s.mainModel) + " · " + tokenBreakdown(s.tokens)
        if s.subagentTokens > 0 { text += "\n" + L("其中子代理 ", "Subagents: ", ja: "うちサブエージェント ", ko: "하위 에이전트: ") + Fmt.tokens(s.subagentTokens) }
        return text
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - 统计

struct StatsTab: View {
    @EnvironmentObject var store: Store
    let now: Date
    @AppStorage("statsDays") private var days: Int = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChipPicker(options: [(7, L("7 天", "7 days", ja: "7 日", ko: "7일")), (30, L("30 天", "30 days", ja: "30 日", ko: "30일"))], selection: $days)

            if let l = store.local {
                content(l)
            } else {
                LoadingState(text: L("正在读取本机会话日志…", "Reading local session logs…", ja: "ローカルのセッションログを読み込み中…", ko: "로컬 세션 로그를 읽는 중…"))
            }
        }
    }

    @ViewBuilder
    private func content(_ l: LocalSnapshot) -> some View {
        let cal = Fmt.calendar
        let since = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now))!
        let sessions = l.sessions(since: since)
        let daily = l.daily(days: days, now: now)
        let models = l.models(since: since).filter { $0.tokens.total > 0 }
        let projects = Array(l.projects(since: since).filter { $0.tokens > 0 }.prefix(5))
        let total = models.reduce(0) { $0 + $1.tokens.total }
        let activeDays = daily.filter { $0.tokens.total > 0 }.count
        let longest = sessions.map { $0.end.timeIntervalSince($0.start) }.max() ?? 0
        let notableModels = models.filter { total > 0 && Double($0.tokens.total) / Double(total) >= 0.01 }

        // 主角：总 token；其余压成一行
        VStack(alignment: .leading, spacing: 3) {
            Text(L("总 token", "Total tokens", ja: "合計トークン", ko: "총 토큰")).font(Theme.label).foregroundStyle(Theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.tokens(total)).font(Theme.hero)
                Text("token").font(Theme.caption).foregroundStyle(Theme.text2)
            }
            Text(statsLine(sessions: sessions.count, activeDays: activeDays, longest: longest,
                           model: notableModels.count == 1 ? notableModels.first.map { Fmt.modelName($0.model) } : nil))
                .font(Theme.caption).foregroundStyle(Theme.text2)
        }

        DailyChart(daily: daily, now: now)

        if !projects.isEmpty {
            SectionBlock(title: L("按项目", "By project", ja: "プロジェクト別", ko: "프로젝트별")) {
                let top = projects.first?.tokens ?? 1
                ForEach(projects) { p in
                    ShareRow(name: p.project, value: Fmt.tokens(p.tokens), fraction: Double(p.tokens) / Double(max(1, top)))
                }
            }
        }

        if notableModels.count > 1 {
            SectionBlock(title: L("按模型", "By model", ja: "モデル別", ko: "모델별")) {
                ForEach(notableModels) { m in
                    let pct = Double(m.tokens.total) / Double(max(1, total)) * 100
                    ShareRow(name: Fmt.modelName(m.model), value: String(format: "%.0f%%", pct), fraction: pct / 100)
                }
            }
        }

        Text(L("来自本机日志，同一条回复只算一次。", "From local logs; each reply is counted once.", ja: "ローカルログから集計。同じ返信は 1 回だけ数えます。", ko: "로컬 로그 기준이며 같은 응답은 한 번만 셉니다."))
            .font(Theme.caption).foregroundStyle(Theme.text2)
    }

    private func statsLine(sessions: Int, activeDays: Int, longest: TimeInterval, model: String?) -> String {
        var parts = [
            L("\(sessions) 个会话", "\(sessions) sessions", ja: "\(sessions) セッション", ko: "세션 \(sessions)개"),
            L("活跃 \(activeDays)/\(days) 天", "active \(activeDays)/\(days) days", ja: "稼働 \(activeDays)/\(days) 日", ko: "활동 \(activeDays)/\(days)일"),
        ]
        if longest > 0 { parts.append(L("最长 ", "longest ", ja: "最長 ", ko: "최장 ") + Fmt.compactDuration(longest)) }
        if let model { parts.append(model) }
        // 每一项内部用不换行空格，折行只发生在「·」之间，不会把 "Opus 5.5" 拆成两行
        return parts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }
}

/// 名称 + 比例条 + 数值，一行
struct ShareRow: View {
    let name: String
    let value: String
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(Theme.body).lineLimit(1).frame(width: 96, alignment: .leading)
            UsageBar(fraction: fraction, marker: nil, color: Theme.data, height: 4)
            Text(value).font(Theme.number).frame(width: 56, alignment: .trailing)
        }
    }
}

struct DailyChart: View {
    let daily: [(day: Date, tokens: TokenCount)]
    let now: Date
    @State private var selected: Date?

    var body: some View {
        let cal = Fmt.calendar
        let picked = selected.flatMap { s in daily.first { cal.isDate($0.day, inSameDayAs: s) } }
        let focus = picked ?? daily.last

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L("每天 token", "Tokens per day", ja: "1 日あたりのトークン", ko: "일별 토큰")).font(Theme.label).foregroundStyle(Theme.text2)
                Spacer()
                Text(focus.map { Fmt.dayLabel($0.day, now: now) } ?? "")
                    .font(Theme.caption).foregroundStyle(Theme.text2)
                Text(focus.map { Fmt.tokens($0.tokens.total) } ?? "—").font(Theme.number)
            }

            Chart(daily, id: \.day) { d in
                BarMark(x: .value("day", d.day, unit: .day),
                        y: .value("token", d.tokens.total),
                        width: .ratio(0.6))
                    .cornerRadius(2)
                    .foregroundStyle(focus.map { cal.isDate($0.day, inSameDayAs: d.day) } == true
                                     ? Theme.dataStrong : Theme.data)
            }
            .chartXSelection(value: $selected)
            // 不要纵轴刻度：具体数值看上方「今天 / 选中那天」，只留一条底线托住柱子
            .chartYAxis {
                AxisMarks(values: [0]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.divider)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: daily.count <= 7 ? 1 : 5)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(Fmt.shortDay(d)).font(.system(size: 11)).foregroundStyle(Theme.text2)
                        }
                    }
                }
            }
            .environment(\.timeZone, Fmt.tz)
            .frame(height: 110)
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var cloud = Cloud.shared
    @ObservedObject private var sync = CloudSync.shared
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
            RowGap()
            SettingsRow {
                SettingsLabel(L("开机自动启动", "Launch at login", ja: "ログイン時に起動", ko: "로그인 시 실행"), icon: "power")
                Spacer()
                SwitchToggle(isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
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
                        .onChange(of: portText) { _, new in
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
                    .disabled(store.isTesting)
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
            .help(L("通知被关闭，请在系统设置 → 通知里允许 Quotabar", "Notifications are off. Allow Quotabar in System Settings → Notifications.", ja: "通知がオフです。システム設定 → 通知 で Quotabar を許可してください。", ko: "알림이 꺼져 있습니다. 시스템 설정 → 알림에서 Quotabar를 허용하세요."))
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
                    Text("Quotabar").font(.system(size: 13, weight: .semibold))
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版", "dev", ja: "開発版", ko: "개발 버전"))
                        .font(Theme.caption).foregroundStyle(Theme.text2)
                }
                Link(destination: URL(string: "https://github.com/tluo-github/quotabar")!) {
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

struct TabBar: View {
    @Binding var selection: ContentView.Tab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 18) {
            ForEach(ContentView.Tab.allCases, id: \.self) { t in
                let on = selection == t
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = t }
                } label: {
                    VStack(spacing: 5) {
                        Text(t.title)
                            .font(.system(size: 12, weight: on ? .medium : .regular))
                            .foregroundStyle(on ? Color.primary : Theme.text2)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 1.5)
                            if on {
                                Rectangle().fill(Theme.ink).frame(height: 1.5)
                                    .matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
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
                Text(title).font(Theme.label).foregroundStyle(Theme.text2)
                if let note {
                    Text(note).font(Theme.caption).foregroundStyle(Theme.text2)
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
            Text(text).font(Theme.body).foregroundStyle(Theme.text2)
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
