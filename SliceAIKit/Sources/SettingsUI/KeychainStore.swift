import Foundation
import Security
import SliceCore

/// 基于系统 Keychain 的 KeychainAccessing 实现
///
/// 采用 macOS 传统文件型 Keychain（`kSecClassGenericPassword`），按 `service + providerId`
/// 定位条目。所有方法签名声明为 `async throws`，但内部不真正 `await` 任何挂起点——
/// 仅用于跨 actor 调用时无需阻塞主线程，且 Security 框架 API 本身线程安全。
public struct KeychainStore: KeychainAccessing {

    /// Keychain 的 service 名称，用于区分本应用与其他应用
    private let service: String

    /// 初始化
    /// - Parameter service: service 名称，默认为 `com.sliceai.lite.providers`
    public init(service: String = "com.sliceai.lite.providers") {
        self.service = service
    }

    /// 读取指定 provider 的 API Key
    /// - Parameter providerId: provider 标识（用作 account）
    /// - Returns: API Key 字符串；条目不存在或解码失败时返回 nil
    public func readAPIKey(providerId: String) async throws -> String? {
        // 构造查询：按 service + account 精确匹配，要求返回数据
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        // 条目不存在视为 nil（非错误）
        if status == errSecItemNotFound { return nil }
        // 其他失败或数据类型不符均视为 nil（若需严格区分可改为抛错）
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 写入或覆盖指定 provider 的 API Key
    /// - Parameters:
    ///   - value: 要写入的 API Key
    ///   - providerId: provider 标识
    public func writeAPIKey(_ value: String, providerId: String) async throws {
        let data = Data(value.utf8)
        // 定位条目的查询（不含数据，避免与 update 字典冲突）
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            // 条目不存在则新增
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw NSError(domain: "KeychainStore", code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: "KeychainStore", code: Int(status))
        }
    }

    /// 删除指定 provider 的 API Key
    /// - Parameter providerId: provider 标识
    public func deleteAPIKey(providerId: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId
        ]
        let status = SecItemDelete(query as CFDictionary)
        // 删除时"条目不存在"视为幂等成功
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: "KeychainStore", code: Int(status))
        }
    }
}
