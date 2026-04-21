// SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift
import Foundation
import LLMProviders
import SliceCore
import SwiftUI

/// 设置界面主视图模型
///
/// 负责：
///   - 持有当前 `Configuration` 并在 `@Published` 下驱动 SwiftUI 刷新；
///   - 通过注入的 `ConfigurationProviding` 做加载/持久化；
///   - 通过注入的 `KeychainAccessing` 读写 API Key，避免把密钥塞进 Configuration；
///   - 通过 `appearance` 字段单独暴露外观模式，配合 `setAppearance(_:)` 立即持久化。
///
/// 类型被标记为 `@MainActor`，保证 `@Published` 属性读写只发生在主线程，
/// 并兼容 Swift 6 严格并发检查。
@MainActor
public final class SettingsViewModel: ObservableObject {

    /// 当前正在编辑的完整配置；UI 通过 `$viewModel.configuration.xxx` 做双向绑定
    @Published public var configuration: Configuration

    /// 当前外观模式（从 configuration.appearance 同步），供 AppearanceSettingsPage 绑定
    ///
    /// 与 `configuration.appearance` 保持同步：`reload()` 时一起更新，
    /// `setAppearance(_:)` 时同时更新两者。设置该值会立即持久化，无需手动调用 save()。
    @Published public var appearance: AppearanceMode

    /// 配置持久化抽象，生产环境通常注入 `FileConfigurationStore`
    private let store: any ConfigurationProviding

    /// Keychain 抽象，生产环境注入 `KeychainStore`
    private let keychain: any KeychainAccessing

    /// 构造设置视图模型
    /// - Parameters:
    ///   - store: 配置读写抽象
    ///   - keychain: Keychain 读写抽象
    ///
    /// 初始化时先塞入内存态的默认配置占位，随后异步 reload 真实磁盘值。
    /// 这样可避免首次渲染出现空白，也无需在调用方处理 async init。
    public init(store: any ConfigurationProviding, keychain: any KeychainAccessing) {
        self.store = store
        self.keychain = keychain
        // 先用默认值占位，reload() 异步完成后更新为真实磁盘值
        let initial = DefaultConfiguration.initial()
        self.configuration = initial
        self.appearance = initial.appearance
        // 使用 [weak self] 捕获弱引用，避免在 Swift 6 严格并发下 self 在 init
        // 尚未完成时被强引用持有的诊断
        Task { [weak self] in await self?.reload() }
    }

    /// 设置外观模式并立即持久化，不需要调用 save()
    ///
    /// 实现顺序：
    ///   1. 更新 `configuration.appearance` 保持两者同步；
    ///   2. 更新独立发布的 `appearance` 属性触发 UI 刷新；
    ///   3. 调用 store.update 写回磁盘（允许失败静默处理，UI 已经切换，用户下次启动 reload 会同步）。
    /// - Parameter mode: 目标外观模式
    public func setAppearance(_ mode: AppearanceMode) async {
        // 更新两处发布属性保持同步
        configuration.appearance = mode
        appearance = mode
        // 写回磁盘；IO 失败不阻断 UI（下次启动 reload 会以磁盘为准）
        do {
            try await store.update(configuration)
        } catch {
            // 记录日志方便调试，不向上抛错（UI 已切换，用户体验优先）
            print("[SettingsViewModel] setAppearance: persist failed – \(error.localizedDescription)")
        }
    }

    /// 从 store 拉取最新 Configuration 覆盖当前内存态
    ///
    /// 同时同步 `appearance` 独立属性，保证两处数据一致。
    public func reload() async {
        let cfg = await store.current()
        self.configuration = cfg
        // 同步独立的 appearance 发布属性，使 AppearanceSettingsPage 刷新
        self.appearance = cfg.appearance
    }

    /// 将当前内存态 Configuration 写回 store
    /// - Throws: 底层 store 的 IO/序列化错误
    public func save() async throws {
        try await store.update(configuration)
    }

