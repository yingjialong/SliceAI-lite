// SliceAIKit/Sources/SettingsUI/ToolEditorView.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 单个 Tool 的编辑表单
///
/// 输入通过 `@Binding` 直接指向 `Configuration.tools[i]`，修改即时反映到 VM。
/// Provider 列表只读展示，用于 Picker 选择关联的供应商。
///
/// 样式采用 DesignSystem：SectionCard 分组 + SettingsRow 行布局，
/// 不使用 Form/Section（FormStyle.grouped 在内联展开场景有额外内边距不适用）。
public struct ToolEditorView: View {

    /// 正在编辑的 Tool 的双向绑定
    @Binding public var tool: Tool

    /// 可选的 Provider 列表，作为 Picker 数据源
    public let providers: [Provider]

    /// 构造 Tool 编辑视图
    /// - Parameters:
    ///   - tool: 指向 Configuration 中某个 Tool 的绑定
    ///   - providers: 供 Picker 显示的 Provider 列表
    public init(tool: Binding<Tool>, providers: [Provider]) {
        self._tool = tool
        self.providers = providers
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.lg) {
            // 基础信息分组：名称 / 图标 / 描述
            basicsCard

            // 提示词分组：System / User
            promptCard

            // Provider 分组：关联 Provider / 模型覆写 / 采样温度
            providerCard

            // 自定义变量分组（有变量时才显示）
            if !tool.variables.isEmpty {
                variablesCard
            }
        }
    }

    // MARK: - 基础信息卡片

    /// 基础信息分组：名称 / 图标 / 描述
    private var basicsCard: some View {
        SectionCard("基础信息") {
            SettingsRow("名称") {
                TextField("工具名称", text: $tool.name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
            }

            SettingsRow("图标") {
                TextField("SF Symbol 或 emoji", text: $tool.icon)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
            }

            SettingsRow("描述") {
                TextField(
                    "可选描述",
                    text: Binding(
                        get: { tool.description ?? "" },
                        set: { tool.description = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundColor(SliceColor.textPrimary)
                .font(SliceFont.body)
            }
        }
    }

    // MARK: - 提示词卡片

    /// 提示词分组：System / User Prompt
    private var promptCard: some View {
        SectionCard("提示词") {
            // System Prompt：多行输入
            VStack(alignment: .leading, spacing: SliceSpacing.xs) {
                Text("System Prompt")
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textPrimary)

                TextField(
                    "可选 System Prompt…",
                    text: Binding(
                        get: { tool.systemPrompt ?? "" },
                        set: { tool.systemPrompt = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .foregroundColor(SliceColor.textPrimary)
                .font(SliceFont.body)
                .padding(SliceSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SliceRadius.control)
                        .fill(SliceColor.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: SliceRadius.control)
                                .stroke(SliceColor.border, lineWidth: 0.5)
                        )
                )
            }
            .padding(.vertical, SliceSpacing.base)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SliceColor.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, -SliceSpacing.xl)
            }

            // User Prompt：多行输入，必填
            VStack(alignment: .leading, spacing: SliceSpacing.xs) {
                HStack {
                    Text("User Prompt")
                        .font(SliceFont.subheadline)
                        .foregroundColor(SliceColor.textPrimary)
                    Spacer()
                    // 必填标记
                    Text("必填")
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.error)
                }

                TextField("输入 User Prompt，可用 {{selection}} 等变量…",
                          text: $tool.userPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...8)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
                    .padding(SliceSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: SliceRadius.control)
                            .fill(SliceColor.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: SliceRadius.control)
                                    .stroke(SliceColor.border, lineWidth: 0.5)
                            )
                    )

                // 变量提示
                Text("可用变量：{{selection}}  {{app}}  {{url}}  {{language}}")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
            }
            .padding(.vertical, SliceSpacing.base)
        }
    }

    // MARK: - Provider 卡片

    /// Provider 分组：关联 Provider / 模型覆写 / 采样温度
    private var providerCard: some View {
        SectionCard("Provider") {
            // Provider Picker
            SettingsRow("Provider") {
                if providers.isEmpty {
                    Text("请先添加 Provider")
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textTertiary)
                } else {
                    Picker("", selection: $tool.providerId) {
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            // 模型覆写（可选）
            SettingsRow("模型覆写") {
                TextField(
                    "留空使用 Provider 默认模型",
                    text: Binding(
                        get: { tool.modelId ?? "" },
                        set: { tool.modelId = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundColor(SliceColor.textPrimary)
                .font(SliceFont.body)
            }

            // 采样温度 Slider
            SettingsRow("Temperature") {
                HStack(spacing: SliceSpacing.sm) {
                    Slider(
                        value: Binding(
                            get: { tool.temperature ?? 0.3 },
                            set: { tool.temperature = $0 }
                        ),
                        in: 0...2
                    )
                    .frame(width: 120)

                    Text(String(format: "%.2f", tool.temperature ?? 0.3))
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            // 展示模式 Picker
            SettingsRow("展示模式") {
                Picker("", selection: $tool.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    // MARK: - 自定义变量卡片

    /// 自定义变量键值对（有值时才渲染，避免空 Section）
    private var variablesCard: some View {
        SectionCard("自定义变量") {
            ForEach(Array(tool.variables.keys.sorted()), id: \.self) { key in
                SettingsRow(key) {
                    TextField(
                        key,
                        text: Binding(
                            get: { tool.variables[key] ?? "" },
                            set: { tool.variables[key] = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
                }
            }
        }
    }
}

// MARK: - DisplayMode + displayLabel

/// 为 DisplayMode 补充本地化展示标签（文件内 extension，避免污染 SliceCore）
private extension DisplayMode {
    /// 用于 Picker 展示的中文标签
    var displayLabel: String {
        switch self {
        case .window:  return "浮窗"
        case .bubble:  return "气泡（v0.2）"
        case .replace: return "替换（v0.2）"
        }
    }
}
