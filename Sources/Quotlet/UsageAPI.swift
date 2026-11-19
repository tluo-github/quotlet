import Foundation
import LocalAuthentication
import Security

// MARK: - 数据模型

struct LimitItem: Identifiable {
    let id: String
    let kind: String
    let title: String
    var percent: Double
    let severity: String?
    let resetsAt: Date?
    /// weekly_scoped 的范围名（Opus / Sonnet …），上报给网站自己拼标题
    var scope: String? = nil
    var isEstimated = false

    var percentText: String {
        isEstimated ? "≈" + String(format: "%.1f%%", percent) : Fmt.percent(percent)
    }
}

struct BreakdownRow: Identifiable {
    let id: String
    let name: String
    let percent: Double
}

struct ExtraUsageInfo {
    let enabled: Bool
    let used: Double?
    let limit: Double?
    let currency: String
}

struct UsageSnapshot {
    let limits: [LimitItem]
    let breakdown: [BreakdownRow]
    let breakdownStart: Date?
    let extra: ExtraUsageInfo?
    let plan: String?

    var session: LimitItem? { limits.first { $0.kind == "session" } }
    var weekly: LimitItem? { limits.first { $0.kind == "weekly_all" } }

    /// 所有额度里最差的状态，用于标题旁的健康标签。
    var overallLevel: Level {
        let levels = limits.map { Level(percent: $0.percent, severity: $0.severity) }
        if levels.contains(.critical) { return .critical }
        if levels.contains(.warning) { return .warning }
        return .normal
    }
}

enum UsageError: LocalizedError {
    case disabled
    case authorizationRequired
    case noCredentials
    case expired
    case forbidden
    case http(Int)
    case network(String)
    case decode

    var errorDescription: String? {
        switch self {
        case .disabled:
            return L("Claude 额度接口已关闭，本机 token 统计不受影响。", "Claude quota API is off. Local token stats still work.", ja: "Claude の使用枠 API はオフです。ローカルのトークン集計は利用できます。", ko: "Claude 한도 API가 꺼져 있습니다. 로컬 토큰 통계는 계속 작동합니다.")
        case .authorizationRequired:
            return L("请在设置的「额度接口」中允许访问钥匙串。", "Allow Keychain access under Quota API in Settings.", ja: "設定の「使用枠 API」でキーチェーンへのアクセスを許可してください。", ko: "설정의 ‘한도 API’에서 키체인 접근을 허용하세요.")
        case .noCredentials:
            return L("没找到 Claude Code 的登录信息。请先在终端运行 claude 并登录。", "No Claude Code login found. Run `claude` in Terminal and sign in first.", ja: "Claude Code のログイン情報が見つかりません。ターミナルで claude を実行してログインしてください。", ko: "Claude Code 로그인 정보를 찾을 수 없습니다. 터미널에서 claude를 실행해 로그인하세요.")
        case .expired:
            return L("登录凭证已过期。打开 Claude Code 随便发一句话，凭证就会自动刷新。", "Your Claude Code login has expired. Send any message in Claude Code to refresh it.", ja: "Claude Code のログインが期限切れです。Claude Code で何かメッセージを送ると更新されます。", ko: "Claude Code 로그인이 만료되었습니다. Claude Code에서 아무 메시지나 보내면 갱신됩니다.")
        case .forbidden:
            return L("Anthropic 拒绝了访问（HTTP 403）。所在地区可能不能直连，请在设置里开启代理。", "Anthropic refused the request (HTTP 403). Your region may need a proxy; enable it in Settings.", ja: "Anthropic がリクエストを拒否しました（HTTP 403）。お住まいの地域ではプロキシが必要な場合があります。設定で有効にしてください。", ko: "Anthropic이 요청을 거부했습니다(HTTP 403). 지역에 따라 프록시가 필요할 수 있으니 설정에서 켜세요.")
        case .http(429):
            return L("请求太频繁，被限流了，稍后会自动重试。", "Rate limited. Will retry automatically.", ja: "リクエストが多すぎます。自動で再試行します。", ko: "요청이 너무 많습니다. 자동으로 다시 시도합니다.")
        case .http(let code):
            return L("Anthropic 接口返回错误（HTTP \(code)）。", "Anthropic API returned an error (HTTP \(code)).", ja: "Anthropic API がエラーを返しました（HTTP \(code)）。", ko: "Anthropic API가 오류를 반환했습니다(HTTP \(code)).")
        case .network(let msg):
            return L("网络连接失败：\(msg)。如果你需要代理才能访问 Anthropic，请在设置里开启并填写代理。", "Network error: \(msg). If you need a proxy to reach Anthropic, enable it in Settings.", ja: "ネットワークエラー：\(msg)。Anthropic への接続にプロキシが必要な場合は、設定で有効にしてください。", ko: "네트워크 오류: \(msg). Anthropic에 접속하려면 프록시가 필요한 경우 설정에서 켜세요.")
        case .decode:
            return L("接口返回的数据看不懂，可能接口格式变了。", "Unexpected response from the API. The format may have changed.", ja: "API から想定外の応答がありました。形式が変わった可能性があります。", ko: "API 응답이 예상과 다릅니다. 형식이 바뀌었을 수 있습니다.")
        }
    }
}

