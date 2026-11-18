import AppKit
import Foundation
import ServiceManagement

@MainActor
final class Store: ObservableObject {
    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    /// 上次失败是网络不通或被地区拒绝（403），界面上提示去设置代理
    @Published private(set) var needsProxyHint = false
    /// 上次失败是不是被限流（429）。限流时不能每分钟重试，否则限流会一直持续。
    private var rateLimited = false

    @Published private(set) var local: LocalSnapshot?
    @Published private(set) var isScanning = false

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
            if let (cached, _) = UsageCache.load() { usage = cached }
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
    /// 本地日志扫描间隔（秒）。有缓存，没变化的文件不会重读。
    private let scanInterval: TimeInterval = 60

    private let scanner = SessionScanner()
    /// 本机日志读最近多少天（会话列表、今天、按小时的图用；更早的历史看 HistoryStore 的每日汇总）
    static let scanDays = 31

    /// Codex 的额度（没装或没用过 Codex 时为空）
    func codexLimits(now: Date) -> [LimitItem] { local?.codexLimits?.limitItems(now: now) ?? [] }
    private var timers: [Timer] = []

    init() {
        Network.registerDefaults()
        Notifier.registerDefaults()
        UserDefaults.standard.register(defaults: ["refreshMinutes": 5])
        let d = UserDefaults.standard
        refreshMinutes = Self.refreshChoices.contains(d.integer(forKey: "refreshMinutes")) ? d.integer(forKey: "refreshMinutes") : 5
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
        let initialAppearance = appearance
        DispatchQueue.main.async { Self.applyAppearance(initialAppearance) }

        // 先显示上次缓存的数据，再去网络刷新
        if let (cached, date) = UsageCache.load() {
            usage = cached
            lastUpdated = date
            CloudSync.shared.usageUpdated(cached, at: date)
        }

        Notifier.shared.setup()
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

    /// 状态栏只在没有数据又出错时显示一个警告图标，其余时候只有文字，省地方。
    var menuBarShowsWarning: Bool { usage == nil && errorMessage != nil }

    var menuBarText: String {
        guard let u = usage else { return errorMessage == nil ? "…" : "—" }
        let s = u.session.map { "\(Int($0.percent))%" } ?? "—"
        let w = u.weekly.map { "\(Int($0.percent))%" } ?? "—"
        if menuBarStyle == "compact" { return "\(s) \(w)" }
        return L("5h \(s) 周 \(w)", "5h \(s) Wk \(w)", ja: "5h \(s) 週 \(w)", ko: "5h \(s) 주 \(w)")
    }

    var menuBarSymbol: String {
        if usage == nil && errorMessage != nil { return "exclamationmark.triangle" }
        let p = usage?.session?.percent ?? 0
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
        refreshLocal()
    }

    /// 打开面板时调用：距上次刷新超过 2 分钟、且没被限流才重新请求接口，避免频繁打开面板时请求过多。
    func refreshIfStale() {
        let stale = lastUpdated.map { Date().timeIntervalSince($0) > 120 } ?? true
        if stale && !rateLimited { refreshUsage() }
        refreshLocal()
    }

    func refreshUsage() {
        // -offline YES：截图 / 录屏时只用本地缓存，不请求接口
        if UserDefaults.standard.bool(forKey: "offline") { return }
        guard !isLoading else { return }
        isLoading = true
        lastAttempt = Date()
        Task {
            do {
                let fresh = try await UsageAPI.fetch()
                usage = fresh
                lastUpdated = Date()
                errorMessage = nil
                rateLimited = false
                needsProxyHint = false
                Notifier.shared.evaluate(fresh)
                CloudSync.shared.usageUpdated(fresh, at: Date())
                HistoryStore.shared.record(provider: "claude", items: fresh.limits)
            } catch {
                errorMessage = error.localizedDescription
                if case UsageError.http(429) = error { rateLimited = true } else { rateLimited = false }
                switch error {
                case UsageError.network, UsageError.forbidden: needsProxyHint = true
                default: needsProxyHint = false
                }
            }
            isLoading = false
        }
    }

    func refreshLocal() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let snap = await scanner.scan(days: Self.scanDays)
            local = Demo.enabled ? Demo.anonymize(snap) : snap
            isScanning = false
            HistoryStore.shared.merge(local ?? snap, scannedDays: Self.scanDays)   // 演示模式用匿名后的项目名
            if let c = snap.codexLimits { HistoryStore.shared.record(provider: "codex", items: c.limitItems(now: Date()), at: c.observedAt) }
            // 网站还不区分来源，先只上报 Claude 的会话和 token
            CloudSync.shared.localUpdated(snap.only(.claude))   // 演示模式下 CloudSync 自己不上报
        }
    }

    /// 用当前代理设置请求一次额度接口（不回退直连），成功的话顺便更新数据。
    func testConnection() {
        guard !isTesting else { return }
        isTesting = true
        connectionTest = nil
        let viaProxy = proxyEnabled
        Task {
            let start = Date()
            do {
                usage = try await UsageAPI.fetch(allowFallback: false)
                lastUpdated = Date()
                errorMessage = nil
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                connectionTest = (true, viaProxy ? L("通过代理连接成功，用时 \(ms) 毫秒", "Connected via proxy in \(ms) ms", ja: "プロキシ経由で接続しました（\(ms) ms）", ko: "프록시로 연결됨 (\(ms) ms)")
                                                   : L("直连成功，用时 \(ms) 毫秒", "Connected directly in \(ms) ms", ja: "直接接続しました（\(ms) ms）", ko: "직접 연결됨 (\(ms) ms)"))
            } catch {
                connectionTest = (false, error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func notificationsChanged() {
        notificationTest = nil
        if notifyLow || notifyFull || notifyReset { Notifier.shared.requestAuthorization() }
        if let u = usage { Notifier.shared.evaluate(u) }   // 立刻按新设置重排「重置提醒」
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
