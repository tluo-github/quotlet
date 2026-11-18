import AppKit
import Charts
import SwiftUI

// MARK: - 主面板

/// 点状态栏打开的面板：只看配额（Claude、Codex 各一组）和「今天」的用量；会话和历史在「用量历史」窗口里。
struct ContentView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var cloud = Cloud.shared
    @State private var showSettings: Bool
    /// 整个面板的固定高度。高度若在面板打开后再变，macOS 会固定窗口底边，顶边就会离开状态栏出现空隙，
    /// 所以不做动态高度；内容放不下时在里面滚动。
    static let panelHeight: CGFloat = 700

    init(startInSettings: Bool = false) {
        _showSettings = State(initialValue: startInSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView { showSettings = false }
                    .id(store.language)
            } else {
                header
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let err = cloud.errorMessage {
                                Banner(text: L("登录失败：", "Sign-in failed: ", ja: "ログインに失敗しました：", ko: "로그인 실패: ") + err,
                                       actionTitle: L("重试", "Try again", ja: "再試行", ko: "다시 시도")) { cloud.signIn() }
                            }
                            UsageTab(now: ctx.date, openSettings: { showSettings = true })
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
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

    private var header: some View {
        HStack(spacing: 8) {
            Text(L("用量", "Usage", ja: "使用量", ko: "사용량")).font(.system(size: 13, weight: .semibold))
                .lineLimit(1).fixedSize()
            if let level = overallLevel {
                HealthBadge(level: level)
            }
            Spacer(minLength: 4)
            AccountButton(cloud: cloud)
        }
    }

    /// Claude 和 Codex 所有额度里最差的状态
    private var overallLevel: Level? {
        let items = (store.usage?.limits ?? []) + store.codexLimits(now: Date())
        guard !items.isEmpty else { return nil }
        let levels = items.map { Level(percent: $0.percent, severity: $0.severity) }
        if levels.contains(.critical) { return .critical }
        if levels.contains(.warning) { return .warning }
        return .normal
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
        VStack(alignment: .leading, spacing: 12) {
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

            let claude = store.usage?.limits ?? []
            let codex = store.codexLimits(now: now)
            let all = claude + codex
            // 左边短标签、右边倒计时都按最长的那个定宽，Claude 和 Codex 两组的进度条一样长、左端对齐
            let labelWidth = all.map {
                ceil(($0.shortLabel as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width)
            }.max() ?? 40
            let countdownWidth = all.map {
                ceil(($0.countdown(now: now) as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)]).width) + 1
            }.max() ?? 40

            if let advice = Advice.make(claude: claude, codex: codex, now: now) {
                AdviceCard(advice: advice)
            }

            if let u = store.usage {
                ProviderGroup(name: "Claude", plan: u.plan.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() },
                              dot: Theme.data, limits: u.limits, now: now,
                              labelWidth: labelWidth, countdownWidth: countdownWidth) {
                    // 用量来源压成一行；额外用量只在开启时显示
                    let sources = sourcesLine(u.breakdown)
                    let extra = u.extra.flatMap { $0.enabled ? $0 : nil }
                    if sources != nil || extra != nil {
                        VStack(alignment: .leading, spacing: 3) {
                            if let sources { Text(sources) }
                            if let e = extra {
                                let used = e.used.map { String(format: "$%.2f", $0) } ?? "—"
                                let limit = e.limit.map { String(format: "$%.2f", $0) } ?? "—"
                                Text(L("额外用量：本月 \(used) / \(limit)", "Extra usage: \(used) of \(limit) this month", ja: "追加使用量：今月 \(used) / \(limit)", ko: "추가 사용량: 이번 달 \(used) / \(limit)"))
                            }
                        }
                        .font(Theme.caption)
                        .foregroundStyle(Theme.text2)
                    }
                }
            } else if store.isLoading {
                LoadingState(text: L("正在获取用量…", "Loading usage…", ja: "使用量を取得中…", ko: "사용량을 불러오는 중…"))
            }

            if !codex.isEmpty, let c = store.local?.codexLimits {
                Hairline()
                ProviderGroup(name: "Codex", plan: c.planTitle, dot: Theme.codex, limits: codex, now: now,
                              labelWidth: labelWidth, countdownWidth: countdownWidth) {
                    // Codex 的额度只在用 Codex 时写进日志，隔久了说明一下是什么时候的数
                    if now.timeIntervalSince(c.observedAt) > 600 {
                        Text(L("记录于 \(Fmt.sessionTime(c.observedAt, now: now))，用 Codex 时更新",
                               "As of \(Fmt.sessionTime(c.observedAt, now: now)); updates when you use Codex",
                               ja: "\(Fmt.sessionTime(c.observedAt, now: now)) 時点 · Codex を使うと更新",
                               ko: "\(Fmt.sessionTime(c.observedAt, now: now)) 기준 · Codex 사용 시 갱신"))
                            .font(Theme.caption).foregroundStyle(Theme.text2)
                    }
                }
            }

            if let l = store.local {
                Hairline()
                TodayBlock(local: l, now: now)
            }
        }
    }
}

