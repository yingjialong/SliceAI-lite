// SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift
import Foundation
import SliceCore
import SwiftUI

/// 设置界面主视图模型
///
/// 负责：
///   - 持有当前 `Configuration` 并在 `@Published` 下驱动 SwiftUI 刷新；
///   - 通过注入的 `ConfigurationProviding` 做加载/持久化；
///   - 通过注入的 `KeychainAccessing` 读写 API Key，避免把密钥塞进 Configuration。
///
/// 类型被标记为 `@MainActor`，保证 `@Published` 属性读写只发生在主线程，
/// 并兼容 Swift 6 严格并发检查。
@MainActor
public final class SettingsViewModel: ObservableObject {

    /// 当前正在编辑的完整配置；UI 通过 `$viewModel.configuration.xxx` 做双向绑定
    @Published public var configuration: Configuration

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
        self.configuration = DefaultConfiguration.initial()
        // 使用 [weak self] 捕获弱引用，避免在 Swift 6 严格并发下 self 在 init
        // 尚未完成时被强引用持有的诊断
        Task { [weak self] in await self?.reload() }
    }

    /// 从 store 拉取最新 Configuration 覆盖当前内存态
    public func reload() async {
        let cfg = await store.current()
        self.configuration = cfg
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
}
