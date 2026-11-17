import AppKit
import SwiftUI

// 设计约定（极简单色）：
// - 黑白灰为主。额度进度条、选中态用墨色（ink）。
// - 图表和 Pro 标签用 Claude 珊瑚橙（data）。
// - 状态色：绿 = 健康（额度正常 / 会话进行中），琥珀 = 用量偏高，红 = 接近上限。永远配文字，不只靠颜色。
// - 不用卡片和边框分区，靠留白和细分隔线。
// - 说明文字用深炭灰 text2，不用系统浅灰。
// - 字号：大数字 24 常规 / 数值 15 / 正文 12 / 说明 11.5 / 小标题 11.5 中粗 / 重置时间在说明行里用蓝色半粗体。
//   大数字用常规字重 + 等宽数字（细字重笔画太细，看着发灰），其余保持安静。

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

enum Theme {
    // 文字：正文用系统 primary；说明文字用接近正文的深炭灰（用户嫌灰字发虚：小字 + 浅灰在 Retina 上边缘不实）
    // 对比度：浅色 ≈11:1，深色 ≈11:1；层级主要靠字号和字重区分，不靠把字调灰。
    static let text2 = Color.dynamic(light: 0x383836, dark: 0xCFCFCB)

    // 中性色（略带暖调，避免纯灰的冷硬感）
    static let surface = Color.dynamic(light: 0xFAFAF8, dark: 0x1C1C1E)   // 面板底，不透明
    static let ink = Color.dynamic(light: 0x1F1F1E, dark: 0xF2F2F0)       // 墨色：进度条 / 选中
    static let inkSoft = Color.dynamic(light: 0xD3D3CF, dark: 0x4A4A4C)   // 图表里未选中的柱子
    static let track = Color.dynamic(light: 0xE2E2DE, dark: 0x333335)     // 进度条底槽
    static let hairline = Color.dynamic(light: 0xE9E9E6, dark: 0x2E2E30)  // 分隔线
    static let hover = Color.dynamic(light: 0xF0F0ED, dark: 0x2A2A2C)
    static let group = Color.dynamic(light: 0xFFFFFF, dark: 0x252527)     // 设置分组容器
    static let divider = Color.dynamic(light: 0xDADAD5, dark: 0x3C3C3F)   // 设置里的分割线，比 hairline 明显
    static let marker = Color.dynamic(light: 0x8E8E8A, dark: 0x8E8E90)    // 时间进度刻度

    // 数据色：Claude 珊瑚橙，只用在图表（统计页柱状图、模型占比）和 Pro 标签。
    // 已用 dataviz 校验脚本检查：对比度浅色 / 深色都 >= 3:1。
    static let data = Color.dynamic(light: 0xC8643F, dark: 0xDD7A58)
    static let dataStrong = Color.dynamic(light: 0x9A4426, dark: 0xF4A588)  // 选中 / 悬停的那根柱子

    // 状态色。警告用琥珀而不是橙，和数据色区分；状态永远配文字。
    static let warning = Color.dynamic(light: 0xA87400, dark: 0xE5B83A)
    static let critical = Color.dynamic(light: 0xC9372C, dark: 0xFF6F61)
    static let live = Color.dynamic(light: 0x23864D, dark: 0x4FCB85)

    // 时间色：重置时间是用户最关心的信息之一，单独一个蓝色，不借用状态色（会被误读成警告）。
    // 对比度：浅色在面板底上 ≈5.3:1，深色 ≈6.8:1。
    static let time = Color.dynamic(light: 0x1F64D6, dark: 0x6AA6FF)
    // 开关打开的颜色：和选中胶囊同一墨色系（深色模式用中灰，白色滑块才看得清）
    static let toggle = Color.dynamic(light: 0x1F1F1E, dark: 0x8A8A86)

    // 字体
    static let hero = Font.system(size: 24, weight: .regular).monospacedDigit()   // 别用 light：细笔画看着发灰
    static let heroLarge = Font.system(size: 28, weight: .regular).monospacedDigit()   // 用量页只有 1–2 条额度时
    static let value = Font.system(size: 15, weight: .regular).monospacedDigit()
    static let number = Font.system(size: 12, weight: .regular).monospacedDigit()
    static let body = Font.system(size: 12)
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11.5)
    static let label = Font.system(size: 11.5, weight: .medium)
}

/// 额度状态。颜色之外一定配文字，不只靠颜色区分。
enum Level {
    case normal, warning, critical

    init(percent: Double, severity: String?) {
        if severity == "critical" || percent >= 90 {
            self = .critical
        } else if severity == "warning" || percent >= 75 {
            self = .warning
        } else {
            self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: return Theme.live
        case .warning: return Theme.warning
        case .critical: return Theme.critical
        }
    }

    var label: String {
        switch self {
        case .normal: return L("健康", "Healthy", ja: "良好", ko: "양호")
        case .warning: return L("用量偏高", "Running high", ja: "使用量多め", ko: "사용량 높음")
        case .critical: return L("接近上限", "Near limit", ja: "上限間近", ko: "한도 임박")
        }
    }
}
