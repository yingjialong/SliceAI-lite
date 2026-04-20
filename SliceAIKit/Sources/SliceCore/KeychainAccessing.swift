import Foundation

/// Keychain 抽象，便于单元测试注入假实现
public protocol KeychainAccessing: Sendable {
    /// 读取 API Key；不存在返回 nil
    func readAPIKey(providerId: String) async throws -> String?

    /// 写入或覆盖 API Key
    func writeAPIKey(_ value: String, providerId: String) async throws

    /// 删除（可选使用）
    func deleteAPIKey(providerId: String) async throws
}