// MARK: - 凭证

struct Credentials {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
}

enum CredentialStore {
    /// 只有开启额度接口后才读凭证；只有设置里的授权操作允许钥匙串交互。
    static func load(allowInteraction: Bool = false) throws -> Credentials {
        guard UsageAPI.isEnabled() else { throw UsageError.disabled }
        let (data, status) = readKeychain(allowInteraction: allowInteraction)
        if let data, let c = parse(data) { return c }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let c = parse(data) { return c }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            throw UsageError.authorizationRequired
        }
        throw UsageError.noCredentials
    }

    private static func readKeychain(allowInteraction: Bool) -> (Data?, OSStatus) {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "Claude Code-credentials",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        context.localizedReason = L("读取 Claude Code 登录凭证以查询额度",
                                    "Read your Claude Code login to check quota",
                                    ja: "使用枠を確認するため Claude Code のログイン情報を読み取ります",
                                    ko: "한도 조회를 위해 Claude Code 로그인 정보를 읽습니다")
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = KeychainAccess.perform(allowInteraction: allowInteraction) {
            SecItemCopyMatching(query as CFDictionary, &result)
        }
        return (status == errSecSuccess ? result as? Data : nil, status)
    }

    private static func parse(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let o = root["claudeAiOauth"] as? [String: Any],
              let token = o["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let exp = (o["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(accessToken: token, expiresAt: exp, subscriptionType: o["subscriptionType"] as? String)
    }
}

// MARK: - 接口

