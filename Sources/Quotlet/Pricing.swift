import Foundation

/// 按官方 API 标价估算「这些用量如果按 API 付费值多少钱」（API 等值）。
/// 包月套餐实际不按这个收费，界面上一律标「API 等值」。价格未知的模型不算，单独计数提示。
/// 价格：美元 / 百万 token，来自 Anthropic 官方价格表（2026-11）。
enum Pricing {
    struct Price {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    /// 按模型 id 的前缀匹配，越具体的放越前面
    private static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5-2", .init(input: 8, output: 40, cacheRead: 0.20, cacheWrite: 10)),
        ("claude-mythos-5-2", .init(input: 8, output: 40, cacheRead: 0.20, cacheWrite: 10)),
        ("claude-fable-5", .init(input: 10, output: 50, cacheRead: 1.0, cacheWrite: 12.5)),
        ("claude-mythos-5", .init(input: 10, output: 50, cacheRead: 1.0, cacheWrite: 12.5)),
        ("claude-opus-5-5", .init(input: 4, output: 20, cacheRead: 0.20, cacheWrite: 5)),
        ("claude-opus-5", .init(input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25)),
        ("claude-opus-4-8", .init(input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25)),
        ("claude-opus-4-7", .init(input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25)),
        ("claude-opus-4-6", .init(input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25)),
        ("claude-opus-4-5", .init(input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25)),
        ("claude-opus-4", .init(input: 15, output: 75, cacheRead: 1.50, cacheWrite: 18.75)),
        ("claude-sonnet-5-5", .init(input: 2, output: 10, cacheRead: 0.10, cacheWrite: 2.5)),
        ("claude-sonnet-5", .init(input: 2, output: 10, cacheRead: 0.20, cacheWrite: 2.5)),
        ("claude-sonnet-4", .init(input: 3, output: 15, cacheRead: 0.30, cacheWrite: 3.75)),
        ("claude-haiku-5-5", .init(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125)),
        ("claude-haiku-4-5", .init(input: 1, output: 5, cacheRead: 0.10, cacheWrite: 1.25)),
    ]

    static func price(for model: String) -> Price? {
        let m = model.lowercased()
        return table.first { m.hasPrefix($0.prefix) }?.price
    }

    /// 一条回复的 API 等值费用；模型价格未知返回 nil
    static func cost(model: String, tokens t: TokenCount) -> Double? {
        guard let p = price(for: model) else { return nil }
        return (Double(t.input) * p.input + Double(t.output) * p.output
              + Double(t.cacheRead) * p.cacheRead + Double(t.cacheWrite) * p.cacheWrite) / 1_000_000
    }
}

/// 一段时间里的汇总：面板「今天」和用量历史窗口都用它
struct UsageStats {
    var tokens = TokenCount()
    var requests = 0
    var cost = 0.0
    var unpricedRequests = 0
    /// 有耗时的回复：输出 token 之和、耗时之和（算平均速度）
    var timedOutput = 0
    var timedSeconds = 0.0
    var peakSpeed = 0.0
    var peakAt: Date?

    /// 输入（含缓存读写）
    var inputAll: Int { tokens.input + tokens.cacheRead + tokens.cacheWrite }
    /// 平均速度 tok/s：输出 token ÷ 回复花的时间
    var avgSpeed: Double? { timedSeconds > 0 ? Double(timedOutput) / timedSeconds : nil }

    mutating func add(_ m: MessageUsage) {
        tokens += m.tokens
        requests += 1
        if let c = Pricing.cost(model: m.model, tokens: m.tokens) { cost += c } else { unpricedRequests += 1 }
        if let (out, d) = m.timed {
            timedOutput += out
            timedSeconds += d
            // 峰值只看输出够多、时间够长的回复，否则几个 token / 零点几秒算出来的速度没有意义
            if m.tokens.output >= 200, d >= 2 {
                let s = Double(m.tokens.output) / d
                if s > peakSpeed { peakSpeed = s; peakAt = m.ts }
            }
        }
    }

    static func of<S: Sequence>(_ messages: S) -> UsageStats where S.Element == MessageUsage {
        var s = UsageStats()
        for m in messages { s.add(m) }
        return s
    }
}

extension Fmt {
    static func money(_ v: Double) -> String {
        if v >= 1000 { return String(format: "US$%.0f", v) }
        return String(format: "US$%.2f", v)
    }

    static func speed(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.2fk", v / 1000) : String(format: "%.0f", v)
    }

    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
