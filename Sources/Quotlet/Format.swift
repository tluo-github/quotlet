import Foundation

/// 界面语言：简体中文 / English / 日本語 / 한국어。默认跟随系统首选语言（其他语言显示英文），
/// 也可以在设置里手动指定（存在 UserDefaults 的 "language"，空 = 跟随系统）。
enum Lang: String, CaseIterable {
    case zh, en, ja, ko

    static let system: Lang = {
        let code = Locale.preferredLanguages.first ?? "en"
        if code.hasPrefix("zh") { return .zh }
        if code.hasPrefix("ja") { return .ja }
        if code.hasPrefix("ko") { return .ko }
        return .en
    }()

    static var current: Lang {
        UserDefaults.standard.string(forKey: "language").flatMap(Lang.init(rawValue:)) ?? system
    }

    /// 语言自己的名字，用在设置的下拉框里
    var nativeName: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }

    var localeID: String {
        switch self {
        case .zh: return "zh_CN"
        case .en: return "en_US"
        case .ja: return "ja_JP"
        case .ko: return "ko_KR"
        }
    }
}

var isChinese: Bool { Lang.current == .zh }

/// 多语言字符串。日语 / 韩语没给时用英文。
func L(_ zh: String, _ en: String, ja: String? = nil, ko: String? = nil) -> String {
    switch Lang.current {
    case .zh: return zh
    case .en: return en
    case .ja: return ja ?? en
    case .ko: return ko ?? en
    }
}

