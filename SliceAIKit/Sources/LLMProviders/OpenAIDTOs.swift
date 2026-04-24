import Foundation

/// OpenAI chat completion stream chunk 的顶层解码结构
/// 说明：
///   - 仅解码当前 MVP 需要的字段（choices[*].delta.content 与 choices[*].finish_reason）
///   - 顶层的 id/object/created/model 等字段对流式增量消费无用，故不声明
///   - Choice / Delta 以 file-scope 类型呈现，避免 SwiftLint nesting rule 触发；
///     两者仅在 LLMProviders 内部使用，不会污染模块的对外 API
struct OpenAIStreamChunk: Decodable {
    /// 一次 chunk 通常只含一个 choice（n=1），但协议允许多个，这里按数组建模以保持一致
    let choices: [OpenAIStreamChoice]
}

/// 单个候选答案在当前 chunk 中的增量信息
struct OpenAIStreamChoice: Decodable {
    /// 本次 chunk 带来的文本/工具增量
    let delta: OpenAIStreamDelta
    /// 非空字符串（如 "stop"/"length"）表示本候选流已结束；nil 表示仍在流中
    let finishReason: String?

    /// 将 snake_case 的 finish_reason 映射为 Swift 端的 camelCase
    private enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

/// chunk 中的增量字段；关注文本 content 与 thinking 模式下的 reasoning 字段
struct OpenAIStreamDelta: Decodable {
    /// 新增文本片段；首帧通常只带 role 而无 content；finish 帧 delta 为 {}，故允许 nil
    let content: String?
    /// OpenRouter 统一 reasoning 字段：所有 vendor 的 thinking 增量统一映射到 delta.reasoning
    let reasoning: String?
    /// DeepSeek V4 风格 reasoning 字段：DeepSeek 直连 API 在 delta.reasoning_content 里返回 thinking 文本
    let reasoningContent: String?

    /// 将 snake_case 的 reasoning_content 映射为 Swift 端的 camelCase
    private enum CodingKeys: String, CodingKey {
        case content
        case reasoning
        case reasoningContent = "reasoning_content"
    }
}
