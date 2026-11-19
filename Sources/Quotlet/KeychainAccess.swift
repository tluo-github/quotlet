import Foundation
import Security

/// Claude Code 和旧版 Quotlet 的条目在传统登录钥匙串里。
/// LAContext.interactionNotAllowed 不会禁止传统 ACL 的密码对话框，还必须关闭旧式交互。
/// 此开关作用于当前进程：所有钥匙串操作串行执行，并恢复进入前的状态。
enum KeychainAccess {
    private static let lock = NSLock()

    static func perform(allowInteraction: Bool, _ operation: () -> OSStatus) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        var previous: DarwinBoolean = false
        let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
        guard readStatus == errSecSuccess else { return readStatus }
        let setStatus = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard setStatus == errSecSuccess else { return setStatus }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return operation()
    }
}