/// 时间按系统时区显示；日期格式随界面语言。
enum Fmt {
    static let tz = TimeZone.autoupdatingCurrent
    static var locale: Locale { Locale(identifier: Lang.current.localeID) }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }()

    /// zh：固定格式；其他语言用模板，让系统按该语言决定 12/24 小时制和日期顺序。
    private static func formatter(_ zh: String, _ enTemplate: String) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = tz
        f.locale = locale
        if isChinese { f.dateFormat = zh } else { f.setLocalizedDateFormatFromTemplate(enTemplate) }
        return f
    }

    /// 按语言缓存格式器，切换语言后自动换成新语言的格式
    private static var cache: [String: DateFormatter] = [:]
    private static let cacheLock = NSLock()
    private static func cached(_ zh: String, _ enTemplate: String) -> DateFormatter {
        let key = "\(Lang.current.rawValue)|\(zh)|\(enTemplate)"
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let f = cache[key] { return f }
        let f = formatter(zh, enTemplate)
        cache[key] = f
        return f
    }

    private static var hm: DateFormatter { cached("HH:mm", "jm") }
    private static var hms: DateFormatter { cached("HH:mm:ss", "jms") }
    private static var mdWeekHm: DateFormatter { cached("M月d日 EEE HH:mm", "EEEMMMdjm") }
    private static var md: DateFormatter { cached("M/d", "Md") }
    private static var mdWeek: DateFormatter { cached("M月d日 EEE", "EEEMMMd") }
    private static var mdShort: DateFormatter { cached("M/d HH:mm", "Mdjm") }
    private static var weekday: DateFormatter { cached("EEEE", "EEEE") }

    static func time(_ d: Date) -> String { hm.string(from: d) }
    static func timeWithSeconds(_ d: Date) -> String { hms.string(from: d) }
    /// 图表横轴：所有语言统一 11/17（韩语模板会给出 "11. 17." 太挤）
    static func shortDay(_ d: Date) -> String { "\(calendar.component(.month, from: d))/\(calendar.component(.day, from: d))" }

    /// 会话列表里用：今天只显示时分，其他日子带日期。
    static func sessionTime(_ d: Date, now: Date) -> String {
        calendar.isDate(d, inSameDayAs: now) ? hm.string(from: d) : mdShort.string(from: d)
    }

    /// 重置时间：「今天 13:49」「明天 02:59」「本周日 03:00」「下周一 03:00」「11月30日 周日 03:00」
    /// 其他语言：Today 1:49 PM / Tomorrow / Sunday 3:00 AM / 完整日期。
    /// 一周以内只说星期几（中文按周一开始算「本周 / 下周」），比日期好懂。
    static func resetMoment(_ d: Date, now: Date) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return L("今天 ", "Today ", ja: "今日 ", ko: "오늘 ") + hm.string(from: d) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(d, inSameDayAs: tomorrow) {
            return L("明天 ", "Tomorrow ", ja: "明日 ", ko: "내일 ") + hm.string(from: d)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 99
        if days > 0 && days < 7 {
            if isChinese {
                var monday = calendar
                monday.firstWeekday = 2
                let week = monday.isDate(d, equalTo: now, toGranularity: .weekOfYear) ? "本周" : "下周"
                let names = ["日", "一", "二", "三", "四", "五", "六"]
                return week + names[calendar.component(.weekday, from: d) - 1] + " " + hm.string(from: d)
            }
            return weekday.string(from: d) + " " + hm.string(from: d)
        }
        return mdWeekHm.string(from: d)
    }

    /// 「还有 1 小时 34 分钟」「还有 4 天 14 小时」
    static func countdown(to d: Date, now: Date) -> String {
        let s = d.timeIntervalSince(now)
        if s <= 0 { return L("已到重置时间，等待刷新", "Reset due, refreshing soon", ja: "リセット時刻です。まもなく更新します", ko: "재설정 시간입니다. 곧 새로 고칩니다") }
        return L("还有 " + duration(s), duration(s) + " left", ja: "残り " + duration(s), ko: duration(s) + " 남음")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        switch Lang.current {
        case .en:
            if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
            if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
            return minutes > 0 ? "\(minutes) min" : "<1 min"
        case .ja:
            if days > 0 { return hours > 0 ? "\(days)日\(hours)時間" : "\(days)日" }
            if hours > 0 { return minutes > 0 ? "\(hours)時間\(minutes)分" : "\(hours)時間" }
            return minutes > 0 ? "\(minutes)分" : "1分未満"
        case .ko:
            if days > 0 { return hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일" }
            if hours > 0 { return minutes > 0 ? "\(hours)시간 \(minutes)분" : "\(hours)시간" }
            return minutes > 0 ? "\(minutes)분" : "1분 미만"
        case .zh:
            break
        }
        // 面板窄，统一紧凑写法：「4天9小时」「1小时9分」「24分钟」
        if days > 0 { return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天" }
        if hours > 0 { return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时" }
        if minutes > 0 { return "\(minutes)分钟" }
        return "不到1分钟"
    }

    /// 和 duration 同一写法（以前两套写法不一致，已统一）
    static func compactDuration(_ seconds: TimeInterval) -> String { duration(seconds) }

    /// 日期分组标题：「今天」「昨天」「11月15日 周日」
    static func dayLabel(_ d: Date, now: Date) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return L("今天", "Today", ja: "今日", ko: "오늘") }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) {
            return L("昨天", "Yesterday", ja: "昨日", ko: "어제")
        }
        return mdWeek.string(from: d)
    }

    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        switch v {
        case 1_000_000_000...: return String(format: "%.2fB", v / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 1_000...: return String(format: "%.1fK", v / 1_000)
        default: return "\(n)"
        }
    }

    static func percent(_ p: Double) -> String {
        p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p)
    }

    /// claude-opus-5-5 → Opus 5.5；claude-sonnet-4-5-20250929 → Sonnet 4.5
    static func modelName(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }

    // MARK: - 解析

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 接口返回的时间带 6 位小数（如 2026-11-17T05:49:59.744399+00:00），
    /// 先去掉小数部分再解析，避免不同系统版本对小数位数的兼容问题。
    /// 服务器给的重置时间会在整点前后抖动（18:59:59.7 / 19:00:00.1），
    /// 所以四舍五入到整分钟，界面上就不会在 02:59 和 03:00 之间来回跳。
    static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let stripped = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        guard let d = isoPlain.date(from: stripped) else { return nil }
        return Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 60).rounded() * 60)
    }
}
