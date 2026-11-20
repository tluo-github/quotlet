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
    private var evaluationSignatures: [String: String] = [:]
    private var resetGenerations: [String: Int] = [:]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [Key.low: true, Key.full: true, Key.reset: true, Key.threshold: 90])
    }

    /// 没有 bundle id 的开发版二进制不能用通知中心（会崩溃），直接跳过。
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func setup(onAuthorized: @escaping () -> Void) {
        guard let center, !Cloud.isPreview else { return }
        center.delegate = self
        if !UserDefaults.standard.bool(forKey: Key.reset) { cancelResetReminders() }
        else if !UsageAPI.isEnabled() { cancelResetReminders(provider: "Claude") }
        let d = UserDefaults.standard
        guard d.bool(forKey: Key.low) || d.bool(forKey: Key.full) || d.bool(forKey: Key.reset) else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.requestAuthorization { granted in if granted { onAuthorized() } }
        }
    }

    func cancelResetReminders(provider: String? = nil) {
        if let provider {
            evaluationSignatures.removeValue(forKey: provider)
            resetGenerations[provider, default: 0] += 1
        } else {
            evaluationSignatures.removeAll()
            for key in Array(resetGenerations.keys) { resetGenerations[key, default: 0] += 1 }
        }
        let prefix = Self.resetPrefix + (provider.map { $0.lowercased() + "|" } ?? "")
        center?.getPendingNotificationRequests { requests in
            self.center?.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
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
        evaluate(provider: "Claude", limits: usage.limits, now: now)
    }

    func evaluate(provider: String, limits items: [LimitItem], now: Date = Date()) {
        guard !Cloud.isPreview else { return }
        guard let center else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { self.evaluateAuthorized(provider: provider, limits: items, now: now) }
        }
    }

    private func evaluateAuthorized(provider: String, limits items: [LimitItem], now: Date) {
        guard let center else { return }
        let d = UserDefaults.standard
        let resetPrefix = Self.resetPrefix + provider.lowercased() + "|"
        let limits = items.filter {
            ($0.kind.hasPrefix("session") || $0.kind.hasPrefix("daily") || $0.kind.hasPrefix("weekly"))
                && ($0.resetsAt.map { $0 > now } ?? true)
        }
        let signature = "\(d.bool(forKey: Key.low))|\(d.bool(forKey: Key.full))|\(d.bool(forKey: Key.reset))|\(Self.lowThreshold)|"
            + limits.map { "\(Self.windowKey(provider: provider, item: $0))|\($0.percent >= Self.lowThreshold)|\($0.percent >= 100)|\($0.isEstimated)" }.sorted().joined(separator: ";")
        guard evaluationSignatures[provider] != signature else { return }
        evaluationSignatures[provider] = signature
        var sent = d.stringArray(forKey: Key.sent) ?? []

        for item in limits {
            Self.updateAlertWindow(provider: provider, item: item, sent: &sent, now: now)
            let title = item.title.hasPrefix(provider) ? item.title : "\(provider) · \(item.title)"
            let when = item.resetsAt.map { r in
                L("\(Fmt.resetMoment(r, now: now)) 重置 · \(Fmt.countdown(to: r, now: now))",
                  "Resets \(Fmt.resetMoment(r, now: now)) · \(Fmt.countdown(to: r, now: now))",
                  ja: "\(Fmt.resetMoment(r, now: now)) にリセット · \(Fmt.countdown(to: r, now: now))",
                  ko: "\(Fmt.resetMoment(r, now: now)) 재설정 · \(Fmt.countdown(to: r, now: now))")
            } ?? ""
            let body = item.isEstimated
                ? L("根据本机新增 token 估算，下次接口刷新时校正。", "Estimated from new local tokens. Corrected at the next quota refresh.",
                    ja: "ローカルの新規トークンから推定。次の API 更新時に補正します。", ko: "새 로컬 토큰으로 추정하며 다음 한도 새로 고침 시 보정됩니다.") + " " + when
                : when

            if item.percent >= 100 {
                if d.bool(forKey: Key.full),
                   let key = Self.recordAlert(provider: provider, item: item, event: .full, sent: &sent, now: now) {
                    post(id: key,
                         title: item.isEstimated
                            ? L("\(title)：预计已用完", "\(title): estimated limit reached", ja: "\(title)：上限到達の推定", ko: "\(title): 예상 한도 도달")
                            : L("\(title)：已用完", "\(title): limit reached", ja: "\(title)：上限に達しました", ko: "\(title): 한도 도달"),
                         body: body)
                }
                if d.bool(forKey: Key.full) {
                    // 用完时不再补发「快到上限」。
                    _ = Self.recordAlert(provider: provider, item: item, event: .low, sent: &sent, now: now)
                }
            }
            if Self.shouldWarn(item: item, threshold: Self.lowThreshold, lowEnabled: d.bool(forKey: Key.low),
                               fullEnabled: d.bool(forKey: Key.full), now: now),
               let key = Self.recordAlert(provider: provider, item: item, event: .low, sent: &sent, now: now) {
                post(id: key,
                     title: L("\(title)：已用 \(item.percentText)，快到上限",
                              "\(title): \(item.percentText) used, nearing the limit",
                              ja: "\(title)：\(item.percentText) 使用、上限が近づいています",
                              ko: "\(title): \(item.percentText) 사용, 한도에 가까워짐"),
                     body: body)
            }
        }
        var seen: Set<String> = []
        d.set(Array(sent.filter { seen.insert($0).inserted }.suffix(300)), forKey: Key.sent)

        // 「已恢复」：达到用户设置的阈值后，在重置时间安排通知。
        resetGenerations[provider, default: 0] += 1
        let generation = resetGenerations[provider]
        center.getPendingNotificationRequests { pending in
            DispatchQueue.main.async {
                guard self.resetGenerations[provider] == generation else { return }
                let old = pending.map(\.identifier).filter { $0.hasPrefix(resetPrefix) || ($0.hasPrefix(Self.resetPrefix) && !$0.hasPrefix("reset|claude|") && !$0.hasPrefix("reset|codex|") && !$0.hasPrefix("reset|gemini|")) }
                center.removePendingNotificationRequests(withIdentifiers: old)
                guard d.bool(forKey: Key.reset) else { return }
                for item in limits where item.percent >= Self.lowThreshold {
                    guard let r = item.resetsAt, r.timeIntervalSince(now) > 0 else { continue }
                    let title = item.title.hasPrefix(provider) ? item.title : "\(provider) · \(item.title)"
                    let content = UNMutableNotificationContent()
                    content.title = L("\(title)：已恢复", "\(title): available again",
                                      ja: "\(title)：リセットされました", ko: "\(title): 다시 사용 가능")
                    content.body = L("额度已重置，可以继续使用 \(provider) 了。", "Your limit has reset. You can use \(provider) again.",
                                     ja: "上限がリセットされました。\(provider) を再び使えます。", ko: "한도가 재설정되었습니다. \(provider)를 다시 사용할 수 있습니다.")
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: r.timeIntervalSince(now) + 5, repeats: false)
                    center.add(UNNotificationRequest(identifier: resetPrefix + item.kind + "|" + (item.scope ?? ""),
                                                     content: content, trigger: trigger))
                }
            }
        }
    }

    static func windowKey(provider: String, item: LimitItem) -> String {
        "\(provider)|\(item.kind)|\(item.scope ?? "")|\(Int(item.resetsAt?.timeIntervalSince1970 ?? 0))"
    }

    enum AlertEvent: String { case low, full }

    /// 每次读数都同步已发提醒的周期边界，包括用量回落到告警阈值以下时。
    static func updateAlertWindow(provider: String, item: LimitItem, sent: inout [String], now: Date) {
        guard let reset = item.resetsAt, reset > now else { return }
        let prefix = "\(provider)|\(item.kind)|\(item.scope ?? "")|"
        var seen: Set<String> = []
        sent = sent.map { previous in
            guard previous.hasPrefix(prefix) else { return previous }
            let parts = previous.dropFirst(prefix.count).split(separator: "|")
            guard parts.count == 2, AlertEvent(rawValue: String(parts[1])) != nil,
                  let timestamp = TimeInterval(parts[0]), timestamp == 0 || timestamp > now.timeIntervalSince1970 else { return previous }
            return windowKey(provider: provider, item: item) + "|" + parts[1]
        }.filter { seen.insert($0).inserted }
    }

    /// 重置时间会被接口修正，不能用修正幅度判断是不是新周期。
    /// 同一额度窗口已有尚未到期的提醒时只更新它的重置时间，不再次发送。
    /// 缺失重置时间后补齐也沿用原提醒；旧周期过期后允许新周期提醒。
    static func recordAlert(provider: String, item: LimitItem, event: AlertEvent,
                            sent: inout [String], now: Date) -> String? {
        updateAlertWindow(provider: provider, item: item, sent: &sent, now: now)
        let key = windowKey(provider: provider, item: item) + "|" + event.rawValue
        guard !sent.contains(key) else { return nil }
        let prefix = "\(provider)|\(item.kind)|\(item.scope ?? "")|"
        let suffix = "|" + event.rawValue
        let alreadySent = sent.contains { previous in
            guard previous.hasPrefix(prefix), previous.hasSuffix(suffix),
                  let timestamp = TimeInterval(previous.dropFirst(prefix.count).dropLast(suffix.count)) else { return false }
            return timestamp == 0 || timestamp > now.timeIntervalSince1970
        }
        guard !alreadySent else { return nil }
        sent.append(key)
        return key
    }

    static func shouldWarn(item: LimitItem, threshold: Double, lowEnabled: Bool, fullEnabled: Bool, now: Date) -> Bool {
        lowEnabled && item.percent >= threshold && (item.percent < 100 || !fullEnabled)
            && (item.resetsAt.map { $0 > now } ?? true)
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

    /// 登录结果只使用已有通知权限，不因登录额外申请权限。
    func notify(title: String, body: String) {
        center?.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            self.post(id: "msg-\(Date().timeIntervalSince1970)", title: title, body: body)
        }
    }

    private func post(id: String, title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error {
                NSLog("[notifications] failed id=%@ error=%@", id, error.localizedDescription)
            } else {
                NSLog("[notifications] posted id=%@ title=%@", id, title)
            }
        }
    }
}
