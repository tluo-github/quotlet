import AppKit
import SwiftUI

/// 开发用：`Quotlet --snapshot <目录>` 会在屏幕外渲染各个页面（浅色 + 深色）存成 PNG，然后退出。
/// 用来检查界面效果，不用真的去点状态栏。
enum Snapshot {
    static var directory: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func run(store: Store, dir: String) async {
        try? await Task.sleep(for: .seconds(4))  // 等数据加载完
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let stage = UserDefaults.standard.bool(forKey: "stage")
        // -stage YES 时多出一张 "closed"：只有仿状态栏、面板收起（演示视频的开头）
        var pages: [(String, ContentView.Tab?)] = [
            ("usage", .usage), ("sessions", .sessions), ("stats", .stats), ("settings", nil),
        ]
        if stage { pages.insert(("closed", .usage), at: 0) }
        for (mode, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            for (page, tab) in pages {
                if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
                // -stage YES：带展示背景和仿状态栏（README 截图用）
                let view = Group {
                    if stage { Stage(open: page != "closed", startInSettings: tab == nil) }
                    else { ContentView(startInSettings: tab == nil) }
                }
                .environmentObject(store)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: name)
                let size = host.fittingSize
                let win = KeyWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                                    styleMask: .borderless, backing: .buffered, defer: false)
                win.appearance = NSAppearance(named: name)
                win.contentView = host
                win.orderFrontRegardless()
                // 成为活动窗口，开关等控件才是激活状态的颜色（否则截图里是灰的，像被禁用）
                NSApp.activate(ignoringOtherApps: true)
                win.makeKey()
                try? await Task.sleep(for: .milliseconds(600))
                // 内容高度是布局后才量出来的，再按最终尺寸调整一次窗口
                win.setContentSize(host.fittingSize)
                try? await Task.sleep(for: .milliseconds(400))

                // -scale 3：按 3 倍像素渲染（默认跟随屏幕，Retina 为 2 倍）
                let scale = UserDefaults.standard.double(forKey: "scale")
                let rep: NSBitmapImageRep? = scale > 0
                    ? NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: Int(host.bounds.width * scale), pixelsHigh: Int(host.bounds.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
                    : host.bitmapImageRepForCachingDisplay(in: host.bounds)
                if let rep {
                    rep.size = host.bounds.size
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let url = URL(fileURLWithPath: dir).appendingPathComponent("\(page)-\(mode).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
                win.orderOut(nil)
            }
        }
        UserDefaults.standard.set(ContentView.Tab.usage.rawValue, forKey: "tab")
        exit(0)
    }
}

/// 无边框窗口默认不能成为活动窗口，截图时需要它能
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
