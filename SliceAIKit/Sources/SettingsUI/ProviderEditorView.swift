// SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 单个 Provider 的编辑表单，含 API Key 的 Keychain 读写入口与连接测试
///
/// API Key 不存 Configuration，而是通过注入的 `onSaveKey` / `onLoadKey` 回调
/// 间接访问 Keychain；连接测试通过 `onTestKey` 回调（通常由 ViewModel 转发到
/// LLMProviders）。这样本视图无需感知具体存储 / 网络实现，便于预览与单元测试。
///
/// 样式采用 DesignSystem：SectionCard 分组 + SettingsRow 行布局 + PillButton 操作按钮，
/// 不使用 Form/Section（FormStyle.grouped 在内联展开场景有额外内边距不适用）。
public struct ProviderEditorView: View {

    /// 指向 Configuration 中某个 Provider 的双向绑定
    @Binding public var provider: Provider

    /// 当前编辑态的 API Key 明文（只在内存中，不写回 Configuration）
    @State private var apiKey: String = ""

    /// 已从 Keychain 预读的 API Key；Test connection 在 `apiKey` 为空时回退使用
    /// （遵循"typed first, saved fallback"约定，让用户改完 key 不必先 Save 也能 Test）
    @State private var savedKey: String = ""

    /// Base URL 的字符串中间态，用于 TextField 编辑
    /// 只有成功解析为 URL 时才回写 provider.baseURL，避免存入无效值
    @State private var baseURLText: String = ""

    /// Save key 后的状态消息：成功绿/灰、失败红；成功 2 秒自动消失
    @State private var saveMessage: ProviderStatusMessage?

    /// Test connection 后的状态消息：成功绿/灰、失败红；成功 2 秒自动消失
    @State private var testMessage: ProviderStatusMessage?

    /// Test 是否进行中；为 true 时禁用按钮 + 显示"测试中…"
    @State private var isTesting: Bool = false

    /// 保存 API Key 的异步回调；throws 让错误能在 UI 层呈现"保存失败：xxx"
    private let onSaveKey: @Sendable (String) async throws -> Void

    /// 读取 API Key 的异步回调；返回 nil 表示不存在
    private let onLoadKey: @Sendable () async -> String?

    /// 测试连接的异步回调；签名 (key, baseURL, model)
    private let onTestKey: @Sendable (String, URL, String) async throws -> Void