/// 一个工具的配额：标题行（名字 · 套餐 · 最紧张那条的百分比）+ 每条额度一行
struct ProviderGroup<Footer: View>: View {
    let name: String
    let plan: String?
    let dot: Color
    let limits: [LimitItem]
    let now: Date
    let labelWidth: CGFloat
    let countdownWidth: CGFloat
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(name).font(.system(size: 13, weight: .semibold))
                if let plan {
                    Text(plan).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.hover))
                }
                Spacer()
                if let worst = limits.max(by: { $0.percent < $1.percent }) {
                    Text(Fmt.percent(worst.percent))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Level(percent: worst.percent, severity: worst.severity).color)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(limits) { item in
                    LimitRow(item: item, now: now, labelWidth: labelWidth, countdownWidth: countdownWidth)
                }
            }
            footer
        }
    }
}

/// 额度告急时的建议：一边快用完、另一边还宽裕，就建议先用另一边
struct Advice {
    let title: String
    let badge: String
    let reason: String

    static func make(claude: [LimitItem], codex: [LimitItem], now: Date) -> Advice? {
        guard !claude.isEmpty, !codex.isEmpty else { return nil }
        func tight(_ items: [LimitItem]) -> LimitItem? {
            items.first { Pace(item: $0, now: now)?.emptyIn != nil || $0.percent >= 90 }
        }
        func roomy(_ items: [LimitItem]) -> Bool { items.allSatisfy { $0.percent < 70 && Pace(item: $0, now: now)?.emptyIn == nil } }
        func left(_ items: [LimitItem]) -> String {
            let five = items.first { $0.kind == "session" } ?? items[0]
            let pct = Fmt.percent(max(0, 100 - five.percent))
            return five.kind == "session"
                ? L("5 小时还剩 \(pct)", "\(pct) left in 5h", ja: "5 時間枠の残り \(pct)", ko: "5시간 \(pct) 남음")
                : L("还剩 \(pct)", "\(pct) left", ja: "残り \(pct)", ko: "\(pct) 남음")
        }
        func why(_ name: String, _ it: LimitItem) -> String {
            var text: String
            if let t = Pace(item: it, now: now)?.emptyIn {
                text = L("\(name) \(it.shortLabel)约 \(Fmt.duration(t))后用完", "\(name) \(it.shortLabel) runs out in ~\(Fmt.duration(t))",
                         ja: "\(name) \(it.shortLabel)は約\(Fmt.duration(t))で上限", ko: "\(name) \(it.shortLabel) 약 \(Fmt.duration(t)) 후 소진")
            } else {
                text = L("\(name) \(it.shortLabel)已用 \(Fmt.percent(it.percent))", "\(name) \(it.shortLabel) at \(Fmt.percent(it.percent))",
                         ja: "\(name) \(it.shortLabel)は \(Fmt.percent(it.percent)) 使用", ko: "\(name) \(it.shortLabel) \(Fmt.percent(it.percent)) 사용")
            }
            if let r = it.resetsAt {
                text += L("，\(Fmt.resetMoment(r, now: now)) 重置", " · resets \(Fmt.resetMoment(r, now: now))",
                          ja: " · \(Fmt.resetMoment(r, now: now)) にリセット", ko: " · \(Fmt.resetMoment(r, now: now)) 재설정")
            }
            return text
        }
        if let t = tight(claude), roomy(codex) {
            return Advice(title: L("先用 Codex", "Use Codex for now", ja: "今は Codex を", ko: "지금은 Codex"), badge: left(codex), reason: why("Claude", t))
        }
        if let t = tight(codex), roomy(claude) {
            return Advice(title: L("先用 Claude", "Use Claude for now", ja: "今は Claude を", ko: "지금은 Claude"), badge: left(claude), reason: why("Codex", t))
        }
        return nil
    }
}

struct AdviceCard: View {
    let advice: Advice

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(advice.title).font(.system(size: 13, weight: .semibold))
                Text(advice.badge).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.live)
            }
            Text(advice.reason).font(Theme.caption).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.live.opacity(0.10)))
    }
}

