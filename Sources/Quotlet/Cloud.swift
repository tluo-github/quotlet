import AppKit
import CryptoKit
import Foundation
import IOKit
import Security
import LocalAuthentication

// Quotlet Cloud：登录 app.quotlet.com，以后用来上报额度和会话。
// 默认关闭；没登录时不发任何请求。
//
// 登录流程：在默认浏览器里打开 /login?client=mac，用户用 GitHub 登录后网页跳到
// quotlet://auth?code=…（Info.plist 注册了这个 scheme），再用 code + PKCE verifier 换设备 token。
// token 存在钥匙串里，不放 UserDefaults。

enum CloudConfig {
    /// 开发时可以用 `defaults write app.quotabar cloudBaseURL http://localhost:8787` 指向本地 wrangler dev
    static var base: URL {
        if let s = UserDefaults.standard.string(forKey: "cloudBaseURL"), let u = URL(string: s) { return u }
        return URL(string: "https://app.quotlet.com")!
    }
    /// quotlet:// 是新的；quotabar:// 是改名前的，过渡期两个都认
    static let callbackSchemes: Set<String> = ["quotlet", "quotabar"]
}

struct CloudUser: Codable, Equatable {
    let id: String
    let email: String?
    let name: String?
}

enum CloudError: LocalizedError {
    case http(Int)
    case network(String)
    case keychain

    var errorDescription: String? {
        switch self {
        case .http(let code): return L("服务器返回 \(code)", "Server returned \(code)", ja: "サーバーが \(code) を返しました", ko: "서버가 \(code)을(를) 반환했습니다")
        case .network(let msg): return L("连不上服务器：\(msg)", "Can't reach the server: \(msg)", ja: "サーバーに接続できません：\(msg)", ko: "서버에 연결할 수 없습니다: \(msg)")
        case .keychain: return L("无法写入钥匙串", "Couldn't save to the keychain", ja: "キーチェーンに保存できません", ko: "키체인에 저장할 수 없습니다")
        }
    }
}

@MainActor
final class Cloud: ObservableObject {
    static let shared = Cloud()

    @Published private(set) var user: CloudUser?
    @Published private(set) var deviceId: String?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    var isSignedIn: Bool { user != nil }

    /// 截图 / 录屏模式：不读钥匙串、不联网
    nonisolated static let isPreview = CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--showcase")

    /// 设备 token 缓存在内存里：上报每分钟都要用，不能每次都读钥匙串
    private(set) var token: String?

    /// 正在浏览器里登录：等 quotlet://auth 回调。只存在内存里，app 重启就作废，重新点登录即可。
    private var pending: (state: String, verifier: String, started: Date)?
    private static let userKey = "cloudUser"
    private static let deviceIdKey = "cloudDeviceId"

    private init() {
        // 截图 / 演示模式：不读钥匙串（开发版每次重编译都会触发钥匙串授权弹窗），也不露出真实账号。
        // `-cloudPreviewUser 名字` 可以渲染已登录的样子。
        if Self.isPreview {
            if let name = UserDefaults.standard.string(forKey: "cloudPreviewUser") {
                user = CloudUser(id: "preview", email: "you@example.com", name: name)
            }
            return
        }
        // 开发用：`-cloudBaseURL http://localhost:8787 -cloudDevToken <token>` 直接用本地 wrangler dev 里的测试设备，
        // 不碰钥匙串（只认启动参数，不会存进 UserDefaults）
        if let dev = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["cloudDevToken"] as? String,
           UserDefaults.standard.string(forKey: "cloudBaseURL") != nil {
            token = dev
            user = CloudUser(id: "dev", email: nil, name: "Dev")
            Task { await refreshMe() }
            return
        }
        // 先用上次保存的账号信息显示，再去服务器确认 token 还有效（可能在网页上被移除了）
        if let data = UserDefaults.standard.data(forKey: Self.userKey),
           let u = try? JSONDecoder().decode(CloudUser.self, from: data) {
            token = CloudToken.load()
            if token != nil {
                deviceId = UserDefaults.standard.string(forKey: Self.deviceIdKey)
                user = u
                Task { await refreshMe() }
            }
        }
    }

