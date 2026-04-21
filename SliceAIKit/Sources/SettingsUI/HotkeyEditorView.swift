// SliceAIKit/Sources/SettingsUI/HotkeyEditorView.swift
import SliceCore
import SwiftUI

/// 命令面板快捷键编辑视图
///
/// 仅做"非空"弱校验，真正的冲突/合法性检查由 `HotkeyRegistrar`（运行时）
/// 承担。这里不强依赖 HotkeyManager 模块，避免把 Carbon 解析逻辑下沉到设置 UI。
///
/// `onCommit` 回调在用户按回车（TextField.onSubmit）且校验通过后触发，
/// 调用方可在此立即持久化热键配置。
public struct HotkeyEditorView: View {

    /// 指向 Configuration.hotkeys.toggleCommandPalette 的双向绑定
    @Binding public var binding: String

    /// 本地的校验错误描述；nil 表示暂未出错
    @State private var error: String?

    /// 校验通过后的外部回调（可选），用于让调用方立即持久化
    private let onCommit: (() -> Void)?

    /// 构造快捷键编辑视图
    /// - Parameters:
    ///   - binding: 指向 Configuration 中命令面板快捷键字符串的绑定
    ///   - onCommit: 校验通过后的回调（可选）；调用方可在此触发 saveHotkeys()
    public init(binding: Binding<String>, onCommit: (() -> Void)? = nil) {
        self._binding = binding
        self.onCommit = onCommit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Command Palette")
                    .frame(width: 140, alignment: .leading)
                TextField("option+space", text: $binding)
                    .onSubmit { validateAndCommit() }
            }
            if let error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            Text("支持: cmd / option / shift / ctrl / space / a–z / 0–9 / f1–f12 / 方向键 / return / esc")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// 轻量校验：仅拒绝空串；校验通过后触发 onCommit 回调
    ///
    /// 真正的 parse 由 HotkeyRegistrar 在注册时负责。
    private func validateAndCommit() {
        if binding.isEmpty {
            error = "不能为空"
            // 校验失败，不触发 onCommit
            return
        }
        error = nil
        // 校验通过，通知调用方（如持久化热键配置）
        onCommit?()
    }
}
