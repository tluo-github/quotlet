import Combine
import Foundation

// 多台 Mac 共享额度与今日用量：
// - 每台 Mac 照常只上报本机读到的数据（CloudSync），这里下载的云端快照只用于显示，不再回传，避免重复统计。
// - 同一服务账号的 5 小时 / 每周额度是同一份数据，取各台 Mac 中采集时间最新的一份，不能相加。
// - 例如只装了 Antigravity CLI 的 Mac 读不到 Gemini 额度，就显示另一台装了 Antigravity 的 Mac 上报的额度。

/// 云端只读快照，与本机扫描结果分开。
struct SharedQuota: Decodable, Identifiable {
    let device_id: String
    let device_name: String?
    let provider: String
    let account_key: String?
    let plan: String?
    let fetched_at: Double
    let limits: [SharedLimit]

    var id: String { provider + ":" + (account_key ?? "default") }
    var observedAt: Date { Date(timeIntervalSince1970: fetched_at / 1000) }

    /// 与本机 Codex 逻辑一致：已过重置时间的窗口按 0% 显示。
    func limitItems(now: Date) -> [LimitItem] {
        limits.enumerated().map { index, l in
            let reset = l.resets_at.map { Date(timeIntervalSince1970: $0 / 1000) }
            let expired = reset.map { $0 <= now } ?? false
            return LimitItem(id: "shared-\(id)-\(index)", kind: l.kind, title: l.title ?? l.kind,
                             percent: expired ? 0 : l.percent, severity: expired ? nil : l.severity,
                             resetsAt: expired ? nil : reset, scope: l.scope)
        }
    }

    func snapshot(now: Date) -> UsageSnapshot {
        UsageSnapshot(limits: limitItems(now: now), breakdown: [], breakdownStart: nil, extra: nil, plan: plan)
    }
}

struct SharedLimit: Decodable {
    let kind: String
    let title: String?
    let percent: Double
    let severity: String?
    let resets_at: Double?
    let scope: String?
}

struct SharedToday: Decodable {
    let day: String
    let tokens_in: Int?
    let tokens_out: Int?
    let tokens_cache_read: Int?
    let tokens_cache_write: Int?
    let requests: Int?
    var tokens: TokenCount {
        TokenCount(input: tokens_in ?? 0, output: tokens_out ?? 0, cacheRead: tokens_cache_read ?? 0, cacheWrite: tokens_cache_write ?? 0)
    }
}

struct SharedDevice: Decodable, Identifiable {
    let id: String
    let name: String
    let online: Bool?
}

struct SharedOverview: Decodable {
    /// 每台 Mac 每个来源一行；用全部行而不是 shared_usage，这样本机那行最新时仍能拿到其他 Mac 的数据
    let usage: [SharedQuota]
    let today: SharedToday?
    let devices: [SharedDevice]
}

enum SharedQuotaResolver {
    /// 返回比本机更新的其他 Mac 快照；本机更新或没有其他 Mac 的数据时返回 nil（用本机数据）。
    static func newest(_ rows: [SharedQuota], provider: String, account: String = "default",
                       localObservedAt: Date?, excludingDevice: String?) -> SharedQuota? {
        let candidate = rows.filter {
            $0.provider == provider && ($0.account_key ?? "default") == account && !$0.limits.isEmpty
                && $0.device_id != excludingDevice
        }.max { $0.fetched_at < $1.fetched_at }
        guard let candidate else { return nil }
        if let localObservedAt, candidate.observedAt.timeIntervalSince(localObservedAt) <= 0.001 { return nil }
        return candidate
    }
}

/// 登录后每 2 分钟拉一次 /api/overview（面板打开时也会刷新）。
@MainActor
final class SharedCloud: ObservableObject {
    static let shared = SharedCloud()

    @Published private(set) var quotas: [SharedQuota] = []
    @Published private(set) var today: SharedToday?
    @Published private(set) var macCount = 0

    private var timer: Timer?
    private var fetching = false
    private var lastFetch = Date.distantPast
    private var userWatch: AnyCancellable?
    private static let interval: TimeInterval = 120

    private init() {
        userWatch = Cloud.shared.$user.map { $0?.id }.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in
                self?.quotas = []
                self?.today = nil
                self?.macCount = 0
                self?.lastFetch = .distantPast
                self?.refresh()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 跨设备合并只在多台 Mac 时有意义
    var hasOtherMacs: Bool { macCount > 1 }

    func quota(_ provider: Source, localObservedAt: Date?) -> SharedQuota? {
        guard CloudSync.shared.isActive else { return nil }
        return SharedQuotaResolver.newest(quotas, provider: provider.rawValue,
                                          localObservedAt: localObservedAt, excludingDevice: Cloud.shared.deviceId)
    }

    /// 只有今天的日期与本机一致时才用（跨过午夜后等下一次拉取）
    func todayTotal(now: Date) -> SharedToday? {
        guard CloudSync.shared.isActive, hasOtherMacs, let today, today.day == Self.dayString(now) else { return nil }
        return today
    }

    func refresh(force: Bool = false) {
        guard CloudSync.shared.isActive, let token = Cloud.shared.token, !fetching else { return }
        if !force && Date().timeIntervalSince(lastFetch) < Self.interval - 5 { return }
        fetching = true
        lastFetch = Date()
        let day = Self.dayString(Date())
        Task {
            defer { fetching = false }
            guard let (data, status) = try? await Cloud.request("GET", "/api/overview?day=\(day)", token: token),
                  status == 200,
                  let o = try? JSONDecoder().decode(SharedOverview.self, from: data) else { return }
            quotas = o.usage
            today = o.today
            macCount = o.devices.count
        }
    }

    static func dayString(_ d: Date) -> String {
        let c = Fmt.calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
