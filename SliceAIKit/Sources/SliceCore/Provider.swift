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
}