/// 面板底部的「今天」：Claude Code + Codex 今天的输出、输入、请求、速度、峰值和 API 等值费用
struct TodayBlock: View {
    let local: LocalSnapshot
    let now: Date
    @EnvironmentObject var store: Store

    var body: some View {
        let start = Fmt.calendar.startOfDay(for: now)
        let st = UsageStats.of(local.messages.lazy.filter { $0.ts >= start })
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("今天", "Today", ja: "今日", ko: "오늘")).font(.system(size: 13, weight: .semibold))
                Text(local.hasCodex ? "Claude Code + Codex" : "Claude Code").font(Theme.caption).foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Spacer()
                Button {
                    HistoryWindowController.shared.show(store: store)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 11, weight: .medium))
                        Text(L("历史", "History", ja: "履歴", ko: "기록"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hover))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("打开用量历史窗口", "Open usage history", ja: "使用量の履歴を開く", ko: "사용량 기록 열기"))
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    TodayTile(label: L("输出", "Output", ja: "出力", ko: "출력"), value: Fmt.tokens(st.tokens.output))
                    TodayTile(label: L("输入（含缓存）", "Input (incl. cache)", ja: "入力（キャッシュ含む）", ko: "입력(캐시 포함)"), value: Fmt.tokens(st.inputAll))
                }
                GridRow {
                    TodayTile(label: L("请求", "Requests", ja: "リクエスト", ko: "요청"), value: Fmt.count(st.requests))
                    TodayTile(label: L("平均速度", "Avg speed", ja: "平均速度", ko: "평균 속도"),
                              value: st.avgSpeed.map { Fmt.speed($0) } ?? "—", unit: st.avgSpeed == nil ? nil : "tok/s")
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                if st.peakSpeed > 0, let at = st.peakAt {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L("今日峰值", "Today's peak", ja: "今日のピーク", ko: "오늘 최고")).foregroundStyle(Theme.text2)
                        Spacer()
                        Text("\(Fmt.speed(st.peakSpeed)) tok/s").fontWeight(.semibold).foregroundStyle(Theme.warning)
                        Text("· \(Fmt.time(at))").foregroundStyle(Theme.text2)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L("今日费用", "Today's cost", ja: "今日の費用", ko: "오늘 비용")).foregroundStyle(Theme.text2)
                    Text(L("API 等值", "API equiv.", ja: "API 換算", ko: "API 환산")).font(.system(size: 10.5)).foregroundStyle(Theme.text2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.hover))
                    Spacer()
                    Text((st.unpricedRequests > 0 ? "≥" : "") + Fmt.money(st.cost)).fontWeight(.semibold)
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.text2)
                        .help(costHelp(st))
                }
            }
            .font(.system(size: 12).monospacedDigit())
        }
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

