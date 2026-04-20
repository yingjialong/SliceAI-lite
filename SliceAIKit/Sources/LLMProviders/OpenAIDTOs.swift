import Foundation

/// OpenAI chat completion stream chunk 的解码结构
/// 说明：
///   - 仅解码当前 MVP 需要的字段（choices[*].delta.content 与 choices[*].finish_reason）
///   - 顶层的 id/object/created/model 等字段对流式增量消费无用，故不声明
///   - finish_reason 为 null 时解码为 nil，表示该 chunk 还不是最后一段
///   - delta 为空对象 {} 时，content 解码为 nil
struct OpenAIStreamChunk: Decodable {
    /// 一次 chunk 通常只含一个 choice（n=1），但协议允许多个，这里按数组建模以保持一致
    let choices: [Choice]

    /// 单个候选答案在当前 chunk 中的增量信息
    struct Choice: Decodable {
        /// 本次 chunk 带来的文本/工具增量
        let delta: Delta
        /// 非空字符串（如 "stop"/"length"）表示本候选流已结束；nil 表示仍在流中
        let finishReason: String?

        /// 将 snake_case 的 finish_reason 映射为 Swift 端的 camelCase
        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    /// chunk 中的增量字段；MVP 仅关注文本 content
    struct Delta: Decodable {
        /// 新增文本片段；首帧通常只带 role 而无 content，因此允许 nil
        let content: String?
    }
}
