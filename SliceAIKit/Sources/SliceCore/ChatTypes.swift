import Foundation

/// 角色，对应 OpenAI Chat Completions 的 role 字段
public enum Role: String, Sendable, Codable {
    case system, user, assistant
}

/// 单条消息
public struct ChatMessage: Sendable, Codable, Equatable {
    public let role: Role
    public let content: String

    /// 构造聊天消息
    /// - Parameters:
    ///   - role: 消息角色（system/user/assistant）
    ///   - content: 消息文本内容
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// 聊天请求
/// nil 的 temperature / maxTokens 会被序列化省略，保持服务端默认
///
/// `extraBody` 是非 Codable 的运行时字段，由 Provider.byParameter 的 enable/
/// disableBodyJSON parse 而来。OpenAICompatibleProvider 在序列化 body 时手动
/// merge 进 root JSON。该字段不通过 Codable 序列化，避免 AnyCodable 痛点。
///
/// 标记为 `@unchecked Sendable` 因为 `[String: Any]` 不是天然 Sendable，
/// 但运行时只在 actor (ToolExecutor) 内构造、value-type 传递不会跨 actor 共享可变状态。
/// 只需 Encodable（向服务端发送）；不需要 Decodable（不从 JSON 反序列化 ChatRequest）。
public struct ChatRequest: @unchecked Sendable, Encodable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?
    /// 额外要 merge 到 request body root 的字段；nil 时不 merge
    /// 此字段不参与 Codable 序列化，由 OpenAICompatibleProvider 在发送前手动处理
    public let extraBody: [String: Any]?

    /// 构造聊天请求
    /// - Parameters:
    ///   - model: 模型标识
    ///   - messages: 历史消息数组
    ///   - temperature: 采样温度，nil 时沿用服务端默认
    ///   - maxTokens: 生成最大 token 数，nil 时沿用服务端默认
    ///   - extraBody: 额外要 merge 到 request body root 的字段；nil 时不 merge
    public init(model: String, messages: [ChatMessage],
                temperature: Double? = nil, maxTokens: Int? = nil,
                extraBody: [String: Any]? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.extraBody = extraBody
    }

    /// CodingKeys 不含 extraBody，意味着 JSONEncoder 不会编码它。
    /// extraBody 只在 OpenAICompatibleProvider 内部访问，merge 进 body 时手动处理。
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// ChatRequest Equatable：extraBody 用 NSDictionary 桥接比较
extension ChatRequest: Equatable {
    /// 比较两个 ChatRequest 是否相等
    /// extraBody 通过 NSDictionary 桥接实现深度比较，因为 [String: Any] 不支持 == 运算符
    public static func == (lhs: ChatRequest, rhs: ChatRequest) -> Bool {
        lhs.model == rhs.model
            && lhs.messages == rhs.messages
            && lhs.temperature == rhs.temperature
            && lhs.maxTokens == rhs.maxTokens
            && (lhs.extraBody as NSDictionary?) == (rhs.extraBody as NSDictionary?)
    }
}

/// 完成原因
public enum FinishReason: String, Sendable, Codable {
    case stop, length, contentFilter = "content_filter", toolCalls = "tool_calls"
}

/// 流式 chunk（delta 为增量文本，finishReason 仅在最后一个 chunk 非 nil）
/// 不声明 Codable：仅由 SSE 解码器生产，不会作为整体通过网络发送
public struct ChatChunk: Sendable, Equatable {
    public let delta: String
    /// 主推理过程的增量文本（OpenRouter `delta.reasoning` /
    /// DeepSeek `delta.reasoning_content` 等的 fallback 提取）
    /// 为 nil 表示该 chunk 没有 reasoning 内容（兼容非 thinking 模型）
    public let reasoningDelta: String?
    public let finishReason: FinishReason?

    /// 构造流式响应块
    /// - Parameters:
    ///   - delta: 本次主内容增量文本
    ///   - reasoningDelta: 本次推理过程增量文本，无则传 nil
    ///   - finishReason: 仅最后一个 chunk 非 nil
    public init(delta: String, reasoningDelta: String? = nil,
                finishReason: FinishReason? = nil) {
        self.delta = delta
        self.reasoningDelta = reasoningDelta
        self.finishReason = finishReason
    }
}
