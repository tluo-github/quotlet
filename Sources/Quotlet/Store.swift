import AppKit
import Foundation
import ServiceManagement

@MainActor
final class Store: ObservableObject {
    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var needsCredentialAuthorization = false
    @Published private(set) var isLoading = false
    /// 上次失败是网络不通或被地区拒绝（403），界面上提示去设置代理
    @Published private(set) var needsProxyHint = false
    /// 上次失败是不是被限流（429）。限流时不能每分钟重试，否则限流会一直持续。
    private var rateLimited = false

    @Published private(set) var local: LocalSnapshot?
    @Published private(set) var isScanning = false

    /// 默认只读本机日志。只有用户主动开启后，才可读取 Claude 登录凭证并查询额度接口。
    @Published var usageAPIEnabled: Bool {
        didSet {
            guard usageAPIEnabled != oldValue else { return }
            quotaEstimator = ClaudeQuotaEstimator()
            UserDefaults.standard.set(usageAPIEnabled, forKey: UsageAPI.enabledKey)
            apiGeneration += 1
            usageTask?.cancel()
            connectionTask?.cancel()
            isLoading = false
            isTesting = false
            errorMessage = nil
            needsCredentialAuthorization = false
            needsProxyHint = false
            rateLimited = false
            connectionTest = nil
            if usageAPIEnabled {
                if let (cached, date) = UsageCache.load() {
                    usage = cached
                    lastUpdated = date
                    quotaEstimator.observe(cached, at: date, messages: [])
                }
                else { lastUpdated = nil }
                refreshUsage()
            } else {
                usage = nil
                Notifier.shared.cancelResetReminders(provider: "Claude")
                lastUpdated = local == nil ? nil : Date()
            }
        }
    }
    private var apiGeneration = 0
    private var usageTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var quotaEstimator = ClaudeQuotaEstimator()

    func displayedClaudeUsage(now: Date) -> UsageSnapshot? {
        guard let usage else { return nil }
        return quotaEstimator.display(usage, messages: local?.messages ?? [], now: now)
    }

    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    // 代理设置（存在 UserDefaults，Network 发请求时读取）
    @Published var proxyEnabled: Bool {
        didSet { UserDefaults.standard.set(proxyEnabled, forKey: Network.Key.enabled); connectionTest = nil }
    }
    @Published var proxyHost: String {
        didSet { UserDefaults.standard.set(proxyHost, forKey: Network.Key.host); connectionTest = nil }
    }
    @Published var proxyPort: Int {
        didSet { UserDefaults.standard.set(proxyPort, forKey: Network.Key.port); connectionTest = nil }
    }
    /// 外观："" = 跟随系统，"light" / "dark"。设在 NSApp 上，面板窗口跟着变。
    @Published var appearance: String {
        didSet {
            UserDefaults.standard.set(appearance, forKey: "appearance")
            Self.applyAppearance(appearance)
        }
    }

    static func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    /// 界面语言："" = 跟随系统，否则 zh / en / ja / ko
    @Published var language: String {
        didSet {
            if language.isEmpty { UserDefaults.standard.removeObject(forKey: "language") }
            else { UserDefaults.standard.set(language, forKey: "language") }
            // 额度标题是解析时按语言生成的：先用缓存按新语言重新解析，再去网络刷新
            if usageAPIEnabled, let (cached, _) = UsageCache.load() { usage = cached }
            refreshUsage()
        }
    }
    @Published var notifyLow: Bool {
        didSet { UserDefaults.standard.set(notifyLow, forKey: Notifier.Key.low); notificationsChanged() }
    }
    @Published var notifyThreshold: Int {
        didSet { UserDefaults.standard.set(notifyThreshold, forKey: Notifier.Key.threshold); notificationsChanged() }
    }
    @Published var notifyFull: Bool {
        didSet { UserDefaults.standard.set(notifyFull, forKey: Notifier.Key.full); notificationsChanged() }
    }
    @Published var notifyReset: Bool {
        didSet { UserDefaults.standard.set(notifyReset, forKey: Notifier.Key.reset); notificationsChanged() }
    }
    /// 测试通知的结果：nil = 还没测，true = 已发送，false = 没有权限
    @Published private(set) var notificationTest: Bool?
    @Published private(set) var connectionTest: (ok: Bool, text: String)?
    @Published private(set) var isTesting = false