    /// 为指定 Provider 写入 API Key
    ///
    /// Keychain 的 account 必须通过 `Provider.keychainAccount` 解析自 `apiKeyRef`，
    /// 这样写入槽位与 `ToolExecutor.execute` 读取槽位一致，避免出现：
    ///   - 导入的配置中 `apiKeyRef = "keychain:shared-key"`，account != provider.id；
    ///   - 重命名 Provider（id 变化）后，旧的 `apiKeyRef` 指向的槽位仍被执行器读取，
    ///     但 UI 层却在新 id 对应的槽位里写键，导致运行时始终拿不到密钥。
    /// - Parameters:
    ///   - key: 明文 API Key；空串语义由调用方决定
    ///   - provider: 目标 Provider；其 `apiKeyRef` 决定写入的 Keychain account
    /// - Throws:
    ///   - `SliceError.configuration(.invalidJSON)` 当 `apiKeyRef` 不是 `keychain:` 前缀
    ///     （例如未来规划的 `env:` 方案），UI 层暂不支持写入
    ///   - Keychain 底层的 IO/OSStatus 错误
    public func setAPIKey(_ key: String, for provider: Provider) async throws {
        guard let account = provider.keychainAccount else {
            // apiKeyRef 不是 keychain: 前缀（例如将来的 env: 方案）；UI 层暂不支持写入
            throw SliceError.configuration(
                .invalidJSON(
                    "Provider '\(provider.id)' uses non-keychain apiKeyRef: \(provider.apiKeyRef)"
                )
            )
        }
        try await keychain.writeAPIKey(key, providerId: account)
    }

    /// 读取指定 Provider 的 API Key，不存在或非 keychain 引用时返回 nil
    ///
    /// 与 `setAPIKey(_:for:)` 对称，通过 `Provider.keychainAccount` 解析 account，
    /// 保证读取槽位与执行器一致。
    /// - Parameter provider: 目标 Provider；其 `apiKeyRef` 决定读取的 Keychain account
    /// - Returns: 明文 API Key；槽位为空或 `apiKeyRef` 非 keychain 前缀时返回 nil
    public func readAPIKey(for provider: Provider) async throws -> String? {
        // apiKeyRef 非 keychain: 前缀时，UI 无处可读，直接返回 nil 让 UI 回退到空态
        guard let account = provider.keychainAccount else { return nil }
        return try await keychain.readAPIKey(providerId: account)
    }

    /// 测试 Provider 配置是否可用
    ///
    /// 用传入的 `apiKey` / `baseURL` / `model` 临时构造一个 `OpenAICompatibleProvider`
    /// 并发一条最小 chat 请求（"Say OK." + temperature 0 + max_tokens 5）；
    /// 拿到首个 chunk 或流自然结束（HTTP 200 + 空 delta）即视为成功。
    ///
    /// 不读 Keychain、不修改 Configuration——key/baseURL/model 都来自调用方传入，
    /// 让 UI 能在用户改完字段还没 Save 时立即测试。
    ///
    /// - Parameters:
    ///   - apiKey: 测试用 API Key（可以是 SecureField 里的 typed 值，也可以是
    ///     已保存的 Keychain 值）
    ///   - baseURL: 测试用 baseURL；通常是 `provider.baseURL`
    ///   - model: 测试用模型 id；通常是 `provider.defaultModel`
    /// - Throws:
    ///   - `SliceError.provider(.unauthorized)`：401（API Key 无效）
    ///   - `SliceError.provider(.serverError(_))`：5xx
    ///   - `SliceError.provider(.networkTimeout)`：网络超时
    ///   - `SliceError.provider(.invalidResponse(_))`：响应非预期
    ///   - 其它由 URLSession / Foundation 抛出的底层错误
    public func testProvider(apiKey: String, baseURL: URL, model: String) async throws {
        // 临时构造一个 OpenAICompatibleProvider 用于探测；
        // 不影响 Configuration 或 ToolExecutor 持有的真实 provider 实例
        let probe = OpenAICompatibleProvider(baseURL: baseURL, apiKey: apiKey)
        let request = ChatRequest(
            model: model,
            messages: [ChatMessage(role: .user, content: "Say OK.")],
            temperature: 0,
            maxTokens: 5
        )
        let stream = try await probe.stream(request: request)
        // 拿到首个 chunk 即视为成功；流直接结束（HTTP 200 + 空 delta）也算成功
        // 注意：for-await 退出后 AsyncThrowingStream 的 onTermination 会 cancel 内部
        // URLSession.bytes 任务，避免无谓地继续接收流
        for try await _ in stream {
            break
        }
    }
}
