import Foundation

/// 用同一额度窗口内的接口变化校准本机 token 增量，供两次接口查询之间显示估算值。
/// 样本仅驻留内存。显示和通知可使用估算值，云端历史使用 UsageSnapshot 原始数据。
struct ClaudeQuotaEstimator {
    private struct Sample {
        let percent: Double
        let resetsAt: Date
        let at: Date
    }

    private struct Calibration {
        var reference: Sample
        var last: Sample
        var percentChange: Double = 0
        var tokens: Double = 0
    }

    private var plan: String?
    private var windows: [String: Calibration] = [:]

    mutating func observe(_ snapshot: UsageSnapshot, at: Date, messages: [MessageUsage]) {
        if snapshot.plan != plan {
            windows.removeAll()
            plan = snapshot.plan
        }
        for item in snapshot.limits where item.kind == "session" || item.kind == "weekly_all" {
            guard let reset = item.resetsAt, reset > at, item.percent.isFinite else {
                windows.removeValue(forKey: item.kind)
                continue
            }
            let sample = Sample(percent: item.percent, resetsAt: reset, at: at)
            guard var calibration = windows[item.kind],
                  calibration.last.resetsAt == reset,
                  item.percent >= calibration.last.percent else {
                windows[item.kind] = Calibration(reference: sample, last: sample)
                continue
            }
            guard at > calibration.last.at else { continue }
            let change = sample.percent - calibration.reference.percent
            if change > 0 {
                let tokens = Self.tokens(messages, after: calibration.reference.at, through: at)
                if tokens > 0 {
                    calibration.percentChange += change
                    calibration.tokens += tokens
                }
                // 没有本机用量的额度增长也推进基线，避免混入下一段校准。
                calibration.reference = sample
            }
            // 百分比没变化时保留校准起点，跨多次查询累积，容纳接口的取整。
            calibration.last = sample
            windows[item.kind] = calibration
        }
    }

    func display(_ snapshot: UsageSnapshot, messages: [MessageUsage], now: Date) -> UsageSnapshot {
        let limits = snapshot.limits.map { item -> LimitItem in
            guard let calibration = windows[item.kind],
                  snapshot.plan == plan,
                  item.resetsAt == calibration.last.resetsAt,
                  item.percent == calibration.last.percent,
                  now < calibration.last.resetsAt,
                  calibration.tokens > 0 else { return item }
            let tokens = Self.tokens(messages, after: calibration.last.at, through: now)
            let percent = min(100, item.percent + tokens * calibration.percentChange / calibration.tokens)
            guard percent > item.percent else { return item }
            var estimated = item
            estimated.percent = percent
            estimated.isEstimated = true
            return estimated
        }
        return UsageSnapshot(limits: limits, breakdown: snapshot.breakdown,
                             breakdownStart: snapshot.breakdownStart, extra: snapshot.extra, plan: snapshot.plan)
    }

    private static func tokens(_ messages: [MessageUsage], after start: Date, through end: Date) -> Double {
        messages.lazy.filter { $0.source == .claude && $0.ts > start && $0.ts <= end }
            .reduce(0) { $0 + Double($1.tokens.total) }
    }
}
