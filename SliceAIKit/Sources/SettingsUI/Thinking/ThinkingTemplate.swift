// SliceAIKit/Sources/SettingsUI/Thinking/ThinkingTemplate.swift
import Foundation
import SliceCore

/// Provider 配置 UI 提供的 byParameter 模板库
///
/// 模板**不进 schema**，是 SettingsUI 内部的常量。用户在 ProviderEditorView
/// 选模板 → UI 自动填两个 textarea → 用户可微调 → 保存为
/// `ProviderThinkingCapability.byParameter(enableJSON, disableJSON)`。
///
/// 各 payload 来自 2026-04-24 web 调研的官方文档；模板内 effort/budget 写死合理
/// 默认值（medium / 8000），需要别的取值用户改 raw JSON 即可。
public enum ProviderThinkingTemplate: String, CaseIterable, Identifiable {
    case openRouterUnified
    case deepSeekV4
    case anthropicAdaptive
    case anthropicBudget
    case openAIReasoningEffort
    case qwen3
    case custom

    /// 遵守 Identifiable，以 rawValue 作为稳定 ID
    public var id: String { rawValue }

    /// 显示给用户的名称（中文，与设置界面一致风格）
    public var displayName: String {
        switch self {
        case .openRouterUnified:
            return "OpenRouter 统一接口（推荐）"
        case .deepSeekV4:
            return "DeepSeek V4"
        case .anthropicAdaptive:
            return "Anthropic 4.6+（adaptive）"
        case .anthropicBudget:
            return "Anthropic 4.5 及以下（budget_tokens）"
        case .openAIReasoningEffort:
            return "OpenAI / GPT-5（reasoning_effort）"
        case .qwen3:
            return "阿里 Qwen3（enable_thinking）"
        case .custom:
            return "自定义"
        }
    }

    /// 给用户的简短说明（出现在选项下方提示）
    public var description: String {
        switch self {
        case .openRouterUnified:
            return "OpenRouter 把 OpenAI / Anthropic / DeepSeek / Grok 全部 reasoning 模型"
                + " 统一为 reasoning.effort 参数。一个模板覆盖所有 vendor。"
        case .deepSeekV4:
            return "适用 deepseek-v4-pro / deepseek-v4-flash 直连。"
        case .anthropicAdaptive:
            return "Claude Sonnet 4.6 / Opus 4.6 起的 adaptive thinking，让模型自决思考量。"
        case .anthropicBudget:
            return "Claude Sonnet 3.7 / 4.5 等支持固定 budget_tokens 的 extended thinking。"
        case .openAIReasoningEffort:
            return "OpenAI o-series（o3/o4-mini）和 GPT-5 系列的 reasoning_effort 参数。"
        case .qwen3:
            return "阿里 Qwen3（含 235B / 32B 等）的 enable_thinking 开关。"
        case .custom:
            return "手动填写 enable / disable 的 JSON。"
        }
    }

    /// 模板预设的 enableBodyJSON
    ///
    /// 填入 `ProviderThinkingCapability.byParameter` 的第一个参数；
    /// 执行时会被 merge 进请求 body。
    public var enableBodyJSON: String {
        switch self {
        case .openRouterUnified:
            return #"{"reasoning":{"effort":"medium"}}"#
        case .deepSeekV4:
            return #"{"thinking":{"type":"enabled"}}"#
        case .anthropicAdaptive:
            return #"{"thinking":{"type":"adaptive"}}"#
        case .anthropicBudget:
            return #"{"thinking":{"type":"enabled","budget_tokens":8000}}"#
        case .openAIReasoningEffort:
            return #"{"reasoning_effort":"medium"}"#
        case .qwen3:
            return #"{"enable_thinking":true}"#
        case .custom:
            return ""
        }
    }

    /// 模板预设的 disableBodyJSON；nil 表示"省略字段"（即不向请求 body 注入任何内容）
    ///
    /// Anthropic 的 thinking 关闭语义是"不携带 thinking 字段"，
    /// 故 anthropicAdaptive / anthropicBudget 返回 nil。
    public var disableBodyJSON: String? {
        switch self {
        case .openRouterUnified:
            return #"{"reasoning":{"effort":"none"}}"#
        case .deepSeekV4:
            return #"{"thinking":{"type":"disabled"}}"#
        case .anthropicAdaptive:
            return nil  // Anthropic 关闭 = 省略 thinking 字段
        case .anthropicBudget:
            return nil
        case .openAIReasoningEffort:
            return #"{"reasoning_effort":"minimal"}"#
        case .qwen3:
            return #"{"enable_thinking":false}"#
        case .custom:
            return nil
        }
    }

    /// 试图从一个已存在的 (enableJSON, disableJSON) 推断对应模板，用于编辑现有 Provider
    /// 时 UI 显示当前模板。无匹配返回 .custom。
    ///
    /// - Parameters:
    ///   - enableJSON: 已保存的 enableBodyJSON 字符串
    ///   - disableJSON: 已保存的 disableBodyJSON 字符串（可为 nil）
    /// - Returns: 匹配的模板 case；无匹配时返回 `.custom`
    public static func match(enableJSON: String, disableJSON: String?) -> ProviderThinkingTemplate {
        for template in allCases where template != .custom {
            if template.enableBodyJSON == enableJSON && template.disableBodyJSON == disableJSON {
                return template
            }
        }
        return .custom
    }
}