    // MARK: 登录

    /// 在默认浏览器里新开标签页登录。登录完网页跳到 quotlet://auth?code=…&state=…，
    /// 系统把这个链接交给 AppDelegate → handleCallback。
    /// 别的 app 就算抢注了 quotlet:// 拿到 code 也没用：换 token 还要只在这里的 PKCE verifier。
    func signIn() {
        guard !isBusy else { return }
        errorMessage = nil
        let verifier = Self.randomString(bytes: 32)
        let state = Self.randomString(bytes: 16)
        pending = (state, verifier, Date())
        var comps = URLComponents(url: CloudConfig.base.appendingPathComponent("login"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "mac"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            // 登录网页、验证码邮件用 App 当前的界面语言
            URLQueryItem(name: "lang", value: Lang.current.rawValue),
        ]
        NSWorkspace.shared.open(comps.url!)
    }

    /// 浏览器打开 quotlet://auth?... 时调用
    func handleCallback(_ url: URL) {
        guard let scheme = url.scheme, CloudConfig.callbackSchemes.contains(scheme), url.host == "auth" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        // state 对不上：不是这次登录发起的（或者 app 中途重启过），忽略
        guard let p = pending, let code, state == p.state, Date().timeIntervalSince(p.started) < 15 * 60 else {
            NSLog("[cloud] ignored callback: no matching login in progress")
            errorMessage = L("登录已过期，请重新登录", "Sign-in expired. Please sign in again.", ja: "ログインの有効期限が切れました。もう一度ログインしてください。", ko: "로그인이 만료되었습니다. 다시 로그인하세요.")
            return
        }
        pending = nil
        Task { await exchange(code: code, verifier: p.verifier) }
    }

    private func exchange(code: String, verifier: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            var devObj: [String: Any] = ["name": Host.current().localizedName ?? "Mac", "kind": "mac"]
            if let mid = Self.machineId { devObj["machine_id"] = mid }
            let body: [String: Any] = [
                "code": code,
                "code_verifier": verifier,
                "device": devObj,
                "lang": Lang.current.rawValue,
            ]
            let (data, status) = try await Self.request("POST", "/api/auth/exchange", json: body, token: nil)
            guard status == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = root["token"] as? String,
                  let userObj = root["user"],
                  let userData = try? JSONSerialization.data(withJSONObject: userObj),
                  let u = try? JSONDecoder().decode(CloudUser.self, from: userData) else {
                throw CloudError.http(status)
            }
            guard CloudToken.save(token) else {
                throw CloudError.keychain
            }
            self.token = token
            setUser(u)
            Task { await refreshMe() }
            Notifier.shared.notify(title: L("已登录 Quotlet Cloud", "Signed in to Quotlet Cloud", ja: "Quotlet Cloud にログインしました", ko: "Quotlet Cloud에 로그인했습니다"),
                                   body: [u.name, u.email].compactMap { $0 }.joined(separator: " · "))
        } catch {
            errorMessage = error.localizedDescription
            Notifier.shared.notify(title: L("Quotlet 登录失败", "Quotlet sign-in failed", ja: "Quotlet のログインに失敗しました", ko: "Quotlet 로그인 실패"),
                                   body: error.localizedDescription)
        }
    }

    // MARK: 退出 / 校验

    func signOut() {
        let token = self.token
        clearToken()
        errorMessage = nil
        // 通知服务器吊销这台设备；失败也没关系，本地已经删掉 token
        if let token {
            Task.detached { _ = try? await Cloud.request("POST", "/api/auth/logout", json: [:], token: token) }
        }
    }

    func openWebsite() {
        NSWorkspace.shared.open(CloudConfig.base)
    }

    /// token 被网页上移除、或账号被删除时，服务器返回 401，本地也退出
    func refreshMe() async {
        guard let token else { setUser(nil); return }
        guard let (data, status) = try? await Self.request("GET", "/api/me", token: token) else { return }  // 网络不通：保持现状
        if status == 401 {
            handleUnauthorized()
            return
        }
        if status == 200,
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let userObj = root["user"],
           let userData = try? JSONSerialization.data(withJSONObject: userObj),
           let u = try? JSONDecoder().decode(CloudUser.self, from: userData) {
            if let dev = root["device"] as? [String: Any], let id = dev["id"] as? String {
                deviceId = id
                UserDefaults.standard.set(id, forKey: Self.deviceIdKey)
            }
            setUser(u)
        }
    }

