import Foundation
import XCTest
@testable import Quotlet

final class SessionLogWatcherTests: XCTestCase {
    @MainActor
    func testDetectsNewNestedSessionAndAppend() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = project.appendingPathComponent(".build/watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let created = expectation(description: "New session detected")
        let appended = expectation(description: "Appended session detected")
        var updates = 0
        let watcher = SessionLogWatcher(paths: [sessions]) {
            updates += 1
            if updates == 1 { created.fulfill() }
            if updates == 2 { appended.fulfill() }
        }
        let directory = sessions.appendingPathComponent("2026/11/19")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rollout-test.jsonl")
        try Data("{}\n".utf8).write(to: file)
        await fulfillment(of: [created], timeout: 8)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        await fulfillment(of: [appended], timeout: 8)
        withExtendedLifetime(watcher) {}
    }
}
