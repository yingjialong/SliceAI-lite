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

    /// "添加变量"对话框是否展示
    @State private var showAddVariableAlert = false

    /// 对话框里待输入的变量名
    @State private var newVariableKey = ""

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

            // 自定义变量分组（始终显示——空态也要提供"添加变量"入口）
            variablesCard
        }
        // 添加变量对话框
        .alert("添加变量", isPresented: $showAddVariableAlert) {
            TextField("变量名（如 language）", text: $newVariableKey)
            Button("添加") { addVariable() }
            Button("取消", role: .cancel) { newVariableKey = "" }
        } message: {
            Text("变量名将作为提示词模板占位符，例如填写 language 后可在 prompt 里用 {{language}} 引用。")
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

            // 浮条显示样式：三选一 segmented
            // 名称模式下会按"≤4 个中文字或 1 个英文单词"自动截断，
            // 避免长名称把浮条撑得过宽；详细截断规则见 FloatingToolbarPanel.shortenLabel
            SettingsRow("浮条显示") {
                Picker("", selection: $tool.labelStyle) {
                    ForEach(ToolLabelStyle.allCases, id: \.self) { style in
                        Text(style.displayLabel).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }
        }
    }

    // MARK: - 提示词卡片

    /// 提示词分组：System / User Prompt
    ///
    /// 这里用 `TextEditor` 代替 `TextField(axis: .vertical)`——后者虽然支持多行显示，
    /// 但 macOS 下按 Return 会触发提交（commit）而非换行，无法输入多段 prompt。
    /// TextEditor 底层是 NSTextView，Return 原生换行，符合写 prompt 的预期。
    private var promptCard: some View {
        SectionCard("提示词") {
            PromptTextEditor(
                label: "System Prompt",
                placeholder: "可选 System Prompt…",
                required: false,
                text: Binding(
                    get: { tool.systemPrompt ?? "" },
                    set: { tool.systemPrompt = $0.isEmpty ? nil : $0 }
                ),
                minHeight: 72
            )
            .padding(.vertical, SliceSpacing.base)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SliceColor.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, -SliceSpacing.xl)
            }

            PromptTextEditor(
                label: "User Prompt",
                placeholder: "输入 User Prompt，可用 {{selection}} 等变量…",
                required: true,
                text: $tool.userPrompt,
                minHeight: 120
            )
            .padding(.vertical, SliceSpacing.base)

            // 变量提示
            Text("可用变量：{{selection}}  {{app}}  {{url}}  {{language}}")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, SliceSpacing.xs)
        }
    }

    // MARK: - Provider 卡片

    /// 当前 Tool 关联的 Provider；用于判断是否显示 thinkingModelId 字段
    ///
    /// 在 providers 列表中按 tool.providerId 查找，找不到返回 nil。
    private var currentProvider: Provider? {
        providers.first { $0.id == tool.providerId }
    }

    /// Provider 分组：关联 Provider / 模型覆写 / Thinking model id（仅 byModel）/ 采样温度
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

            // Thinking 模式：根据 Provider.thinking 三态分别渲染
            //
            // 用 @ViewBuilder + switch-on-enum 而不是连续 if/else if，原因：
            //   1. 显式覆盖三个 case（含 .none）保证 UI 永远给用户反馈，不会"字段消失"
            //   2. 避免 enum-with-associated-values 的 == 比较易错（byModel 无关联值时 OK，
            //      但与 byParameter 混用 == 与 case 模式风格不一致，未来扩展易踩坑）
            thinkingSection

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

    /// Thinking 模式相关字段；由 currentProvider?.thinking 三态驱动
    ///
    /// 三态都显式渲染：
    ///   - .byModel：thinkingModelId 输入框（必填项）
    ///   - .byParameter：只读说明，告诉用户已在 Provider 层配置
    ///   - .none + Provider 存在：灰色提示"未启用 thinking 切换"，避免字段静默消失让用户困惑
    ///   - .none + Provider nil（providerId 不在列表）：EmptyView，由 Provider Picker 区域兜底
    @ViewBuilder
    private var thinkingSection: some View {
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

    // MARK: - 自定义变量卡片

    /// 自定义变量分组：始终显示；提供 key-value 列表 + 添加/删除入口
    ///
    /// 空态下显示"暂无变量"提示 + 底部"添加变量"按钮；非空时每行 key + value
    /// TextField + 右侧删除按钮。添加新变量通过 alert 询问 key 名，value 初始为空、
    /// 用户后续在列表里填。
    private var variablesCard: some View {
        SectionCard("自定义变量") {
            // 说明文字
            HStack {
                Text("变量会注入到提示词里的 {{变量名}} 占位符。")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, SliceSpacing.xs)

            if tool.variables.isEmpty {
                // 空态
                HStack {
                    Text("暂无自定义变量")
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textTertiary)
                    Spacer()
                }
                .padding(.vertical, SliceSpacing.sm)
            } else {
                // 变量行列表：key 标签 + value TextField + 删除按钮
                ForEach(Array(tool.variables.keys.sorted()), id: \.self) { key in
                    variableRow(key: key)
                }
            }

            // 底部"添加变量"按钮
            HStack {
                Spacer()
                PillButton("添加变量", icon: "plus", style: .secondary) {
                    newVariableKey = ""
                    showAddVariableAlert = true
                }
            }
            .padding(.top, SliceSpacing.xs)
        }
    }

    /// 单行自定义变量编辑：key 标签 + value TextField + 删除按钮
    /// - Parameter key: 变量名
    private func variableRow(key: String) -> some View {
        HStack(spacing: SliceSpacing.sm) {
            // key 标签占固定宽度，便于多行对齐
            Text(key)
                .font(SliceFont.subheadline)
                .foregroundColor(SliceColor.textPrimary)
                .frame(minWidth: 90, alignment: .leading)
                .lineLimit(1)

            // value 输入框
            TextField(
                "变量值",
                text: Binding(
                    get: { tool.variables[key] ?? "" },
                    set: { tool.variables[key] = $0 }
                )
            )
            .textFieldStyle(.plain)
            .foregroundColor(SliceColor.textPrimary)
            .font(SliceFont.body)

            // 删除按钮
            Button {
                tool.variables.removeValue(forKey: key)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SliceColor.error)
            }
            .buttonStyle(.plain)
            .help("删除此变量")
        }
        .padding(.vertical, SliceSpacing.xs)
    }

    // MARK: - 辅助

    /// alert 里"添加"按钮的回调：校验 key 并写入 variables
    ///
    /// 约束：
    ///   - 去首尾空白后非空
    ///   - 不与已有 key 重复（重复时直接忽略这次添加，保留已有值）
    /// 若校验未通过也重置 newVariableKey，避免下次弹框残留脏值。
    private func addVariable() {
        defer { newVariableKey = "" }
        let trimmed = newVariableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, tool.variables[trimmed] == nil else { return }
        tool.variables[trimmed] = ""
    }
}

