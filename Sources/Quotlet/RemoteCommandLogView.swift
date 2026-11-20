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
                        .fill(remote.wsConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(remote.wsConnected
                         ? L("实时通道已连接", "Live channel connected", ja: "リアルタイム接続中", ko: "실시간 채널 연결됨")
                         : L("实时通道未连接", "Live channel disconnected", ja: "未接続", ko: "연결 끊김"))
                        .font(.system(size: 13, weight: .semibold))
                    if !remote.wsRouteLabel.isEmpty {
                        Text("(\(remote.wsRouteLabel))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    if let t = remote.lastWSConnectedAt {
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
                    Label(L("重连并拉取排队指令", "Reconnect & Sync Queue", ja: "再接続して同期", ko: "재연결 및 동기화"), systemImage: "arrow.clockwise")
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
            case "rejected": return .orange
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

                Text(Self.dateTimeFmt.string(from: item.receivedAt))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
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
