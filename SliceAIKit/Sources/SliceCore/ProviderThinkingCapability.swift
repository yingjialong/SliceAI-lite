import Foundation

/// Provider 声明的 thinking 切换机制
///
/// 设计要点：
///   - 两种机制并存以覆盖现存与未来所有混合模型
///   - byParameter 用 raw JSON 字符串存储而不是 typed struct，避开 Swift Codable
///     的 AnyCodable 复杂度；用户在 SettingsUI 直接面对 JSON 文本框
///   - disableBodyJSON 设计为 Optional：Anthropic adaptive / budget 的"关闭"=
///     省略 thinking 字段，OpenRouter / DeepSeek V4 的"关闭"= 显式传值
public enum ProviderThinkingCapability: Sendable, Codable, Equatable {
    /// 通过切换 model id 开关（典型：DeepSeek V3、字节 doubao 双 model）
    /// Tool 必须配置 thinkingModelId 才能真正切换
    case byModel

    /// 通过 request body root 透传 JSON 字段开关
    /// - enableBodyJSON: thinking=on 时 merge 到 request body root 的 JSON 字符串
    /// - disableBodyJSON: thinking=off 时 merge（nil 表示不传，等同省略字段）
    case byParameter(enableBodyJSON: String, disableBodyJSON: String?)
}
