import AppKit
import UserNotifications

/// 系统通知（5 小时和每周额度都适用）：
/// - 快到上限：用到设定的比例时（80 / 90 / 95%，默认 90%）
/// - 已用完：用到 100% 时
/// - 已恢复：用到「快到上限」比例以上的额度重置后
/// 同一个窗口里每种只提醒一次。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    enum Key {
        static let low = "notifyLow"
        static let full = "notifyFull"
        static let reset = "notifyReset"
        static let sent = "notifiedKeys"
        static let threshold = "notifyThreshold"
    }

    static let thresholdChoices = [80, 90, 95]
    static var lowThreshold: Double {
        let v = UserDefaults.standard.integer(forKey: Key.threshold)
        return Double(thresholdChoices.contains(v) ? v : 90)
    }
    private static let resetPrefix = "reset|"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [Key.low: true, Key.full: true, Key.reset: true, Key.threshold: 90])
    }

    /// 没有 bundle id 的开发版二进制不能用通知中心（会崩溃），直接跳过。
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func setup() {
        guard let center else { return }
        center.delegate = self
        let d = UserDefaults.standard
        if d.bool(forKey: Key.low) || d.bool(forKey: Key.full) || d.bool(forKey: Key.reset) { requestAuthorization() }
    }

    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        guard let center else { done?(false); return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async { done?(ok) }
        }
    }

    // 菜单栏 app 也照常弹横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// 每次成功取到额度后调用。
    func evaluate(_ usage: UsageSnapshot, now: Date = Date()) {
        guard let center else { return }
        let d = UserDefaults.standard
        let limits = usage.limits.filter { $0.kind == "session" || $0.kind.hasPrefix("weekly") }
        var sent = d.stringArray(forKey: Key.sent) ?? []

        for item in limits {
            let window = Int(item.resetsAt?.timeIntervalSince1970 ?? 0)
            let base = "\(item.kind)|\(item.title)|\(window)"
            let when = item.resetsAt.map { r in
                L("\(Fmt.resetMoment(r, now: now)) 重置 · \(Fmt.countdown(to: r, now: now))",
                  "Resets \(Fmt.resetMoment(r, now: now)) · \(Fmt.countdown(to: r, now: now))",
                  ja: "\(Fmt.resetMoment(r, now: now)) にリセット · \(Fmt.countdown(to: r, now: now))",
                  ko: "\(Fmt.resetMoment(r, now: now)) 재설정 · \(Fmt.countdown(to: r, now: now))")
            } ?? ""

            if item.percent >= 100 {
                let key = base + "|full"
                if d.bool(forKey: Key.full), !sent.contains(key) {
                    post(id: key,
                         title: L("\(item.title)：已用完", "\(item.title): limit reached",
                                  ja: "\(item.title)：上限に達しました", ko: "\(item.title): 한도 도달"),
                         body: when)
                }
                sent.append(contentsOf: [key, base + "|low"])   // 用完时不再补发「快到上限」
            } else if item.percent >= Self.lowThreshold {
                let key = base + "|low"
                if d.bool(forKey: Key.low), !sent.contains(key) {
                    post(id: key,
                         title: L("\(item.title)：已用 \(Fmt.percent(item.percent))，快到上限",
                                  "\(item.title): \(Fmt.percent(item.percent)) used, nearing the limit",
                                  ja: "\(item.title)：\(Fmt.percent(item.percent)) 使用、上限が近づいています",
                                  ko: "\(item.title): \(Fmt.percent(item.percent)) 사용, 한도에 가까워짐"),
                         body: when)
                }
                sent.append(key)
            }
        }
        d.set(Array(Set(sent)).suffix(300).map { $0 }, forKey: Key.sent)

        // 「已恢复」：给用到 80% 以上的额度在重置时间排一条通知（每次刷新重排）
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(Self.resetPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard d.bool(forKey: Key.reset) else { return }
            for item in limits where item.percent >= Self.lowThreshold {
                guard let r = item.resetsAt, r.timeIntervalSince(now) > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = L("\(item.title)：已恢复", "\(item.title): available again",
                                  ja: "\(item.title)：リセットされました", ko: "\(item.title): 다시 사용 가능")
                content.body = L("额度已重置，可以继续使用 Claude 了。", "Your limit has reset. You can use Claude again.",
                                 ja: "上限がリセットされました。Claude を再び使えます。", ko: "한도가 재설정되었습니다. Claude를 다시 사용할 수 있습니다.")
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: r.timeIntervalSince(now) + 5, repeats: false)
                center.add(UNNotificationRequest(identifier: Self.resetPrefix + item.kind + "|" + item.title,
                                                 content: content, trigger: trigger))
            }
        }
    }

    /// 设置页的「发送测试通知」。返回是否有通知权限。
    func sendTest(_ done: @escaping (Bool) -> Void) {
        requestAuthorization { ok in
            if ok {
                self.post(id: "test-\(Date().timeIntervalSince1970)",
                          title: L("Quotlet 通知已开启", "Quotlet notifications are on",
                                   ja: "Quotlet の通知はオンです", ko: "Quotlet 알림이 켜져 있습니다"),
                          body: L("额度快到上限、用完和恢复时，会在这里提醒你。",
                                  "You'll be notified here when a limit is near, reached, or available again.",
                                  ja: "上限が近いとき、上限に達したとき、リセットされたときにお知らせします。",
                                  ko: "한도에 가까워지거나, 도달하거나, 다시 사용할 수 있게 되면 알려 드립니다."))
            }
            done(ok)
        }
    }

    /// 一次性提醒（比如登录结果）：没授权过会先请求通知权限
    func notify(title: String, body: String) {
        requestAuthorization { ok in
            if ok { self.post(id: "msg-\(Date().timeIntervalSince1970)", title: title, body: body) }
        }
    }

    private func post(id: String, title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
