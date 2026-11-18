// 找某个进程的带标题窗口编号，给 screencapture -l 用。用法：swift scripts/window-id.swift <pid>
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1]) ?? 0
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
    if let name = w[kCGWindowName as String] as? String, !name.isEmpty, let n = w[kCGWindowNumber as String] {
        print(n)
        break
    }
}