    /// 构造 Provider 编辑视图
    /// - Parameters:
    ///   - provider: 指向 Configuration 中某个 Provider 的绑定
    ///   - onSaveKey: 保存 API Key 的异步回调；抛错会被 UI 转成"保存失败"提示
    ///   - onLoadKey: 读取 API Key 的异步回调；返回 nil 表示槽位为空
    ///   - onTestKey: 测试连接的异步回调；抛错会被 UI 转成"测试失败"提示
    public init(
        provider: Binding<Provider>,
        onSaveKey: @escaping @Sendable (String) async throws -> Void,
        onLoadKey: @escaping @Sendable () async -> String?,
        onTestKey: @escaping @Sendable (String, URL, String) async throws -> Void
    ) {
        self._provider = provider
        self.onSaveKey = onSaveKey
        self.onLoadKey = onLoadKey
        self.onTestKey = onTestKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.lg) {
            // 基础信息分组：名称 / Base URL / 默认模型
            basicsCard

            // API Key 分组：输入 + 保存/测试按钮 + 状态消息
            apiKeyCard
        }
        .task {
            // 视图首次出现时同步 Base URL 字符串态
            baseURLText = provider.baseURL.absoluteString
            // 预读已有 API Key，同时存入 savedKey 供 Test 回退
            if let existing = await onLoadKey() {
                apiKey = existing
                savedKey = existing
                print("[ProviderEditorView] onLoadKey: key loaded for provider '\(provider.id)'")
            }
        }
    }

    // MARK: - 基础信息卡片

    /// 基础信息分组：名称 / Base URL / 默认模型
    private var basicsCard: some View {
        SectionCard("基础信息") {
            // 名称行
            SettingsRow("名称") {
                TextField("名称", text: $provider.name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
            }

            // Base URL 行：中间态编辑，失焦或回车时尝试解析
            SettingsRow("Base URL") {
                TextField("https://api.openai.com/v1", text: $baseURLText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
                    .onChange(of: baseURLText) { _, newValue in
                        // 实时解析，仅有效 URL 才回写，避免存入非法值
                        if let url = URL(string: newValue) {
                            provider.baseURL = url
                        }
                    }
            }

            // 默认模型行（最后一行无分隔线，借助 SettingsRow 内置分隔）
            SettingsRow("默认模型") {
                TextField("gpt-4o-mini", text: $provider.defaultModel)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
            }
        }
    }

    // MARK: - API Key 卡片

    /// API Key 分组：SecureField + Save / Test 按钮 + 状态消息
    private var apiKeyCard: some View {
        SectionCard("API Key") {
            // API Key 输入行
            SettingsRow("API Key") {
                SecureField("sk-…", text: $apiKey)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
            }

            // 操作按钮行（不用 SettingsRow，横向排列多个按钮）
            HStack(spacing: SliceSpacing.base) {
                PillButton("保存 Key", icon: "key", style: .secondary) {
                    Task { await saveKey() }
                }
                .disabled(apiKey.isEmpty)
                .opacity(apiKey.isEmpty ? 0.45 : 1)

                PillButton(isTesting ? "测试中…" : "测试连接", icon: "network", style: .secondary) {
                    Task { await testKey() }
                }
                .disabled(isTesting || effectiveKey.isEmpty)
                .opacity(isTesting || effectiveKey.isEmpty ? 0.45 : 1)

                Spacer()

                Text("存储在系统钥匙串")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
            }
            .padding(.vertical, SliceSpacing.base)

            // 状态消息区（saveMessage / testMessage 独立展示，避免按钮行 layout 抖动）
            if let msg = saveMessage {
                statusLabel(msg)
            }
            if let msg = testMessage {
                statusLabel(msg)
            }
        }
    }

    // MARK: - 计算属性

    /// Test 实际使用的 key：SecureField 非空用 typed；否则用预读的 saved key
    private var effectiveKey: String {
        apiKey.isEmpty ? savedKey : apiKey
    }

    // MARK: - 异步操作

    /// 执行保存：捕获当前 apiKey、调用 onSaveKey、按结果更新 saveMessage
    private func saveKey() async {
        let key = apiKey
        print("[ProviderEditorView] saveKey: begin for provider '\(provider.id)'")
        do {
            try await onSaveKey(key)
            // 同步更新 savedKey，让 Test 立即可用最新已保存值
            savedKey = key
            saveMessage = ProviderStatusMessage(text: "已保存", isError: false)
            print("[ProviderEditorView] saveKey: success")
            // 成功消息 2 秒后自动清除
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if saveMessage?.isError == false {
                saveMessage = nil
            }
        } catch {
            print("[ProviderEditorView] saveKey: failed – \(error.localizedDescription)")
            saveMessage = ProviderStatusMessage(
                text: "保存失败：\(error.localizedDescription)",
                isError: true
            )
        }
    }

    /// 执行连接测试：用 effectiveKey + 当前 baseURL/model，调 onTestKey
    private func testKey() async {
        let key = effectiveKey
        guard !key.isEmpty else { return }
        print("[ProviderEditorView] testKey: begin for provider '\(provider.id)' model=\(provider.defaultModel)")
        isTesting = true
        testMessage = ProviderStatusMessage(text: "测试中…", isError: false)
        do {
            try await onTestKey(key, provider.baseURL, provider.defaultModel)
            testMessage = ProviderStatusMessage(text: "连接成功", isError: false)
            isTesting = false
            print("[ProviderEditorView] testKey: success")
            // 成功消息 2 秒后自动清除
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if testMessage?.isError == false {
                testMessage = nil
            }
        } catch let err as SliceError {
            // SliceError 携带友好文案，直接展示 userMessage
            print("[ProviderEditorView] testKey: SliceError – \(err.developerContext)")
            testMessage = ProviderStatusMessage(text: "测试失败：\(err.userMessage)", isError: true)
            isTesting = false
        } catch {
            print("[ProviderEditorView] testKey: error – \(error.localizedDescription)")
            testMessage = ProviderStatusMessage(
                text: "测试失败：\(error.localizedDescription)",
                isError: true
            )
            isTesting = false
        }
    }

    // MARK: - 辅助视图

    /// 状态消息标签：错误用红色、成功/进行中用次要灰色
    @ViewBuilder
    private func statusLabel(_ msg: ProviderStatusMessage) -> some View {
        Text(msg.text)
            .font(SliceFont.caption)
            .foregroundColor(msg.isError ? SliceColor.error : SliceColor.textSecondary)
            .lineLimit(2)
            .padding(.vertical, SliceSpacing.xs)
    }
}

// MARK: - ProviderStatusMessage

/// 状态消息载体（文件内私有）
///
/// 用于 saveMessage / testMessage 双 @State，统一展示样式。
/// 重命名为 ProviderStatusMessage 避免与其他文件的同名私有类型冲突（Swift 私有类型
/// 在同一模块内仍可能因名称相同导致隐式遮蔽，加前缀更安全）。
private struct ProviderStatusMessage: Equatable, Sendable {
    let text: String
    let isError: Bool
}
