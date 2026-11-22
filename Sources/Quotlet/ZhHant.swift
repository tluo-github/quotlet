import Foundation

/// 简体 → 繁体（台湾）转换：对照表由 scripts/gen-zh-hant.py 从源码里的简体文案生成（ZhHantData.swift）。
/// 按最长词优先匹配，查不到的字原样保留；中文引号“”换成台湾习惯的「」。
enum ZhHant {
    private static let table: [String: String] = {
        var t: [String: String] = [:]
        for line in ZhHantData.pairs.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { t[String(parts[0])] = String(parts[1]) }
        }
        return t
    }()
    private static let maxKeyLength: Int = table.keys.map(\.count).max() ?? 1

    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func convert(_ s: String) -> String {
        lock.lock()
        if let hit = cache[s] { lock.unlock(); return hit }
        lock.unlock()

        let chars = Array(s)
        var out = ""
        out.reserveCapacity(s.utf8.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "“" { out.append("「"); i += 1; continue }
            if c == "”" { out.append("」"); i += 1; continue }
            guard isHan(c) else { out.append(c); i += 1; continue }
            var runEnd = i
            while runEnd < chars.count, isHan(chars[runEnd]) { runEnd += 1 }
            var len = min(maxKeyLength, runEnd - i)
            var matched = false
            while len > 0 {
                if let v = table[String(chars[i..<(i + len)])] {
                    out += v
                    i += len
                    matched = true
                    break
                }
                len -= 1
            }
            if !matched { out.append(c); i += 1 }
        }

        lock.lock()
        if cache.count > 4000 { cache.removeAll(keepingCapacity: true) }
        cache[s] = out
        lock.unlock()
        return out
    }

    private static func isHan(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v)
    }
}
