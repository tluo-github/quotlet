import SwiftUI

@main
struct QuotabarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            if store.menuBarShowsWarning {
                Image(systemName: "exclamationmark.triangle")
            } else {
                HStack(spacing: 3) {
                    Image(systemName: store.menuBarSymbol)
                    Text(store.menuBarText)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 浏览器登录完成后打开 quotabar://auth?...
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { MainActor.assumeIsolated { Cloud.shared.handleCallback(url) } }
    }
}
