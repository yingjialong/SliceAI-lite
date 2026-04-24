// SliceAIKit/Sources/SettingsUI/Thinking/ProviderThinkingSectionView.swift
import DesignSystem
import SliceCore
import SwiftUI

/// Provider 编辑页中的"Thinking 切换"SectionCard 子视图
///
/// 封装 thinking 相关 UI 状态（模式 Picker / 模板 Picker / JSON 文本框 / 校验逻辑），
/// 通过 `@Binding var provider: Provider` 直接回写 `provider.thinking`，
/// 不持有 ViewModel 引用——与 `ProviderEditorView` 其他字段的设计保持一致。
///
/// 抽取为独立视图的原因：ProviderEditorView 加入 thinking 块后行数超出
/// SwiftLint file_length 和 type_body_length 限制（500 / 250 行），
/// 提取后两个文件均在合理范围内。
struct ProviderThinkingSectionView: View {

    /// 指向 Configuration 中某个 Provider 的双向绑定
    @Binding var provider: Provider

    /// 当前选择的 thinking 切换模式
    @State private var thinkingMode: ThinkingMode = .none

    /// byParameter 模式下当前选中的模板
    @State private var template: ProviderThinkingTemplate = .openRouterUnified

    /// byParameter 模式下"开启 thinking"时注入 request body 的 JSON 文本
    @State private var enableJSON: String = ""

    /// byParameter 模式下"关闭 thinking"时注入 request body 的 JSON 文本（可选）
    @State private var disableJSON: String = ""

    /// enableJSON 校验错误描述；nil 表示合法
    @State private var enableJSONError: String?

    /// disableJSON 校验错误描述；nil 表示合法
    @State private var disableJSONError: String?

    var body: some View {
        SectionCard("Thinking 切换") {
            // 模式选择行
            SettingsRow("模式") {
                Picker("", selection: $thinkingMode) {
                    ForEach(ThinkingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: thinkingMode) { _, _ in
                    print("[ProviderThinkingSectionView] thinkingMode -> \(thinkingMode.rawValue)")
                    commitThinking()
                }
            }

            // byParameter 模式：模板选择 + JSON 编辑区
            if thinkingMode == .byParameter {
                byParameterContent

            } else if thinkingMode == .byModel {
                // byModel 模式：引导文字
                Text("切换 model id 模式：请在工具配置里填 thinking 模式的 model id。")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SliceSpacing.xs)
            }
        }
        .onAppear {
            // 视图出现时从已保存的 provider.thinking 反推 UI 状态
            loadThinkingFromProvider()
        }
    }

    // MARK: - byParameter 子内容

    /// byParameter 模式的 Section 内容：模板 Picker + 说明 + 两个 JSON 编辑区
    @ViewBuilder
    private var byParameterContent: some View {
        // 模板 Picker 行
        SettingsRow("模板") {
            Picker("", selection: $template) {
                ForEach(ProviderThinkingTemplate.allCases) { tpl in
                    Text(tpl.displayName).tag(tpl)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: template) { _, newTemplate in
                // 切换模板时自动填充 JSON 文本框（custom 模板不覆盖用户已输入内容）
                if newTemplate != .custom {
                    enableJSON = newTemplate.enableBodyJSON
                    disableJSON = newTemplate.disableBodyJSON ?? ""
                    // 重新校验填充后的 JSON
                    enableJSONError = validateJSON(enableJSON)
                    disableJSONError = disableJSON.isEmpty ? nil : validateJSON(disableJSON)
                }
                print("[ProviderThinkingSectionView] template -> \(newTemplate.rawValue)")
                commitThinking()
            }
        }

        // 模板说明
        Text(template.description)
            .font(SliceFont.caption)
            .foregroundColor(SliceColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, SliceSpacing.xs)

        // enableJSON 编辑区
        thinkingJSONEditor(
            label: "开启 thinking 时塞入 request body:",
            text: $enableJSON,
            errorMessage: enableJSONError
        ) { _, _ in
            enableJSONError = validateJSON(enableJSON)
            commitThinking()
        }

        // disableJSON 编辑区（可选）
        thinkingJSONEditor(
            label: "关闭 thinking 时塞入 request body（可选）:",
            text: $disableJSON,
            errorMessage: disableJSONError
        ) { _, _ in
            disableJSONError = disableJSON.isEmpty ? nil : validateJSON(disableJSON)
            commitThinking()
        }
    }

    // MARK: - JSON 编辑器辅助视图

    /// JSON 文本编辑器子视图，含标题标签、TextEditor、错误提示
    ///
    /// - Parameters:
    ///   - label: 编辑区上方的说明文字
    ///   - text: JSON 内容双向绑定
    ///   - errorMessage: 校验错误描述；nil 表示合法（边框显示正常颜色）
    ///   - onChange: text 变化时的回调（旧值 / 新值）
    @ViewBuilder
    private func thinkingJSONEditor(
        label: String,
        text: Binding<String>,
        errorMessage: String?,
        onChange: @escaping (String, String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            // 说明标签
            Text(label)
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textSecondary)

            // JSON 输入框：等宽字体 + 圆角边框（校验错误时变红）
            TextEditor(text: text)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(SliceColor.textPrimary)
                .frame(minHeight: 80, maxHeight: 80)
                .padding(SliceSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SliceRadius.control)
                        .fill(SliceColor.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: SliceRadius.control)
                                .stroke(
                                    errorMessage == nil
                                        ? SliceColor.border
                                        : SliceColor.error,
                                    lineWidth: errorMessage == nil ? 0.5 : 1.0
                                )
                        )
                )
                .onChange(of: text.wrappedValue, onChange)

