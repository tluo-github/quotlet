import SwiftUI

@main
enum QuotletEntry {
    static func main() {
        // `--hook` 命令行模式：在 SwiftUI 启动前直接写 events.jsonl 并退出，不启界面、不联网、永远 exit 0
        if CommandLine.arguments.contains("--hook") {
            HookCLI.run()
            return
        }
        QuotletApp.main()
    }
}

struct QuotletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.menuBarSymbol)
                Text(store.menuBarText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 浏览器登录完成后打开 quotlet://auth?...
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { MainActor.assumeIsolated { Cloud.shared.handleCallback(url) } }
    }
}