    /// 服务器说 token 无效（在网页上被移除、账号被删）：本地也退出
    func handleUnauthorized() {
        NSLog("[cloud] token rejected (401), signing out locally")
        clearToken()
    }

    private func clearToken() {
        CloudToken.delete()
        token = nil
        deviceId = nil
        UserDefaults.standard.removeObject(forKey: Self.deviceIdKey)
        setUser(nil)
        HookManager.shared.handleSignedOut()
        RemoteCommandManager.shared.handleSignedOut()
    }

    private func setUser(_ u: CloudUser?) {
        user = u
        if let u, let data = try? JSONEncoder().encode(u) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.userKey)
        }
    }

    // MARK: 网络

    /// 和额度请求一样：开了代理先走代理，失败再直连。
    /// 整轮都失败时再重试一次。每次失败都写进系统日志：
    /// `log show --last 10m --predicate 'process == "Quotlet" AND eventMessage CONTAINS "[cloud]"'`
    nonisolated static func request(_ method: String, _ path: String, json: [String: Any]? = nil, token: String?) async throws -> (Data, Int) {
        let url = URL(string: path, relativeTo: CloudConfig.base)?.absoluteURL ?? CloudConfig.base.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var firstError: Error?
        for round in 1...2 {
            let sessions = Network.sessions(for: url, allowFallback: true)
            for (i, session) in sessions.enumerated() {
                let route = (i == 0 && sessions.count > 1) ? "proxy" : "direct"
                let started = Date()
                do {
                    let (data, resp) = try await session.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    NSLog("[cloud] %@ %@ via %@ → %d (%.1fs)", method, path, route, code, Date().timeIntervalSince(started))
                    return (data, code)
                } catch {
                    NSLog("[cloud] %@ %@ via %@ round %d failed after %.1fs: %@", method, path, route, round, Date().timeIntervalSince(started), String(describing: error))
                    if firstError == nil { firstError = error }   // 报给用户的是第一次（走代理）的错误，直连失败在国内是常态
                }
            }
        }
        throw CloudError.network(firstError?.localizedDescription ?? "")
    }

    // MARK: PKCE

    private static func randomString(bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return base64url(Data(b))
    }

    private static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 稳定的本机指纹（对硬件 IOPlatformUUID 加盐做 SHA-256），改名或重装重登时云端复用同一设备记录
    nonisolated static let machineId: String? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let uuid = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
              !uuid.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(("quotlet-mac:" + uuid).utf8))
        return "mac_" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }()
}

// MARK: - 钥匙串

/// Quotlet 自己的钥匙串条目（和 Claude Code 的凭证无关）
enum CloudToken {
    private static let service = "Quotabar Cloud"
    private static let accountKey = "cloudTokenAccount"

    // 旧版本使用固定账号；新登录使用独立条目，兼容临时签名变化后无法访问的旧条目。
    private static var account: String {
        UserDefaults.standard.string(forKey: accountKey) ?? "device-token"
    }

    private static var query: [String: Any] {
        query(account: account)
    }

    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var out: CFTypeRef?
        let status = KeychainAccess.perform(allowInteraction: false) {
            SecItemCopyMatching(q as CFDictionary, &out)
        }
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let previous = query
        let newAccount = "device-token-\(UUID().uuidString)"
        var q = query(account: newAccount)
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrLabel as String] = service
        let status = KeychainAccess.perform(allowInteraction: false) {
            SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        UserDefaults.standard.set(newAccount, forKey: accountKey)
        // 新 token 已持久化后再清理旧条目。旧签名的 ACL 可能禁止删除，清理失败也可继续登录。
        _ = KeychainAccess.perform(allowInteraction: false) { SecItemDelete(previous as CFDictionary) }
        return true
    }

    static func delete() {
        _ = KeychainAccess.perform(allowInteraction: false) { SecItemDelete(query as CFDictionary) }
    }
}