            // 错误提示（仅有错误时显示，避免空行占位）
            if let err = errorMessage {
                Text(err)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.error)
            }
        }
        .padding(.vertical, SliceSpacing.xs)
    }

    // MARK: - Thinking helper 方法

    /// 校验 JSON 字符串：返回 nil 表示合法，非 nil 为错误描述
    ///
    /// 校验规则：
    ///   1. 去首尾空白后非空
    ///   2. 能被 UTF-8 编码
    ///   3. 能被 JSONSerialization 解析
    ///   4. 根节点必须是 JSON object（{...}），不接受数组或原始值
    private func validateJSON(_ jsonString: String) -> String? {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "JSON 不能为空" }
        guard let data = trimmed.data(using: .utf8) else { return "非 UTF-8 编码" }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            guard obj is [String: Any] else { return "必须是 JSON object（{...}）" }
            return nil
        } catch {
            return "JSON 解析失败：\(error.localizedDescription)"
        }
    }

    /// 将当前 UI 状态写回 provider.thinking（通过 @Binding 直接传播到 viewModel.configuration）
    ///
    /// 校验失败时提前返回，不覆盖上次合法值。
    /// 与 ProviderEditorView 其他字段一致：直接写 @Binding，
    /// 不在视图层显式调用 save()；持久化由宿主 ProvidersSettingsPage 负责。
    private func commitThinking() {
        let newCapability: ProviderThinkingCapability?
        switch thinkingMode {
        case .none:
            // 不支持 thinking：清空 provider.thinking
            newCapability = nil
        case .byModel:
            // 切换 model id 模式：仅声明机制，具体 thinkingModelId 在 Tool 层配置
            newCapability = .byModel
        case .byParameter:
            // 参数透传：两个 JSON 均合法才写回
            if enableJSONError != nil {
                print("[ProviderThinkingSectionView] commitThinking: enableJSON invalid, skip")
                return
            }
            if !disableJSON.isEmpty && disableJSONError != nil {
                print("[ProviderThinkingSectionView] commitThinking: disableJSON invalid, skip")
                return
            }
            newCapability = .byParameter(
                enableBodyJSON: enableJSON,
                disableBodyJSON: disableJSON.isEmpty ? nil : disableJSON
            )
        }
        provider.thinking = newCapability
        print("[ProviderThinkingSectionView] commitThinking: \(String(describing: newCapability)) for '\(provider.id)'")
    }

    /// 视图出现时从 provider.thinking 反推 UI 状态
    ///
    /// 在 .onAppear 里调用，用于打开已有 Provider 的编辑区时恢复之前保存的配置。
    private func loadThinkingFromProvider() {
        switch provider.thinking {
        case .none:
            thinkingMode = .none
        case .byModel:
            thinkingMode = .byModel
        case .byParameter(let en, let dis):
            thinkingMode = .byParameter
            enableJSON = en
            disableJSON = dis ?? ""
            // 反推匹配的模板（无匹配时显示 .custom）
            template = ProviderThinkingTemplate.match(enableJSON: en, disableJSON: dis)
            // 初始化时校验已存在的 JSON
            enableJSONError = validateJSON(enableJSON)
            disableJSONError = disableJSON.isEmpty ? nil : validateJSON(disableJSON)
        }
        print("[ProviderThinkingSectionView] loadThinkingFromProvider:",
              "mode=\(thinkingMode.rawValue) provider='\(provider.id)'")
    }
}

// MARK: - ThinkingMode 枚举

/// Thinking 切换模式（SettingsUI 层枚举，与 ProviderThinkingCapability 对应）
private enum ThinkingMode: String, CaseIterable, Identifiable {
    case none
    case byModel
    case byParameter

    /// 遵守 Identifiable
    var id: String { rawValue }

    /// 用户可见的中文标签
    var label: String {
        switch self {
        case .none:        return "不支持"
        case .byModel:     return "切换 model id"
        case .byParameter: return "参数透传"
        }
    }
}
