import XCTest
@testable import Quotlet

final class SharedUsageTests: XCTestCase {
    private func quota(_ device: String, _ provider: String, at seconds: Double, percent: Double = 40,
                       resetsAt: Double? = nil, account: String? = nil) -> SharedQuota {
        let json: [String: Any] = [
            "device_id": device, "device_name": "Mac " + device, "provider": provider,
            "account_key": account ?? "default", "plan": "Pro", "fetched_at": seconds * 1000,
            "limits": [["kind": "session", "title": "5h", "percent": percent, "resets_at": (resetsAt ?? seconds + 3600) * 1000]],
        ]
        return try! JSONDecoder().decode(SharedQuota.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testResolverUsesNewestOtherMacOnlyWhenNewerThanLocal() {
        let rows = [quota("a", "gemini", at: 1000), quota("b", "gemini", at: 2000), quota("me", "gemini", at: 3000),
                    quota("c", "gemini", at: 9000, account: "work")]
        // 本机没有 Gemini 额度（只装了 CLI）：用其他 Mac 中最新的一份，跳过本机自己上报的旧行与其他账号
        XCTAssertEqual(SharedQuotaResolver.newest(rows, provider: "gemini", localObservedAt: nil, excludingDevice: "me")?.device_id, "b")
        // 本机数据更新：用本机
        XCTAssertNil(SharedQuotaResolver.newest(rows, provider: "gemini", localObservedAt: Date(timeIntervalSince1970: 2500), excludingDevice: "me"))
        XCTAssertNil(SharedQuotaResolver.newest(rows, provider: "codex", localObservedAt: nil, excludingDevice: "me"))
    }

    func testResolverRejectsStaleSameWindowRemoteSnapshotWithNewerTimestamp() {
        let now = Date(timeIntervalSince1970: 1200)
        let resetSeconds: Double = 5000
        let localLimits = [
            LimitItem(id: "local-s", kind: "session", title: "5h", percent: 97, severity: nil,
                      resetsAt: Date(timeIntervalSince1970: resetSeconds))
        ]
        // 另一台旧客户端空闲重绘在 t=1200 上传了同窗口的 74%，不能覆盖本机 t=1000 采集到的 97%
        let staleRemote = [quota("other", "claude", at: 1200, percent: 74, resetsAt: resetSeconds)]
        XCTAssertNil(SharedQuotaResolver.newest(staleRemote, provider: "claude",
                                                localObservedAt: Date(timeIntervalSince1970: 1000),
                                                excludingDevice: "me", localLimits: localLimits, now: now))

        // 另一台 Mac 真正继续使用到了 98%，正常采纳
        let progressedRemote = [quota("other", "claude", at: 1200, percent: 98, resetsAt: resetSeconds)]
        XCTAssertEqual(SharedQuotaResolver.newest(progressedRemote, provider: "claude",
                                                  localObservedAt: Date(timeIntervalSince1970: 1000),
                                                  excludingDevice: "me", localLimits: localLimits, now: now)?.device_id, "other")

        // 进入下一个新重置窗口（如 2%），正常采纳
        let nextCycleNow = Date(timeIntervalSince1970: 5100)
        let nextCycleRemote = [quota("other", "claude", at: 5100, percent: 2, resetsAt: resetSeconds + 18_000)]
        XCTAssertEqual(SharedQuotaResolver.newest(nextCycleRemote, provider: "claude",
                                                  localObservedAt: Date(timeIntervalSince1970: 1000),
                                                  excludingDevice: "me", localLimits: localLimits, now: nextCycleNow)?.device_id, "other")
    }

    func testExpiredSharedWindowShowsZero() {
        let q = quota("a", "codex", at: 1000, percent: 80, resetsAt: 1500)
        let item = q.limitItems(now: Date(timeIntervalSince1970: 2000)).first
        XCTAssertEqual(item?.percent, 0)
        XCTAssertNil(item?.resetsAt)
        XCTAssertEqual(q.limitItems(now: Date(timeIntervalSince1970: 1200)).first?.percent, 80)
    }

    func testOverviewDecodesAllDeviceRows() throws {
        let json = """
        {"now":1,"usage":[{"device_id":"a","provider":"gemini","account_key":"default","device_name":"Mac A","plan":null,
          "limits":[{"kind":"session","percent":12.5}],"fetched_at":1000}],
         "shared_usage":[],"today":{"day":"2026-11-22","tokens_in":1,"tokens_out":2,"tokens_cache_read":3,"tokens_cache_write":4,"requests":5,"total":10},
         "devices":[{"id":"a","name":"Mac A","online":true,"remote_enabled":false},{"id":"b","name":"Mac B","online":false}],"sessions":[]}
        """
        let o = try JSONDecoder().decode(SharedOverview.self, from: Data(json.utf8))
        XCTAssertEqual(o.usage.first?.limits.first?.percent, 12.5)
        XCTAssertEqual(o.today?.tokens.total, 10)
        XCTAssertEqual(o.devices.count, 2)
    }

    @MainActor
    func testDailyRowsKeepSessionsSeparate() {
        let ts = Date(timeIntervalSince1970: 1_795_300_000)
        func msg(_ sid: String, _ out: Int) -> MessageUsage {
            var m = MessageUsage(ts: ts, model: "gemini-3-pro", tokens: TokenCount(input: 1, output: out, cacheRead: 0, cacheWrite: 0))
            m.project = "Antigravity CLI"; m.source = .gemini; m.sessionId = sid
            return m
        }
        let rows = CloudSync.dailyRows(LocalSnapshot(sessions: [], messages: [msg("gemini-a", 10), msg("gemini-a", 5), msg("gemini-b", 7)]))
        XCTAssertEqual(rows.count, 2)
        let a = rows.first { ($0.payload["session_id"] as? String) == "gemini-a" }
        XCTAssertEqual(a?.payload["tokens_out"] as? Int, 15)
        XCTAssertEqual(a?.payload["requests"] as? Int, 2)
    }
}