// MARK: - PromptTextEditor

/// 带 placeholder 和圆角边框的多行 prompt 编辑器
///
/// macOS 下原生 `TextField(axis: .vertical)` 按 Return 会提交而非换行，写 prompt
/// 体验差；改用 `TextEditor`（底层 NSTextView）即可。TextEditor 没有原生 placeholder
/// 所以这里用 ZStack overlay 一层灰字模拟，text 为空时显示。
private struct PromptTextEditor: View {

    /// 标题（显示在编辑器上方）
    let label: String

    /// placeholder 文本
    let placeholder: String

    /// 是否显示"必填"红字标记
    let required: Bool

    /// 内容双向绑定
    @Binding var text: String

    /// 编辑器最小高度
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            HStack {
                Text(label)
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textPrimary)
                Spacer()
                if required {
                    Text("必填")
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.error)
                }
            }

            ZStack(alignment: .topLeading) {
                // 占位提示：仅 text 为空时显示；禁用 hit-test 不挡编辑器
                if text.isEmpty {
                    Text(placeholder)
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textTertiary)
                        .padding(.horizontal, SliceSpacing.sm + 4)
                        .padding(.vertical, SliceSpacing.sm + 4)
                        .allowsHitTesting(false)
                }
                // 实际编辑器：隐藏默认背景，由外层圆角边框负责视觉
                TextEditor(text: $text)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textPrimary)
                    .frame(minHeight: minHeight)
                    .padding(SliceSpacing.sm)
            }
            .background(
                RoundedRectangle(cornerRadius: SliceRadius.control)
                    .fill(SliceColor.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: SliceRadius.control)
                            .stroke(SliceColor.border, lineWidth: 0.5)
                    )
            )
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

// MARK: - ToolLabelStyle + displayLabel

/// 为 ToolLabelStyle 补充本地化展示标签（文件内 extension，避免污染 SliceCore）
private extension ToolLabelStyle {
    /// 用于 Picker 展示的中文标签
    var displayLabel: String {
        switch self {
        case .icon:        return "图标"
        case .name:        return "名称"
        case .iconAndName: return "图标+名称"
        }
    }
}
