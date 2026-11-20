import Foundation

/// 只保留日志明确记录的运行阶段；没有新日志的会话会过期，不把“最近用过”当作正在生成。
struct LiveActivity {
    enum Phase { case generating, tools, idle }
    let id: String
    let source: Source
    var model = ""
    var phase: Phase = .idle
    var since = Date.distantPast
    var updatedAt = Date.distantPast

    mutating func update(_ phase: Phase, at date: Date) {
        if self.phase != phase { since = date }
        self.phase = phase
        updatedAt = date
    }

    func isFresh(at now: Date) -> Bool {
        (0..<120).contains(now.timeIntervalSince(updatedAt)) && now.timeIntervalSince(since) < 900
    }
}

/// 按回复的真实起止时间重建速度。重叠的请求相加，空闲时间为零；进行中的部分单独标为估算。
struct Throughput {
    struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        var measured: Double = 0
        var estimated: Double = 0
        var total: Double { measured + estimated }
    }
    struct Interval {
        let start: Date
        let end: Date
        let speed: Double
        let source: Source
        let model: String
    }
    struct Reading: Identifiable {
        var id: Source { source }
        let source: Source
        let detected: Bool
        let speed: Double
        let generating: Int
        let tools: Int
        let hasRecentResponse: Bool
        let isPartial: Bool
        var isEstimated: Bool { generating > 0 }
    }
    let detectedSources: Set<Source>
    let intervals: [Interval]
    let activities: [LiveActivity]
    let now: Date

    init(snapshot: LocalSnapshot, now: Date) {
        self.now = now
        detectedSources = Set(Source.allCases.filter { source in
            switch source {
            case .claude: return snapshot.hasClaude
            case .codex: return snapshot.hasCodex
            case .gemini: return snapshot.hasGemini
            }
        }).union(snapshot.liveActivities.map(\.source))
        intervals = snapshot.messages.reversed().prefix { $0.ts >= now.addingTimeInterval(-1200) }.compactMap { message in
            guard message.ts <= now, message.ts >= now.addingTimeInterval(-1200),
                  message.isFinal, let duration = message.duration,
                  duration.isFinite, (0.2...900).contains(duration), message.tokens.output > 0 else { return nil }
            return Interval(start: message.ts.addingTimeInterval(-duration), end: message.ts,
                            speed: Double(message.tokens.output) / duration,
                            source: message.source, model: message.model)
        }
        activities = snapshot.liveActivities.filter { $0.isFresh(at: now) && $0.phase != .idle }
    }

    var generating: Int { activities.filter { $0.phase == .generating }.count }
    var tools: Int { activities.filter { $0.phase == .tools }.count }
    var estimatedSpeed: Double { activities.reduce(0) { $0 + estimate(for: $1) } }
    func measuredSpeed(at date: Date) -> Double {
        intervals.filter { $0.start < date && $0.end >= date }.reduce(0) { $0 + $1.speed }
    }

    /// 总数与明细使用同一时刻：正在生成时取现在，否则短暂保留最近完成时的并发读数。
    var readings: [Reading] {
        let latest = intervals.filter { (0..<5).contains(now.timeIntervalSince($0.end)) }.max { $0.end < $1.end }
        let displayTime = generating > 0 ? now : (latest?.end ?? now)
        return Source.allCases.map { source in
            let running = activities.filter { $0.source == source && $0.phase == .generating }
            let measured = intervals.filter { $0.source == source && $0.start < displayTime && $0.end >= displayTime }
            let value = measured.reduce(0) { $0 + $1.speed } + running.reduce(0) { $0 + estimate(for: $1) }
            return Reading(source: source, detected: detectedSources.contains(source), speed: value,
                           generating: running.count,
                           tools: activities.filter { $0.source == source && $0.phase == .tools }.count,
                           hasRecentResponse: !measured.isEmpty,
                           isPartial: running.contains { estimate(for: $0) == 0 })
        }
    }

    var currentSpeed: Double { readings.reduce(0) { $0 + $1.speed } }
    var currentIsPartial: Bool { readings.contains(where: \.isPartial) }

    var hasEstimate: Bool { activities.contains { estimate(for: $0) > 0 } }

    private func estimate(for activity: LiveActivity) -> Double {
        guard activity.phase == .generating else { return 0 }
        let recent = intervals.filter {
            $0.source == activity.source && $0.model == activity.model && $0.end <= activity.since
        }.sorted { $0.end > $1.end }.prefix(5)
        let seconds = recent.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard seconds > 0 else { return 0 }
        return recent.reduce(0) { $0 + $1.speed * $1.end.timeIntervalSince($1.start) } / seconds
    }

    func points(seconds: Int) -> [Point] {
        let count = max(1, seconds)
        let start = now.addingTimeInterval(-Double(count))
        var points = (0...count).map { Point(date: start.addingTimeInterval(Double($0))) }
        for interval in intervals where interval.end >= start {
            // 每个点代表前一秒的平均吞吐，短回复也按覆盖时长计入，避免漏掉或夸大。
            for index in points.indices {
                let end = points[index].date
                let overlap = min(end, interval.end).timeIntervalSince(max(end.addingTimeInterval(-1), interval.start))
                if overlap > 0 { points[index].measured += interval.speed * overlap }
            }
        }
        for activity in activities where activity.phase == .generating {
            let speed = estimate(for: activity)
            for index in points.indices {
                let end = points[index].date
                let overlap = min(end, now).timeIntervalSince(max(end.addingTimeInterval(-1), activity.since))
                if overlap > 0 { points[index].estimated += speed * min(1, overlap) }
            }
        }
        return points
    }
}
