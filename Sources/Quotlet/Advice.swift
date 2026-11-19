import SwiftUI

/// 一家额度告急、另一家仍有余量时，给出切换建议。
struct Advice {
    let title: String
    let badge: String
    let reason: String

    static func make(claude: [LimitItem], codex: [LimitItem], now: Date,
                     threshold: Double = Notifier.lowThreshold) -> Advice? {
        func tight(_ items: [LimitItem]) -> LimitItem? {
            items.first { $0.percent >= threshold && ($0.resetsAt.map { $0 > now } ?? false) }
        }
        func roomy(_ items: [LimitItem]) -> Bool {
            items.contains { $0.kind == "session" } && items.contains { $0.kind == "weekly_all" }
                && items.allSatisfy { $0.percent < 70 && ($0.resetsAt.map { $0 > now } ?? false) }
        }
        func left(_ items: [LimitItem]) -> String {
            let five = items.first { $0.kind == "session" }!
            let percent = (five.isEstimated ? "≈" : "") + Fmt.percent(max(0, 100 - five.percent))
            return L("5 小时还剩 \(percent)", "\(percent) left in 5h",
                     ja: "5 時間枠の残り \(percent)", ko: "5시간 \(percent) 남음")
        }
        func why(_ name: String, _ item: LimitItem) -> String {
            L("\(name) \(item.shortLabel)已用 \(item.percentText)",
              "\(name) \(item.shortLabel) at \(item.percentText)",
              ja: "\(name) \(item.shortLabel)は \(item.percentText) 使用",
              ko: "\(name) \(item.shortLabel) \(item.percentText) 사용")
        }
        if let item = tight(claude), roomy(codex) {
            return Advice(title: L("先用 Codex", "Use Codex for now", ja: "今は Codex を", ko: "지금은 Codex"),
                          badge: left(codex), reason: why("Claude", item))
        }
        if let item = tight(codex), roomy(claude) {
            return Advice(title: L("先用 Claude", "Use Claude for now", ja: "今は Claude を", ko: "지금은 Claude"),
                          badge: left(claude), reason: why("Codex", item))
        }
        return nil
    }
}

struct AdviceCard: View {
    let advice: Advice

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(advice.title + " · " + advice.badge)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.live)
                .fixedSize(horizontal: false, vertical: true)
            Text(advice.reason).font(Theme.caption).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.live.opacity(0.10)))
    }
}