enum UsageAPI {
    static let enabledKey = "claudeUsageAPIEnabled"
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: enabledKey) }
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// allowFallback：代理失败时是否再试直连。「测试连接」时传 false，才能真正测出代理通不通。
    static func fetch(allowFallback: Bool = true, allowInteraction: Bool = false) async throws -> UsageSnapshot {
        guard isEnabled() else { throw UsageError.disabled }
        // 不按本地 expiresAt 提前放弃：凭证过期后 Claude Code 下次发消息时才会换新，
        // 这里照常请求，服务器拒绝（401）才算过期，Store 会每分钟重试。
        let cred = try await Task.detached(priority: .utility) { try CredentialStore.load(allowInteraction: allowInteraction) }.value
        try Task.checkCancellation()
        guard isEnabled() else { throw UsageError.disabled }

        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(cred.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, resp) = try await send(req, allowFallback: allowFallback)
        try Task.checkCancellation()
        guard isEnabled() else { throw UsageError.disabled }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw UsageError.expired }
        if code == 403 { throw UsageError.forbidden }
        guard code == 200 else { throw UsageError.http(code) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.decode
        }
        UsageCache.save(data, plan: cred.subscriptionType)
        return parse(root, plan: cred.subscriptionType)
    }

    /// 先走代理，失败再直连。
    private static func send(_ req: URLRequest, allowFallback: Bool) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for session in Network.sessions(allowFallback: allowFallback) {
            do { return try await session.data(for: req) } catch { lastError = error }
        }
        throw UsageError.network(lastError?.localizedDescription ?? L("未知错误", "unknown error", ja: "不明なエラー", ko: "알 수 없는 오류"))
    }

    static func parse(_ root: [String: Any], plan: String?) -> UsageSnapshot {
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

        var limits: [LimitItem] = []
        if let arr = root["limits"] as? [[String: Any]] {
            for (i, l) in arr.enumerated() {
                let kind = l["kind"] as? String ?? "unknown"
                let scope = l["scope"] as? [String: Any]
                let scopeName = ((scope?["model"] as? [String: Any])?["display_name"] as? String)
                    ?? ((scope?["surface"] as? [String: Any])?["display_name"] as? String)
                    ?? (scope?["surface"] as? String)
                let title: String
                switch kind {
                case "session": title = L("当前会话 · 5 小时", "Current session · 5 hours", ja: "現在のセッション · 5 時間", ko: "현재 세션 · 5시간")
                case "weekly_all": title = L("本周 · 所有模型", "This week · all models", ja: "今週 · すべてのモデル", ko: "이번 주 · 모든 모델")
                case "weekly_scoped": title = L("本周 · ", "This week · ", ja: "今週 · ", ko: "이번 주 · ") + (scopeName ?? L("指定范围", "scoped", ja: "対象範囲", ko: "지정 범위"))
                default: title = scopeName.map { "\(kind) · \($0)" } ?? kind
                }
                limits.append(LimitItem(
                    id: "\(i)-\(kind)-\(scopeName ?? "")",
                    kind: kind,
                    title: title,
                    percent: num(l["percent"]) ?? 0,
                    severity: l["severity"] as? String,
                    resetsAt: Fmt.parseISO(l["resets_at"] as? String),
                    scope: scopeName))
            }
        }
        // 老格式兜底
        if limits.isEmpty {
            let pairs: [(String, String, String)] = [
                ("five_hour", "session", L("当前会话 · 5 小时", "Current session · 5 hours", ja: "現在のセッション · 5 時間", ko: "현재 세션 · 5시간")),
                ("seven_day", "weekly_all", L("本周 · 所有模型", "This week · all models", ja: "今週 · すべてのモデル", ko: "이번 주 · 모든 모델")),
                ("seven_day_opus", "weekly_scoped", L("本周 · Opus", "This week · Opus", ja: "今週 · Opus", ko: "이번 주 · Opus")),
                ("seven_day_sonnet", "weekly_scoped", L("本周 · Sonnet", "This week · Sonnet", ja: "今週 · Sonnet", ko: "이번 주 · Sonnet")),
            ]
            for (key, kind, title) in pairs {
                guard let w = root[key] as? [String: Any], let u = num(w["utilization"]) else { continue }
                limits.append(LimitItem(id: key, kind: kind, title: title, percent: u, severity: nil,
                                        resetsAt: Fmt.parseISO(w["resets_at"] as? String),
                                        scope: key.hasSuffix("_opus") ? "Opus" : key.hasSuffix("_sonnet") ? "Sonnet" : nil))
            }
        }

        var breakdown: [BreakdownRow] = []
        var breakdownStart: Date?
        if let b = root["seven_day_breakdown"] as? [String: Any] {
            breakdownStart = Fmt.parseISO(b["window_started_at"] as? String)
            for r in (b["rows"] as? [[String: Any]]) ?? [] {
                let key = r["key"] as? String ?? ""
                let name: String
                switch key {
                case "claude_code": name = "Claude Code"
                case "chat": name = L("网页 / App 聊天", "Web & app chats", ja: "Web とアプリのチャット", ko: "웹 및 앱 채팅")
                case "cowork": name = "Cowork"
                case "other": name = L("其他", "Other", ja: "その他", ko: "기타")
                default: name = r["display_name"] as? String ?? key
                }
                breakdown.append(BreakdownRow(id: key, name: name, percent: num(r["percent"]) ?? 0))
            }
        }

        var extra: ExtraUsageInfo?
        if let e = root["extra_usage"] as? [String: Any] {
            let enabled = e["is_enabled"] as? Bool ?? false
            var used: Double?, limit: Double?
            var currency = e["currency"] as? String ?? "USD"
            if let spend = root["spend"] as? [String: Any] {
                func money(_ v: Any?) -> Double? {
                    guard let m = v as? [String: Any], let a = num(m["amount_minor"]) else { return nil }
                    return a / pow(10, num(m["exponent"]) ?? 2)
                }
                used = money(spend["used"])
                limit = money(spend["limit"])
                currency = ((spend["used"] as? [String: Any])?["currency"] as? String) ?? currency
            }
            extra = ExtraUsageInfo(enabled: enabled, used: used, limit: limit, currency: currency)
        }

        return UsageSnapshot(limits: limits, breakdown: breakdown, breakdownStart: breakdownStart,
                             extra: extra, plan: plan)
    }
}

