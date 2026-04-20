import Foundation
import SliceCore

/// 生产环境使用的 LLMProviderFactory 实现
public struct OpenAIProviderFactory: LLMProviderFactory {
    public init() {}

    public func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        // MVP v0.1 只有 OpenAI 兼容一种类型；未来可按 provider.id 前缀或新字段分发
        OpenAICompatibleProvider(baseURL: provider.baseURL, apiKey: apiKey)
    }
}
