import AppKit
import ServiceManagement

/// 0.5 改名：用 DMG 升级的老用户「应用程序」里会同时有 Quotabar.app（旧名）和 Quotlet.app，
/// 两个 bundle id 相同，会出现两个状态栏图标。新版启动时发现旧的就先把它退出，再问要不要移到废纸篓；
/// 开机启动打开着的话重新登记一次，让它指向新的 app。
@MainActor
enum LegacyApp {
    static let oldURL = URL(fileURLWithPath: "/Applications/Quotabar.app")

    static func check() {
        let me = Bundle.main.bundleURL.standardizedFileURL
        // 只在装好的正式版里检查（开发版从 build/ 运行时不去动用户正在用的旧版）
        guard me.path.contains("/Applications/"), me != oldURL.standardizedFileURL,
              FileManager.default.fileExists(atPath: oldURL.path) else { return }

        // 旧版还开着：退出它，免得状态栏上有两个图标
        if let id = Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id)
            where app.bundleURL?.standardizedFileURL == oldURL.standardizedFileURL {
                app.terminate()
            }
        }

        // 同一个版本只问一次；选了「保留」就不再打扰
        let key = "legacyAppAsked"
        guard UserDefaults.standard.string(forKey: key) == nil else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Quotabar 已改名为 Quotlet", "Quotabar is now Quotlet", ja: "Quotabar は Quotlet になりました", ko: "Quotabar가 Quotlet으로 바뀌었습니다")
        alert.informativeText = L("“应用程序”里还有旧版 Quotabar.app，它和 Quotlet 是同一个 app。要把旧版移到废纸篓吗？",
                                  "The old Quotabar.app is still in Applications. It's the same app as Quotlet. Move the old copy to the Trash?",
                                  ja: "アプリケーションフォルダに古い Quotabar.app が残っています。Quotlet と同じアプリです。古い方をゴミ箱に入れますか？",
                                  ko: "응용 프로그램 폴더에 예전 Quotabar.app이 남아 있습니다. Quotlet과 같은 앱입니다. 예전 앱을 휴지통으로 옮길까요?")
        alert.addButton(withTitle: L("移到废纸篓", "Move to Trash", ja: "ゴミ箱に入れる", ko: "휴지통으로 이동"))
        alert.addButton(withTitle: L("保留", "Keep", ja: "残す", ko: "유지"))
        let answer = alert.runModal()
        UserDefaults.standard.set(answer == .alertFirstButtonReturn ? "trashed" : "kept", forKey: key)
        guard answer == .alertFirstButtonReturn else { return }

        NSWorkspace.shared.recycle([oldURL]) { _, error in
            if let error { NSLog("[legacy] move to trash failed: \(error.localizedDescription)") }
        }
        // 开机启动：重新登记，指向现在这个 app
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
        }
    }
}