struct TodayTile: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.text2).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit())
                if let unit { Text(unit).font(Theme.caption).foregroundStyle(Theme.text2) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

extension LimitItem {
    /// 窗口长度：5 小时 / 7 天；其他类型不知道就不画时间刻度、不做预测
    var windowLength: TimeInterval? {
        if kind == "session" { return 5 * 3600 }
        if kind.hasPrefix("weekly") { return 7 * 86400 }
        return nil
    }

    /// 紧凑行左边的短标签：「5 小时」「本周」「Opus 周」
    static func shortLabel(kind: String, scope: String?) -> String {
        switch kind {
        case "session": return L("5 小时", "5h", ja: "5 時間", ko: "5시간")
        case "weekly_all": return L("本周", "Week", ja: "今週", ko: "이번 주")
        case "weekly_scoped":
            let s = scope ?? L("指定", "Scoped", ja: "対象", ko: "지정")
            return L("\(s) 周", "\(s) wk", ja: "\(s) 週", ko: "\(s) 주간")
        default: return scope ?? kind
        }
    }

    var shortLabel: String { Self.shortLabel(kind: kind, scope: scope) }

    /// 紧凑行右边的倒计时：「3小时6分」「3天19小时」
    func countdown(now: Date) -> String {
        guard let r = resetsAt else { return "" }
        return r > now ? Fmt.duration(r.timeIntervalSince(now)) : "—"
    }
}

/// 按窗口里到现在为止的平均速度估算：重置时会用到多少，会不会在重置前用完。
/// 只用当前百分比和已过时间，不需要历史数据；窗口刚开始时速度不准，不预测。
struct Pace {
    let projected: Double          // 照这个速度，重置时用到的百分比
    let emptyIn: TimeInterval?     // 会提前用完时：还有多久用完
    let early: TimeInterval?       // 比重置早多久

    init?(item: LimitItem, now: Date) {
        guard let r = item.resetsAt, let w = item.windowLength else { return nil }
        let left = r.timeIntervalSince(now)
        let elapsed = w - left
        guard left > 0, elapsed > 60, item.percent > 0, item.percent < 100 else { return nil }
        // 已过时间不到窗口的 10% 且用量不到 10%：样本太少，不预测
        guard elapsed >= w * 0.1 || item.percent >= 10 else { return nil }
        let rate = item.percent / elapsed
        projected = item.percent + rate * left
        if projected >= 100 {
            let t = (100 - item.percent) / rate
            emptyIn = t
            early = left - t
        } else {
            emptyIn = nil
            early = nil
        }
    }

    var level: Level {
        if emptyIn != nil { return .critical }
        if projected >= 85 { return .warning }
        return .normal
    }
}

/// 一条额度的紧凑显示（标签按最长的定宽，几行的进度条和数字对齐）：
///   5 小时  ━━━━━━━│──  54%  3小时14分
///           今天 10:30 重置 · 届时约 72%
///           约 46分钟后用完，比重置早 39分钟      ← 只在会提前用完时出现，红色
struct LimitRow: View {
    let item: LimitItem
    let now: Date
    var labelWidth: CGFloat = 40
    var countdownWidth: CGFloat = 56

    private var level: Level { Level(percent: item.percent, severity: item.severity) }

    /// 窗口里已经过去的时间比例，用来画进度条上的竖线。
    private var elapsed: Double? {
        guard let r = item.resetsAt, let w = item.windowLength else { return nil }
        return min(1, max(0, 1 - r.timeIntervalSince(now) / w))
    }

    var body: some View {
        let pace = Pace(item: item, now: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(item.shortLabel)
                    .font(Theme.bodyMedium)
                    .lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)
                    .help(item.title)
                // 竖线 = 时间已过多少
                UsageBar(fraction: item.percent / 100, marker: elapsed, color: level.color, height: 6)
                    .help(elapsedText ?? "")
                Text(Fmt.percent(item.percent))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level.color)
                    .frame(width: 40, alignment: .trailing)
                Text(item.countdown(now: now))
                    .font(Theme.caption.monospacedDigit())
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1).fixedSize()
                    .frame(width: countdownWidth, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let r = item.resetsAt {
                    resetLine(r, pace: pace)
                        .foregroundStyle(Theme.text2)
                }
                if item.percent >= 100, let r = item.resetsAt, r > now {
                    Text(L("已用完，\(Fmt.duration(r.timeIntervalSince(now)))后恢复",
                           "Used up · back in \(Fmt.duration(r.timeIntervalSince(now)))",
                           ja: "上限に到達 · \(Fmt.duration(r.timeIntervalSince(now)))後に回復",
                           ko: "모두 사용 · \(Fmt.duration(r.timeIntervalSince(now))) 후 복구"))
                        .foregroundStyle(Theme.critical)
                } else if let pace, let t = pace.emptyIn, let e = pace.early {
                    Text(L("约 \(Fmt.duration(t))后用完，比重置早 \(Fmt.duration(e))",
                           "Empty in ~\(Fmt.duration(t)) — \(Fmt.duration(e)) before reset",
                           ja: "約\(Fmt.duration(t))で上限 · リセットの\(Fmt.duration(e))前",
                           ko: "약 \(Fmt.duration(t)) 후 소진 · 재설정 \(Fmt.duration(e)) 전"))
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.critical)
                }
            }
            .font(Theme.caption)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, labelWidth + 10)
        }
    }

    /// 「今天 10:30 重置 · 届时约 72%」，重置时间用蓝色半粗体；会提前用完时不写届时多少（下一行红字说明）
    private func resetLine(_ r: Date, pace: Pace?) -> Text {
        if r <= now { return Text(Fmt.countdown(to: r, now: now)) }
        let moment = Text(Fmt.resetMoment(r, now: now)).fontWeight(.semibold).foregroundColor(Theme.time)
        var line: Text
        switch Lang.current {
        case .zh: line = moment + Text(" 重置")
        case .en: line = Text("Resets ") + moment
        case .ja: line = moment + Text(" にリセット")
        case .ko: line = moment + Text(" 재설정")
        }
        if let pace, pace.emptyIn == nil, item.percent < 100 {
            let p = Fmt.percent(pace.projected)
            let s = Text(L(" · 届时约 \(p)", " · ~\(p) by then", ja: " · その時点で約 \(p)", ko: " · 그때 약 \(p)"))
            line = line + (pace.level == .normal ? s : s.foregroundColor(pace.level.color))
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
