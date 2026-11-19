import CoreServices
import Foundation

/// 目录级监听覆盖新会话、子代理、归档和文件替换；解析仍由 SessionScanner 的缓存负责。
@MainActor
final class SessionLogWatcher {
    private let paths: [String]
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var pendingUpdate: DispatchWorkItem?

    init(paths: [URL], onChange: @escaping () -> Void) {
        self.paths = paths.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        self.onChange = onChange
        // 从父目录监听，覆盖日志目录重建；尚未创建的父目录向上找到已有目录。
        let roots = Set(self.paths.map { path -> String in
            var root = URL(fileURLWithPath: path).deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            while !FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                let parent = root.deletingLastPathComponent()
                if parent == root { break }
                root = parent
            }
            return root.path
        })
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagWatchRoot
        stream = FSEventStreamCreate(nil, { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<SessionLogWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            // 回调固定在主队列，和停止监听、合并刷新串行执行。
            MainActor.assumeIsolated {
                for index in 0..<count {
                    let rescanFlags = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                    let lost = eventFlags[index] & FSEventStreamEventFlags(rescanFlags) != 0
                    if lost || watcher.paths.contains(where: { path in
                        changed[index] == path || changed[index].hasPrefix(path + "/") || path.hasPrefix(changed[index] + "/")
                    }) {
                        watcher.scheduleUpdate()
                        break
                    }
                }
            }
        }, &context, Array(roots) as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, FSEventStreamCreateFlags(flags))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        if !FSEventStreamStart(stream) {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func scheduleUpdate() {
        // 持续写入期间也每秒更新，避免不断延后导致长会话一直没有刷新。
        guard pendingUpdate == nil else { return }
        let update = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingUpdate = nil
            self.onChange()
        }
        pendingUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: update)
    }

    deinit {
        pendingUpdate?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
