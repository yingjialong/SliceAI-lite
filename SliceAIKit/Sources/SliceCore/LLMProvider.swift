import Foundation

/// LLM 调用的抽象协议，所有供应商（OpenAI 兼容 / 未来的 Anthropic / Gemini）必须实现
public protocol LLMProvider: Sendable {
    /// 流式调用。失败时 AsyncStream 会 throw SliceError.provider
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error>
}

/// 工厂：根据 Provider 配置创建对应的 LLMProvider
public protocol LLMProviderFactory: Sendable {
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider
}