// MARK: - 本地缓存

/// 把上一次成功的接口返回存到 ~/Library/Caches/<bundle id>/usage.json。
/// 启动时先显示缓存，网络失败或被限流时也有数据可看。
enum UsageCache {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Quotabar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage.json")
    }

    static func save(_ data: Data, plan: String?) {
        let wrapper: [String: Any] = ["plan": plan ?? "", "body": String(decoding: data, as: UTF8.self)]
        if let out = try? JSONSerialization.data(withJSONObject: wrapper) { try? out.write(to: url) }
    }

    /// 读缓存，返回解析后的数据和缓存时间。标题等文字按当前语言重新生成。
    static func load() -> (UsageSnapshot, Date)? {
        guard let data = try? Data(contentsOf: url),
              let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = (wrapper["body"] as? String)?.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        let plan = (wrapper["plan"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (UsageAPI.parse(root, plan: plan), date)
    }
}

// MARK: - 代理

enum Network {
    enum Key {
        static let enabled = "proxyEnabled"
        static let host = "proxyHost"
        static let port = "proxyPort"
    }

    /// 系统语言是中文、或地区在中国大陆 / 香港 / 澳门时，默认开启代理 127.0.0.1:7890（Clash 常用端口）。
    /// 看的是系统设置而不是界面语言：界面切成英文的大陆用户一样需要代理。
    /// 代理连不上时会自动退回直连，所以不需要代理的人开着也没关系。
    static var likelyNeedsProxy: Bool {
        let region = Locale.current.region?.identifier ?? ""
        return Lang.system == .zh || ["CN", "HK", "MO"].contains(region)
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.enabled: likelyNeedsProxy,
            Key.host: "127.0.0.1",
            Key.port: 7890,
        ])
    }

    private static var cache: [String: URLSession] = [:]
    private static let lock = NSLock()

    static func sessions(allowFallback: Bool) -> [URLSession] {
        let d = UserDefaults.standard
        let host = (d.string(forKey: Key.host) ?? "").trimmingCharacters(in: .whitespaces)
        let port = d.integer(forKey: Key.port)
        var list: [URLSession] = []
        if d.bool(forKey: Key.enabled), !host.isEmpty, (1...65535).contains(port) {
            list.append(session(key: "\(host):\(port)") {
                let cfg = URLSessionConfiguration.ephemeral
                cfg.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: 1,
                    kCFNetworkProxiesHTTPProxy as String: host,
                    kCFNetworkProxiesHTTPPort as String: port,
                    kCFNetworkProxiesHTTPSEnable as String: 1,
                    kCFNetworkProxiesHTTPSProxy as String: host,
                    kCFNetworkProxiesHTTPSPort as String: port,
                ]
                return cfg
            })
            if !allowFallback { return list }
        }
        list.append(session(key: "direct") { .ephemeral })  // 系统网络设置（系统代理或直连）
        return list
    }

    private static func session(key: String, make: () -> URLSessionConfiguration) -> URLSession {
        lock.lock(); defer { lock.unlock() }
        if let s = cache[key] { return s }
        let cfg = make()
        cfg.timeoutIntervalForRequest = 20
        let s = URLSession(configuration: cfg)
        cache[key] = s
        return s
    }
}
