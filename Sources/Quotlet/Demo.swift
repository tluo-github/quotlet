import Foundation

/// 演示模式（`-demo YES`）：录屏、截图时把会话标题和项目名换成示例文字，
/// 避免公开个人项目信息。额度和 token 数字保持真实。
enum Demo {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "demo") }

    private static let titles: [(String, String, String, String)] = [
        ("修复登录页的表单校验", "Fix form validation on the login page", "ログイン画面のフォーム検証を修正", "로그인 페이지 폼 검증 수정"),
        ("给订单接口加分页", "Add pagination to the orders API", "注文 API にページングを追加", "주문 API에 페이지네이션 추가"),
        ("重构图片上传组件", "Refactor the image upload component", "画像アップロード部品をリファクタ", "이미지 업로드 컴포넌트 리팩터링"),
        ("排查夜间任务超时", "Debug the nightly job timeout", "夜間ジョブのタイムアウトを調査", "야간 작업 타임아웃 디버깅"),
        ("写搜索功能的单元测试", "Write unit tests for search", "検索機能の単体テストを書く", "검색 기능 단위 테스트 작성"),
        ("升级依赖并修复告警", "Upgrade dependencies and fix warnings", "依存関係を更新して警告を修正", "의존성 업그레이드 및 경고 수정"),
        ("优化首页加载速度", "Speed up the home page", "トップページの表示を高速化", "홈 화면 로딩 속도 개선"),
        ("设计通知设置数据表", "Design the notification settings schema", "通知設定のテーブル設計", "알림 설정 스키마 설계"),
        ("迁移到新的日志库", "Migrate to the new logging library", "新しいログライブラリへ移行", "새 로깅 라이브러리로 이전"),
        ("整理 README 和示例", "Tidy up the README and examples", "README とサンプルを整理", "README와 예제 정리"),
    ]
    private static let projects = ["web-app", "api-server", "ios-client", "data-pipeline", "docs"]

    static func anonymize(_ snap: LocalSnapshot) -> LocalSnapshot {
        var names: [String: String] = [:]
        func fake(_ real: String) -> String {
            if let n = names[real] { return n }
            let n = projects[names.count % projects.count]
            names[real] = n
            return n
        }
        let sessions = snap.sessions.enumerated().map { i, s in
            let t = titles[i % titles.count]
            return SessionSummary(id: s.id, project: fake(s.project), cwd: nil,
                                  title: L(t.0, t.1, ja: t.2, ko: t.3), start: s.start, end: s.end, tokens: s.tokens,
                                  subagentTokens: s.subagentTokens, requests: s.requests, mainModel: s.mainModel, source: s.source)
        }
        let messages = snap.messages.map { m -> MessageUsage in var m = m; m.project = fake(m.project); return m }
        return LocalSnapshot(sessions: sessions, messages: messages, codexLimits: snap.codexLimits)
    }
}
