import Foundation

/// LLM 供应商配置（API Key 不在此结构内，通过 apiKeyRef 指向 Keychain）
public struct Provider: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var apiKeyRef: String     // 如 "keychain:openai-official"
    public var defaultModel: String
    /// 该 Provider 支持的 thinking 切换机制；nil 表示不支持，结果面板不显示 toggle
    public var thinking: ProviderThinkingCapability?

    /// 构造 Provider 配置
    /// - Parameters:
    ///   - id: Provider 唯一标识（如 "openai"）
    ///   - name: 显示名称（如 "OpenAI"）
    ///   - baseURL: API 基础地址
    ///   - apiKeyRef: Keychain 引用字符串，用于懒加载真实密钥
    ///   - defaultModel: 默认模型标识，Tool 未指定 modelId 时使用
    ///   - thinking: 该 Provider 的 thinking 切换机制，nil = 不支持
    public init(id: String, name: String, baseURL: URL,
                apiKeyRef: String, defaultModel: String,
                thinking: ProviderThinkingCapability? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.defaultModel = defaultModel
        self.thinking = thinking
    }

    /// JSON 字段名映射，集中管理所有 key
    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKeyRef, defaultModel, thinking
    }

    /// 自定义 decode：thinking 使用 decodeIfPresent 保证向后兼容
    ///
    /// 旧版 config.json 不含 thinking 字段，解码时回落到 nil（不支持），
    /// 避免因缺字段抛 DecodingError。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decode(URL.self, forKey: .baseURL)
        self.apiKeyRef = try container.decode(String.self, forKey: .apiKeyRef)
        self.defaultModel = try container.decode(String.self, forKey: .defaultModel)
        // thinking 字段可选：旧版 config.json 不含此字段时解码为 nil
        self.thinking = try container.decodeIfPresent(
            ProviderThinkingCapability.self, forKey: .thinking
        )
    }

    /// apiKeyRef 使用的 scheme 前缀；未来扩展 env: / file: 时在此枚举
    public static let keychainRefPrefix = "keychain:"

    /// 解析 apiKeyRef 得到 Keychain 中的 account 名；非 keychain: 前缀返回 nil
    public var keychainAccount: String? {
        guard apiKeyRef.hasPrefix(Self.keychainRefPrefix) else { return nil }
        return String(apiKeyRef.dropFirst(Self.keychainRefPrefix.count))
    }
}