    /// 额度接口刷新间隔（分钟），设置里可选。Anthropic 没公开这个接口的频率限制，
    /// 实测短时间请求几十次会被限流，默认 5 分钟。
    static let refreshChoices = [1, 2, 5, 10, 15, 30]
    @Published var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes") }
    }
    private var apiInterval: TimeInterval { TimeInterval(refreshMinutes * 60) }
    /// 被限流后至少等这么久再试
    private let rateLimitBackoff: TimeInterval = 300
    private let retryInterval: TimeInterval = 60
    /// 文件监听之外的每分钟兜底扫描，兼顾跨日统计和文件事件丢失。
    private let scanInterval: TimeInterval = 60

    private let scanner = SessionScanner()
    private var logWatcher: SessionLogWatcher?
    private var pendingLocalRefresh = false
    /// 本机日志读最近多少天（会话列表、今天、按小时的图用；更早的历史看 HistoryStore 的每日汇总）
    static let scanDays = 31

    /// Codex 的额度（没装或没用过 Codex 时为空）
    func codexLimits(now: Date) -> [LimitItem] { local?.codexLimits?.limitItems(now: now) ?? [] }
    /// Gemini 的额度（没装或没用过 Antigravity 时为空）
    func geminiLimits(now: Date) -> [LimitItem] { local?.geminiLimits?.limitItems(now: now) ?? [] }
    private var timers: [Timer] = []

    init() {
        Network.registerDefaults()
        Notifier.registerDefaults()
        UserDefaults.standard.register(defaults: ["refreshMinutes": 10])
        let d = UserDefaults.standard
        usageAPIEnabled = UsageAPI.isEnabled()
        refreshMinutes = Self.refreshChoices.contains(d.integer(forKey: "refreshMinutes")) ? d.integer(forKey: "refreshMinutes") : 10
        notifyLow = d.bool(forKey: Notifier.Key.low)
        notifyFull = d.bool(forKey: Notifier.Key.full)
        notifyThreshold = Int(Notifier.lowThreshold)
        notifyReset = d.bool(forKey: Notifier.Key.reset)
        proxyEnabled = d.bool(forKey: Network.Key.enabled)
        proxyHost = d.string(forKey: Network.Key.host) ?? "127.0.0.1"
        proxyPort = d.integer(forKey: Network.Key.port)
        language = d.string(forKey: "language") ?? ""
        appearance = d.string(forKey: "appearance") ?? ""
        menuBarStyle = d.string(forKey: "menuBarStyle") ?? "full"
        menuBarSource = d.string(forKey: "menuBarSource").flatMap(Source.init(rawValue:)) ?? .claude
        let initialAppearance = appearance
        DispatchQueue.main.async { Self.applyAppearance(initialAppearance) }

        // 先显示上次缓存的数据，再去网络刷新
        if usageAPIEnabled, let (cached, date) = UsageCache.load() {
            usage = cached
            lastUpdated = date
            quotaEstimator.observe(cached, at: date, messages: [])
            CloudSync.shared.usageUpdated(cached, at: date)
        }

        Notifier.shared.setup { [weak self] in self?.evaluateNotifications() }
        _ = HookManager.shared
        _ = RemoteCommandManager.shared
        refreshAll()
        // 开发用：-openHistory YES 启动后直接打开用量历史窗口（截图检查用）
        if UserDefaults.standard.bool(forKey: "openHistory") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                HistoryWindowController.shared.show(store: self)
            }
        }
        if Showcase.enabled {
            Task { @MainActor in Showcase.show(store: self) }
        }
        if let dir = Snapshot.directory {
            Task { await Snapshot.run(store: self, dir: dir) }
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        logWatcher = SessionLogWatcher(paths: [
            home.appendingPathComponent(".claude/projects"),
            CodexLogs.home.appendingPathComponent("sessions"),
            CodexLogs.home.appendingPathComponent("archived_sessions"),
            CodexLogs.home.appendingPathComponent("session_index.jsonl"),
            CodexLogs.home.appendingPathComponent("external_agent_session_imports.json"),
            GeminiLogs.brainDir,
            GeminiLogs.home.appendingPathComponent("antigravity/daemon"),
            GeminiLogs.dbPath,
        ]) { [weak self] in self?.refreshLocal() }
        if !Showcase.enabled && !Demo.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { LegacyApp.check() }
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocal() }
        })
    }

    /// 状态栏样式："full" = 5h 41% 周 62%，"compact" = 41% 62%
    @Published var menuBarStyle: String {
        didSet { UserDefaults.standard.set(menuBarStyle, forKey: "menuBarStyle") }
    }

    @Published var menuBarSource: Source {
        didSet { UserDefaults.standard.set(menuBarSource.rawValue, forKey: "menuBarSource") }
    }

    private var menuBarLimits: (session: LimitItem?, weekly: LimitItem?) {
        switch menuBarSource {
        case .claude:
            let displayed = displayedClaudeUsage(now: Date())
            return (displayed?.session, displayed?.weekly)
        case .codex:
            let limits = codexLimits(now: Date())
            return (limits.first { $0.kind == "session" }, limits.first { $0.kind == "weekly_all" })
        case .gemini:
            let limits = geminiLimits(now: Date())
            return (limits.first { $0.kind == "session" }, limits.first { $0.kind == "weekly_all" } ?? limits.first)
        }
    }

    var menuBarShowsWarning: Bool { menuBarSource == .claude && usage == nil && errorMessage != nil }

    var menuBarText: String {
        if menuBarSource == .claude, !usageAPIEnabled {
            guard let local else { return "—" }
            let start = Fmt.calendar.startOfDay(for: Date())
            let total = local.messages.lazy.filter { $0.source == .claude && $0.ts >= start }.reduce(0) { $0 + $1.tokens.total }
            return L("今日 \(Fmt.tokens(total))", "Today \(Fmt.tokens(total))", ja: "今日 \(Fmt.tokens(total))", ko: "오늘 \(Fmt.tokens(total))")
        }
        let limits = menuBarLimits
        guard limits.session != nil || limits.weekly != nil else { return "—" }
        // Free 套餐等只有周额度时，不显示多余的「5h —」
        if limits.session == nil, let weekly = limits.weekly?.percentText {
            if menuBarStyle == "compact" { return weekly }
            return L("周 \(weekly)", "Wk \(weekly)", ja: "週 \(weekly)", ko: "주 \(weekly)")
        }
        let session = limits.session?.percentText ?? "—"
        let weekly = limits.weekly?.percentText ?? "—"
        if menuBarStyle == "compact" { return "\(session) \(weekly)" }
        return L("5h \(session) 周 \(weekly)", "5h \(session) Wk \(weekly)",
                 ja: "5h \(session) 週 \(weekly)", ko: "5h \(session) 주 \(weekly)")
    }

    var menuBarSymbol: String {
        if menuBarSource == .claude, !usageAPIEnabled { return "chart.bar" }
        if menuBarShowsWarning { return "exclamationmark.triangle" }
        let limits = menuBarLimits
        let p = max(limits.session?.percent ?? 0, limits.weekly?.percent ?? 0)
        switch p {
        case 90...: return "gauge.with.dots.needle.100percent"
        case 60...: return "gauge.with.dots.needle.67percent"
        case 30...: return "gauge.with.dots.needle.50percent"
        default: return "gauge.with.dots.needle.33percent"
        }
    }

    /// 每分钟检查一次：上次出错（限流除外）就立即重试，否则到了设定的间隔再刷新。
    private var lastAttempt = Date.distantPast
    private func tick() {
        guard usageAPIEnabled else { return }
        let sinceAttempt = Date().timeIntervalSince(lastAttempt)
        if rateLimited {
            if sinceAttempt >= max(apiInterval, rateLimitBackoff) - 1 { refreshUsage() }
            return
        }
        let age = lastUpdated.map { Date().timeIntervalSince($0) } ?? .infinity
        if errorMessage != nil || age >= apiInterval - 1 { refreshUsage() }
    }

    func refreshAll() {
        refreshUsage()
        refreshLocal(forceGeminiQuota: true)
    }

    func authorizeClaudeQuota() {
        guard needsCredentialAuthorization else { return }
        refreshUsage(allowInteraction: true)
    }

    /// 打开面板时调用：距上次刷新超过 2 分钟、且没被限流才重新请求接口，避免频繁打开面板时请求过多。
    func refreshIfStale() {
        let stale = lastUpdated.map { Date().timeIntervalSince($0) > 120 } ?? true
        if stale && !rateLimited { refreshUsage() }
        refreshLocal()
    }

    private func refreshUsage(allowInteraction: Bool = false) {
        guard usageAPIEnabled else { return }
        // -offline YES：截图 / 录屏时只用本地缓存，不请求接口
        if UserDefaults.standard.bool(forKey: "offline") { return }
        guard !isLoading else { return }
        isLoading = true
        lastAttempt = Date()
        let generation = apiGeneration
        usageTask = Task {
            defer { if generation == apiGeneration { isLoading = false } }
            do {
                let fresh = try await UsageAPI.fetch(allowInteraction: allowInteraction)
                let observedAt = Date()
                let sample = await scanner.scan(days: Self.scanDays)
                guard !Task.isCancelled, usageAPIEnabled, generation == apiGeneration else { return }
                quotaEstimator.observe(fresh, at: observedAt, messages: sample.messages)
                usage = fresh
                lastUpdated = observedAt
                errorMessage = nil
                needsCredentialAuthorization = false
                rateLimited = false
                needsProxyHint = false
                Notifier.shared.evaluate(fresh)
                CloudSync.shared.usageUpdated(fresh, at: Date())
                HistoryStore.shared.record(provider: "claude", items: fresh.limits)
            } catch {
                guard !Task.isCancelled, usageAPIEnabled, generation == apiGeneration else { return }
                errorMessage = error.localizedDescription
                if case UsageError.authorizationRequired = error { needsCredentialAuthorization = true }
                else { needsCredentialAuthorization = false }
                if case UsageError.http(429) = error { rateLimited = true } else { rateLimited = false }
                switch error {
                case UsageError.network, UsageError.forbidden: needsProxyHint = true
                default: needsProxyHint = false
                }
            }
        }
    }

    func refreshLocal(forceGeminiQuota: Bool = false) {
        guard !isScanning else {
            pendingLocalRefresh = true
            return
        }
        isScanning = true
        Task {
            let snap = await scanner.scan(days: Self.scanDays, forceGeminiQuota: forceGeminiQuota)
            local = Demo.enabled ? Demo.anonymize(snap) : snap
            isScanning = false
            if let displayed = displayedClaudeUsage(now: Date()) { Notifier.shared.evaluate(displayed) }
            if !usageAPIEnabled { lastUpdated = Date() }
            HistoryStore.shared.merge(local ?? snap, scannedDays: Self.scanDays)   // 演示模式用匿名后的项目名
            if let c = snap.codexLimits { HistoryStore.shared.record(provider: "codex", items: c.limitItems(now: Date()), at: c.observedAt) }
            if let c = snap.codexLimits {
                Notifier.shared.evaluate(provider: "Codex", limits: c.limitItems(now: Date()))
            }
            if let g = snap.geminiLimits { HistoryStore.shared.record(provider: "gemini", items: g.limitItems(now: Date()), at: g.observedAt) }
            if let g = snap.geminiLimits {
                Notifier.shared.evaluate(provider: "Gemini", limits: g.limitItems(now: Date()))
            }
            CloudSync.shared.localUpdated(snap)   // 演示模式下 CloudSync 自己不上报
            RemoteCommandManager.shared.localUpdated(snap)
            if pendingLocalRefresh {
                pendingLocalRefresh = false
                refreshLocal()
            }
        }
    }

    /// 用当前代理设置请求一次额度接口（不回退直连），成功的话顺便更新数据。
    func testConnection() {
        guard usageAPIEnabled, !isTesting else { return }
        isTesting = true
        connectionTest = nil
        let viaProxy = proxyEnabled
        let generation = apiGeneration
        connectionTask = Task {
            defer { if generation == apiGeneration { isTesting = false } }
            let start = Date()
            do {
                let fresh = try await UsageAPI.fetch(allowFallback: false)
                let observedAt = Date()
                let sample = await scanner.scan(days: Self.scanDays)
                guard !Task.isCancelled, usageAPIEnabled, generation == apiGeneration else { return }
                quotaEstimator.observe(fresh, at: observedAt, messages: sample.messages)
                usage = fresh
                lastUpdated = observedAt
                errorMessage = nil
                needsCredentialAuthorization = false
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                connectionTest = (true, viaProxy ? L("通过代理连接成功，用时 \(ms) 毫秒", "Connected via proxy in \(ms) ms", ja: "プロキシ経由で接続しました（\(ms) ms）", ko: "프록시로 연결됨 (\(ms) ms)")
                                                   : L("直连成功，用时 \(ms) 毫秒", "Connected directly in \(ms) ms", ja: "直接接続しました（\(ms) ms）", ko: "직접 연결됨 (\(ms) ms)"))
            } catch {
                guard !Task.isCancelled, usageAPIEnabled, generation == apiGeneration else { return }
                if case UsageError.authorizationRequired = error { needsCredentialAuthorization = true }
                connectionTest = (false, error.localizedDescription)
            }
        }
    }

    private func notificationsChanged() {
        notificationTest = nil
        if notifyLow || notifyFull || notifyReset {
            Notifier.shared.requestAuthorization { [weak self] granted in
                guard let self, granted else { return }
                self.evaluateNotifications()
            }
            return
        }
        evaluateNotifications()
    }

    private func evaluateNotifications() {
        let now = Date()
        if let u = displayedClaudeUsage(now: now) { Notifier.shared.evaluate(u, now: now) }
        if let c = local?.codexLimits { Notifier.shared.evaluate(provider: "Codex", limits: c.limitItems(now: now), now: now) }
        if let g = local?.geminiLimits { Notifier.shared.evaluate(provider: "Gemini", limits: g.limitItems(now: now), now: now) }
    }

    func sendTestNotification() {
        Notifier.shared.sendTest { [weak self] ok in
            self?.notificationTest = ok
            // 成功的提示 3 秒后恢复成按钮
            if ok {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    if self?.notificationTest == true { self?.notificationTest = nil }
                }
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = L("设置开机启动失败：", "Couldn't change launch at login: ", ja: "ログイン時の起動を変更できませんでした：", ko: "로그인 시 실행을 변경하지 못했습니다: ") + error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
