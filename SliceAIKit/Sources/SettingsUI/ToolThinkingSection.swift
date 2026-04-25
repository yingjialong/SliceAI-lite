// SliceAIKit/Sources/SettingsUI/ToolThinkingSection.swift
import DesignSystem
import SliceCore
import SwiftUI

/// Tool 编辑表单中"Thinking 模式"行的子视图
///
/// 抽出原因：ToolEditorView 主 struct 加入 thinking 三态分支后行数超出
/// SwiftLint type_body_length 警告阈值 250 行。提取为独立 view 后两个
/// 文件均在合理范围内（与 ProviderThinkingSectionView 同样处理思路）。
///
/// 视图职责：根据 `currentProvider?.thinking` 三态分别渲染：
///   - `.byModel`：thinkingModelId 输入框（必填）
///   - `.byParameter`：只读"已配置参数透传"提示
///   - `.none` 且 Provider 存在：灰色"未启用 thinking 切换"提示，避免字段静默消失
///   - `.none` 且 Provider 不存在：EmptyView，由上层 Provider Picker 区域兜底
///
/// 用 @ViewBuilder + switch-on-enum 而非连续 if/else，保证三态都显式渲染，
/// 未来扩展 ProviderThinkingCapability case 时编译器会提示遗漏分支。
struct ToolThinkingSection: View {

    /// 指向 Configuration 中某个 Tool 的双向绑定
    @Binding var tool: Tool

    /// Tool 当前关联的 Provider；用于决定渲染哪种 thinking 提示
    let currentProvider: Provider?

    @ViewBuilder
    var body: some View {
        switch currentProvider?.thinking {
        case .byModel:
            // 切 model id 模式：thinkingModelId 必填；空字符串映射为 nil 避免存无意义空串
            SettingsRow("Thinking model id") {
                TextField(
                    "如 deepseek-reasoner",
                    text: Binding(
                        get: { tool.thinkingModelId ?? "" },
                        set: { newValue in
                            tool.thinkingModelId = newValue.isEmpty ? nil : newValue
                        }
                    )
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundColor(SliceColor.textPrimary)
                .font(SliceFont.body)
            }
        case .byParameter:
            // 参数透传：thinking 已在 Provider 层配置，工具层无需额外字段
            SettingsRow("Thinking 模式") {
                Text("该 Provider 已配置参数透传，无需在工具层配置")
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .none where currentProvider != nil:
            // Provider 存在但 thinking == nil：显式提示，避免用户找不到字段而困惑
            SettingsRow("Thinking 模式") {
                Text("此 Provider 未启用 thinking 切换")
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .none:
            // currentProvider 为 nil（providerId 不在列表）：EmptyView，由 Provider Picker 兜底
            EmptyView()
        }
    }
}
