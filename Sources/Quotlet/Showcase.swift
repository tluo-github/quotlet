import AppKit
import SwiftUI

/// 录演示视频用：`Quotlet --showcase` 在屏幕左上角 (60, 60) 开一个 420pt 宽的窗口，
/// 里面是干净的背景、一条仿状态栏和真实的面板。点状态栏标签打开 / 关闭面板。
/// 窗口位置固定，方便脚本按坐标操作鼠标录屏。
enum Showcase {
    static let origin = CGPoint(x: 60, y: 60)          // 左上角，屏幕坐标（左上为原点）
    static let size = CGSize(width: 420, height: ContentView.panelHeight + 90)
    static var enabled: Bool { CommandLine.arguments.contains("--showcase") }
    private static var window: NSWindow?

    @MainActor
    static func show(store: Store) {
        let screenH = NSScreen.screens.first?.frame.height ?? 1000
        let frame = NSRect(x: origin.x, y: screenH - origin.y - size.height, width: size.width, height: size.height)
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .floating
        win.isOpaque = true
        win.hasShadow = false
        win.contentView = NSHostingView(rootView: Stage().environmentObject(store))
        win.orderFrontRegardless()
        window = win
    }
}

struct Stage: View {
    @EnvironmentObject var store: Store
    @State private var open: Bool
    private let startInSettings: Bool

    init(open: Bool = false, startInSettings: Bool = false) {
        _open = State(initialValue: open)
        self.startInSettings = startInSettings
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.56, green: 0.64, blue: 0.75), Color(red: 0.86, green: 0.81, blue: 0.77)],
                           startPoint: .top, endPoint: .bottom)

            // 仿状态栏
            Rectangle().fill(.white.opacity(0.32)).frame(height: 28)
            HStack(spacing: 3) {
                Image(systemName: store.menuBarSymbol)
                Text(store.menuBarText)
            }
            .font(.system(size: 13))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(width: 145, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(open ? 0.45 : 0)))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } }
            .offset(x: 265, y: 3)

            if open {
                ContentView(startInSettings: startInSettings)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.08)))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .offset(x: 40, y: 40)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .frame(width: Showcase.size.width, height: Showcase.size.height)
    }
}
