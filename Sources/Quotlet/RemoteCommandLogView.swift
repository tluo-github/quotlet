import AppKit
import SwiftUI

// 「远程指令与日志」独立排查窗口：
// 1. 查看当前本机 Device ID、WebSocket 实时通道状态、路由（代理/直连）与三家 CLI 探测路径
// 2. 查看本机收到的所有远程指令执行历史（commands-history.json）：状态、目录、Prompt、回复摘要与错误
// 3. 查看实时诊断日志（WS 收发、排队指令对账、安全校验、CLI 执行与状态回报）并支持一键复制或打开日志目录

@MainActor
final class RemoteCommandLogWindowController: NSObject, NSWindowDelegate {
    static let shared = RemoteCommandLogWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: RemoteCommandLogView())
            let w = NSWindow(contentViewController: host)
            w.title = L("远程指令与诊断日志", "Remote Commands & Logs", ja: "リモートコマンドとログ", ko: "원격 명령 및 로그")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 820, height: 600))
            w.contentMinSize = NSSize(width: 640, height: 440)
            w.center()
            w.setFrameAutosaveName("QuotletRemoteLogs")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct RemoteCommandLogView: View {
    @ObservedObject private var cloud = Cloud.shared
    @ObservedObject private var remote = RemoteCommandManager.shared
    @State private var tab: Int = 0
    @State private var copiedId = false
    @State private var copiedLogs = false
    @State private var filterText = ""

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            diagnosticsHeader
                .padding(16)
                .background(Theme.group)

            Divider()

            HStack(spacing: 12) {
                Picker("", selection: $tab) {
                    Text(L("指令历史 (\(remote.recentHistory.count))", "Command History (\(remote.recentHistory.count))", ja: "コマンド履歴 (\(remote.recentHistory.count))", ko: "명령 기록 (\(remote.recentHistory.count))")).tag(0)
                    Text(L("运行日志 (\(remote.logs.count))", "Live Logs (\(remote.logs.count))", ja: "実行ログ (\(remote.logs.count))", ko: "실행 로그 (\(remote.logs.count))")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Spacer()

                TextField(L("筛选关键词…", "Filter…", ja: "フィルター…", ko: "필터…"), text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)

                Button {
                    let dir = RemoteCommandManager.debugLogURL.deletingLastPathComponent()
                    NSWorkspace.shared.open(dir)
                } label: {
                    Label(L("打开目录", "Open Folder", ja: "フォルダを開く", ko: "폴더 열기"), systemImage: "folder")
                }
                .controlSize(.small)

                if tab == 1 {
                    Button {
                        copyAllLogs()
                    } label: {
                        Label(copiedLogs ? L("已复制", "Copied", ja: "コピー済み", ko: "복사됨") : L("复制日志", "Copy Logs", ja: "ログをコピー", ko: "로그 복사"), systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)

                    Button(L("清空", "Clear", ja: "クリア", ko: "지우기")) {
                        remote.clearLogs()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if tab == 0 {
                historyList
            } else {
                logsList
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    private var diagnosticsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(remote.pollConnected ? Color.green : (remote.enabled ? Color.orange : Color.secondary))
                        .frame(width: 8, height: 8)
                    Text(remote.pollConnected
                         ? L("队列轮询正常", "Queue polling active", ja: "ポーリング正常", ko: "큐 폴링 정상")
                         : (remote.enabled
                            ? L("等待队列同步…", "Waiting for queue sync…", ja: "同期待ち…", ko: "큐 동기화 대기…")
                            : L("远程指令已关闭", "Remote commands off", ja: "リモートコマンドオフ", ko: "원격 명령 꺼짐")))
                        .font(.system(size: 13, weight: .semibold))
                    if remote.pendingOutboxCount > 0 {
                        Text(L("· 待重传 \(remote.pendingOutboxCount) 条", "· \(remote.pendingOutboxCount) retrying", ja: "· 再送待ち \(remote.pendingOutboxCount) 件", ko: "· 재전송 \(remote.pendingOutboxCount)건"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.orange)
                    }
                    if let t = remote.lastPollAt {
                        Text("· \(Self.timeFmt.string(from: t))")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    remote.probeCapabilities()
                } label: {
                    Label(L("重新探测 CLI", "Re-probe CLIs", ja: "CLI 再検出", ko: "CLI 다시 감지"), systemImage: "magnifyingglass")
                }
                .controlSize(.small)

                Button {
                    remote.reconnectAndSync()
                } label: {
                    Label(L("立即同步队列", "Sync Queue Now", ja: "今すぐ同期", ko: "지금 큐 동기화"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text(L("本机 Device ID:", "Device ID:", ja: "デバイス ID:", ko: "기기 ID:"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    let devId = cloud.deviceId ?? "—"
                    Text(devId)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                    if let id = cloud.deviceId {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(id, forType: .string)
                            copiedId = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedId = false }
                        } label: {
                            Image(systemName: copiedId ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5))
                        }
                        .buttonStyle(.plain)
                        .help(L("复制 Device ID（可与 iPhone 设备页后 6 位核对）", "Copy Device ID", ja: "Device ID をコピー", ko: "Device ID 복사"))
                    }
                }
                Spacer()
                Text(remote.enabled
                     ? L("远程指令：已开启", "Remote: Enabled", ja: "リモート：オン", ko: "원격: 켜짐")
                     : L("远程指令：已关闭", "Remote: Disabled", ja: "リモート：オフ", ko: "원격: 꺼짐"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(remote.enabled ? Color.green : Color.secondary)
            }

            if let caps = remote.capabilities {
                HStack(spacing: 10) {
                    capPill(name: "Claude", cap: caps.claude)
                    capPill(name: "Codex", cap: caps.codex)
                    capPill(name: "Antigravity (agy)", cap: caps.gemini)
                    Spacer()
                }
            }
        }
    }

    private func capPill(name: String, cap: ProviderCapability) -> some View {
        let ver = cap.version.map { " \($0)" } ?? ""
        let text = cap.available ? "\(name) ✓\(ver)" : "\(name) —"
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((cap.available ? Color.green : Color.secondary).opacity(0.13), in: Capsule())
            .foregroundStyle(cap.available ? Color.green : Color.secondary)
            .help(cap.cliPath ?? cap.note ?? "")
    }

    private var filteredHistory: [CommandHistoryEntry] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return remote.recentHistory }
        return remote.recentHistory.filter {
            $0.prompt.lowercased().contains(q)
                || ($0.project?.lowercased().contains(q) ?? false)
                || $0.provider.lowercased().contains(q)
                || $0.status.lowercased().contains(q)
                || ($0.error?.lowercased().contains(q) ?? false)
                || ($0.result?.lowercased().contains(q) ?? false)
        }
    }

    private var historyList: some View {
        Group {
            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(L("本机还没有收到过远程指令", "No remote commands received on this Mac yet", ja: "まだリモートコマンドを受信していません", ko: "이 Mac에서 수신한 원격 명령이 없습니다"))
                        .font(.system(size: 13, weight: .medium))
                    Text(L("如果 iPhone 上一直显示「排队中」，请核对上方本机 Device ID 后 6 位与 iPhone 选择的目标 Mac 是否一致，并点「重连并拉取排队指令」。",
                           "If iPhone stays on Queued, verify the Device ID above matches the Mac selected on iPhone, then click Reconnect & Sync Queue.",
                           ja: "iPhone で待機中のままの場合は、上の Device ID が iPhone で選択した Mac と一致するか確認してください。",
                           ko: "iPhone에서 대기 중이면 위의 Device ID가 iPhone에서 선택한 Mac과 일치하는지 확인하세요."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredHistory) { item in
                            commandHistoryRow(item)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func commandHistoryRow(_ item: CommandHistoryEntry) -> some View {
        let statusColor: Color = {
            switch item.status {
            case "done": return .green
            case "running", "delivered": return .blue
            case "rejected", "cancelled": return .orange
            case "failed": return .red
            default: return .secondary
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.status.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)

                Text(item.provider == "gemini" ? "Antigravity (agy)" : item.provider)
                    .font(.system(size: 11.5, weight: .semibold))

                Text(item.mode)
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                if let proj = item.project {
                    Text(proj).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }

                Spacer()

                if item.status == "running" || item.status == "delivered" || item.status == "queued" {
                    Button(L("终止", "Stop", ja: "中止", ko: "중지")) {
                        remote.cancelCommand(id: item.id)
                    }
                    .controlSize(.mini)
                    .tint(.red)
                }

                Text(Self.dateTimeFmt.string(from: item.receivedAt))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    remote.deleteHistoryEntry(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("删除这条记录", "Delete this entry", ja: "この履歴を削除", ko: "이 기록 삭제"))
            }

            Text(item.prompt)
                .font(.system(size: 12.5))
                .textSelection(.enabled)

            if let cwd = item.resolvedCwd {
                Text("cwd: \(cwd)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let res = item.result, !res.isEmpty {
                Text(res)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            if let err = item.error, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            if let sid = item.resultSessionId ?? item.sessionId {
                Text("session: \(sid) · id: \(item.id)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Theme.group, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var filteredLogs: [RemoteLogEntry] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return remote.logs }
        return remote.logs.filter {
            $0.message.lowercased().contains(q) || $0.category.lowercased().contains(q)
        }
    }

    private var logsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(filteredLogs) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.timeFmt.string(from: entry.ts))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.category)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(width: 34)
                            .padding(.vertical, 1)
                            .background(levelColor(entry.level).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(levelColor(entry.level))
                        Text(entry.message)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(entry.level == .error ? Color.red : Color.primary)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
        }
    }

    private func levelColor(_ l: RemoteLogEntry.Level) -> Color {
        switch l {
        case .ok: return .green
        case .warn: return .orange
        case .error: return .red
        case .info: return .blue
        }
    }

    private func copyAllLogs() {
        let text = remote.logs.reversed().map { e in
            "[\(Self.dateTimeFmt.string(from: e.ts))] [\(e.level.rawValue.uppercased())] [\(e.category)] \(e.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedLogs = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedLogs = false }
    }
}

// MARK: - 主面板「远程指令」标签页（360pt 宽紧凑布局）

struct RemoteTab: View {
    @ObservedObject private var cloud = Cloud.shared
    @ObservedObject private var remote = RemoteCommandManager.shared
    let openSettings: () -> Void

    @State private var expandedIds: Set<String> = []
    @State private var showLogs = false
    @State private var copiedDevId = false

    private static let clockFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !cloud.isSignedIn {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("登录 Quotlet Cloud 后可接收远程指令", "Sign in to Quotlet Cloud to receive remote commands", ja: "Quotlet Cloud にログインしてリモートコマンドを受信", ko: "원격 명령을 받으려면 Quotlet Cloud에 로그인하세요"))
                        .font(Theme.bodyMedium)
                        .foregroundStyle(Theme.text)
                    Text(L("仅在你在本机手动开启后生效，且只允许在近 30 天使用过的项目目录中执行。",
                           "Off by default. Only runs in project folders used in the last 30 days.",
                           ja: "既定でオフ。直近 30 日間のプロジェクトのみ許可されます。",
                           ko: "기본값은 꺼짐이며 최근 30일간 사용한 프로젝트 폴더에서만 실행됩니다."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                    ChipButton(title: L("登录", "Sign in", ja: "ログイン", ko: "로그인")) { cloud.signIn() }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.group))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
            } else {
                statusCard
                historySection
                liveLogSection
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(remote.pollConnected ? Color.green : (remote.enabled ? Color.orange : Color.secondary))
                        .frame(width: 7, height: 7)
                    Text(remote.pollConnected
                         ? L("队列轮询中", "Queue polling", ja: "ポーリング中", ko: "큐 폴링 중")
                         : (remote.enabled
                            ? L("等待队列同步…", "Syncing queue…", ja: "同期中…", ko: "동기화 중…")
                            : L("远程指令已关闭", "Remote off", ja: "オフ", ko: "꺼짐")))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if remote.pendingOutboxCount > 0 {
                        Text(L("· 待重传 \(remote.pendingOutboxCount)", "· \(remote.pendingOutboxCount) retrying", ja: "· 再送 \(remote.pendingOutboxCount)", ko: "· 재전송 \(remote.pendingOutboxCount)"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                SwitchToggle(isOn: Binding(get: { remote.enabled }, set: { remote.setEnabled($0) }))
            }

            if let id = cloud.deviceId {
                HStack(spacing: 6) {
                    Text(L("设备 ID", "Device ID", ja: "デバイス ID", ko: "기기 ID"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text2)
                    Text(String(id.suffix(8)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(id, forType: .string)
                        copiedDevId = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedDevId = false }
                    } label: {
                        Image(systemName: copiedDevId ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.text2)
                    }
                    .buttonStyle(.plain)
                    .help(L("复制完整 Device ID 与 iPhone 核对", "Copy full Device ID", ja: "完全な Device ID をコピー", ko: "전체 Device ID 복사"))
                    Spacer()
                }
            }

            if let caps = remote.capabilities {
                HStack(spacing: 6) {
                    miniCap("Claude", ok: caps.claude.available)
                    miniCap("Codex", ok: caps.codex.available)
                    miniCap("Antigravity (agy)", ok: caps.gemini.available)
                }
            }

            Hairline()

            HStack(spacing: 8) {
                ChipButton(title: L("重连拉取", "Sync Queue", ja: "再接続", ko: "재연결")) {
                    remote.reconnectAndSync()
                }
                ChipButton(title: L("完整日志窗口", "Log Window", ja: "ログウィンドウ", ko: "로그 창")) {
                    RemoteCommandLogWindowController.shared.show()
                }
                Spacer()
                Button(L("设置", "Settings", ja: "設定", ko: "설정")) {
                    openSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.group))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func miniCap(_ title: String, ok: Bool) -> some View {
        Text("\(title) \(ok ? "✓" : "—")")
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((ok ? Color.green : Color.secondary).opacity(0.13), in: Capsule())
            .foregroundStyle(ok ? Color.green : Theme.text2)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("指令执行历史", "Command History", ja: "コマンド履歴", ko: "명령 실행 기록"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if remote.recentHistory.contains(where: { !["queued", "delivered", "running"].contains($0.status) }) {
                    Button(L("清空已结束", "Clear finished", ja: "完了分を消去", ko: "완료된 기록 지우기")) {
                        remote.clearFinishedHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text2)
                }
                Text("\(remote.recentHistory.count)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Theme.text2)
            }

            if remote.recentHistory.isEmpty {
                Text(L("本机暂未收到远程指令。在 iPhone 或网页端选中本台 Mac 发送后，这里会实时显示进度与结果。",
                       "No commands received yet. Send one from iPhone or web to see live progress here.",
                       ja: "まだコマンドを受信していません。",
                       ko: "아직 수신한 원격 명령이 없습니다."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.group))
            } else {
                ForEach(remote.recentHistory.prefix(15)) { item in
                    compactHistoryCard(item)
                }
            }
        }
    }

    private func compactHistoryCard(_ item: CommandHistoryEntry) -> some View {
        let expanded = expandedIds.contains(item.id)
        let color: Color = {
            switch item.status {
            case "done": return .green
            case "running", "delivered": return .blue
            case "rejected", "cancelled": return .orange
            case "failed": return .red
            default: return .secondary
            }
        }()

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(item.status.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)

                Text(item.provider == "gemini" ? "Antigravity" : item.provider.capitalized)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text)

                if let proj = item.project, !proj.isEmpty {
                    Text("· \(proj)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
                Spacer()
                Text(Self.clockFmt.string(from: item.receivedAt))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.text2)
                Button {
                    expandedIds.remove(item.id)
                    remote.deleteHistoryEntry(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.text2)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("删除这条记录", "Delete this entry", ja: "この履歴を削除", ko: "이 기록 삭제"))
            }

            Text(item.prompt)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text)
                .lineLimit(expanded ? nil : 2)

            if let res = item.result, !res.isEmpty {
                Text(res)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
            }

            if let err = item.error, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .lineLimit(expanded ? nil : 2)
                    .textSelection(.enabled)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.group))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded { expandedIds.remove(item.id) } else { expandedIds.insert(item.id) }
        }
        .contextMenu {
            Button(role: .destructive) {
                expandedIds.remove(item.id)
                remote.deleteHistoryEntry(id: item.id)
            } label: {
                Label(L("删除这条记录", "Delete entry", ja: "この履歴を削除", ko: "이 기록 삭제"), systemImage: "trash")
            }
        }
    }

    private var liveLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showLogs.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showLogs ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(L("运行日志 (\(remote.logs.count))", "Live Logs (\(remote.logs.count))", ja: "実行ログ (\(remote.logs.count))", ko: "실행 로그 (\(remote.logs.count))"))
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Theme.text2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showLogs {
                VStack(alignment: .leading, spacing: 4) {
                    if remote.logs.isEmpty {
                        Text(L("暂无日志", "No logs yet", ja: "ログなし", ko: "로그 없음"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.text2)
                    } else {
                        ForEach(remote.logs.prefix(15)) { entry in
                            HStack(alignment: .top, spacing: 5) {
                                Text(Self.clockFmt.string(from: entry.ts))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(Theme.text2)
                                Text("[\(entry.category)]")
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(entry.level == .error ? Color.red : (entry.level == .ok ? Color.green : Theme.text2))
                                Text(entry.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.group))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
    }
}
