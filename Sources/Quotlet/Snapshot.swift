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

    /// 仅供开发截图复现折线图选中时刻，不移动用户的鼠标。
    static var projectCursor: Date? {
        #if DEBUG
        guard directory != nil,
              let value = ProcessInfo.processInfo.environment["QUOTLET_SNAPSHOT_PROJECT_CURSOR"],
              let timestamp = Double(value) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
        #else
        return nil
        #endif
    }

    /// 仅在开发截图时模拟悬停位置，用来检查浮动提示框在左右边缘的布局。
    static var throughputCursorFraction: Double? {
        #if DEBUG
        guard directory != nil,
              let value = ProcessInfo.processInfo.environment["QUOTLET_SNAPSHOT_THROUGHPUT_CURSOR"],
              let fraction = Double(value), fraction.isFinite, (0...1).contains(fraction) else { return nil }
        return fraction
        #else
        return nil
        #endif
    }

    @MainActor
    static func run(store: Store, dir: String) async {
        try? await Task.sleep(for: .seconds(2))
        // 等本机日志扫描完（最多 30 秒）
        for _ in 0..<60 where store.local == nil || store.isScanning { try? await Task.sleep(for: .milliseconds(500)) }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let snapshotWidth = UserDefaults.standard.double(forKey: "snapshotHistoryWidth")
        let snapshotHeight = UserDefaults.standard.double(forKey: "snapshotHistoryHeight")
        let stage = UserDefaults.standard.bool(forKey: "stage")
        let tab = UserDefaults.standard.string(forKey: "snapshotPanelTab").flatMap(ContentView.Tab.init(rawValue:))
        // -stage YES 时多出一张 "closed"：只有仿状态栏、面板收起（演示视频的开头）
        // 页面名 + 是否打开设置；history 是用量历史窗口
        var pages: [(String, Bool)] = [("usage", false), ("settings", true), ("history", false)]
        if let tab { pages = [(tab.rawValue, false)] }
        else if stage { pages.insert(("closed", false), at: 0) }
        for (mode, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            for (page, settings) in pages {
                // -stage YES：带展示背景和仿状态栏（README 截图用）
                let view = Group {
                    if let tab { ContentView(initialTab: tab) }
                    else if page == "history" { HistoryView().frame(width: snapshotWidth > 0 ? snapshotWidth : 1120, height: snapshotHeight > 0 ? snapshotHeight : 900) }
                    else if stage { Stage(open: page != "closed", startInSettings: settings) }
                    else { ContentView(startInSettings: settings) }
                }
                .environmentObject(store)
                let controller = NSHostingController(rootView: view)
                let host = controller.view
                host.appearance = NSAppearance(named: name)
                let size = host.fittingSize
                let win = KeyWindow(contentViewController: controller)
                if page == "history" {
                    controller.sceneBridgingOptions = [.toolbars, .title]
                    win.title = L("用量历史", "Usage History", ja: "使用量の履歴", ko: "사용량 기록")
                    win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                    win.toolbarStyle = .unified
                } else {
                    win.styleMask = .borderless
                }
                win.setContentSize(size)
                win.setFrameOrigin(NSPoint(x: -10000, y: -10000))
                win.appearance = NSAppearance(named: name)
                win.orderFrontRegardless()
                // 成为活动窗口，开关等控件才是激活状态的颜色（否则截图里是灰的，像被禁用）
                NSApp.activate(ignoringOtherApps: true)
                win.makeKey()
                try? await Task.sleep(for: .milliseconds(600))
                // 内容高度是布局后才量出来的，再按最终尺寸调整一次窗口
                win.setContentSize(host.fittingSize)
                try? await Task.sleep(for: .milliseconds(400))

                // 历史窗口连同原生工具栏渲染，不依赖屏幕录制权限。
                let capture = page == "history" ? (win.contentView?.superview ?? host) : host
                // -scale 3：按 3 倍像素渲染（默认跟随屏幕，Retina 为 2 倍）
                let scale = UserDefaults.standard.double(forKey: "scale")
                let rep: NSBitmapImageRep? = scale > 0
                    ? NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: Int(capture.bounds.width * scale), pixelsHigh: Int(capture.bounds.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
                    : capture.bitmapImageRepForCachingDisplay(in: capture.bounds)
                if let rep {
                    rep.size = capture.bounds.size
                    capture.cacheDisplay(in: capture.bounds, to: rep)
                    let url = URL(fileURLWithPath: dir).appendingPathComponent("\(page)-\(mode).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
                win.orderOut(nil)
            }
        }
        exit(0)
    }
}

/// 无边框窗口默认不能成为活动窗口，截图时需要它能
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
