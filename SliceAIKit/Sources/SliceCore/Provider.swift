import Foundation

/// LLM 供应商配置（API Key 不在此结构内，通过 apiKeyRef 指向 Keychain）
public struct Provider: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var apiKeyRef: String     // 如 "keychain:openai-official"
    public var defaultModel: String

    /// 构造 Provider 配置
    /// - Parameters:
    ///   - id: Provider 唯一标识（如 "openai"）
    ///   - name: 显示名称（如 "OpenAI"）
    ///   - baseURL: API 基础地址
    ///   - apiKeyRef: Keychain 引用字符串，用于懒加载真实密钥
    ///   - defaultModel: 默认模型标识，Tool 未指定 modelId 时使用
    public init(id: String, name: String, baseURL: URL,
                apiKeyRef: String, defaultModel: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.defaultModel = defaultModel
    }

    /// apiKeyRef 使用的 scheme 前缀；未来扩展 env: / file: 时在此枚举
    public static let keychainRefPrefix = "keychain:"

    /// 解析 apiKeyRef 得到 Keychain 中的 account 名；非 keychain: 前缀返回 nil
    public var keychainAccount: String? {
        guard apiKeyRef.hasPrefix(Self.keychainRefPrefix) else { return nil }
        return String(apiKeyRef.dropFirst(Self.keychainRefPrefix.count))
    }
}
