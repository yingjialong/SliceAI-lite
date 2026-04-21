// SliceAIApp/AppContainer.swift
import AppKit
import DesignSystem
import Foundation
import HotkeyManager
import LLMProviders
import Permissions
import SelectionCapture
import SettingsUI
import SliceCore
import Windowing

/// 应用的依赖注入组合根（Composition Root）。
///
/// 职责：
///   - 在应用启动的单点集中创建所有跨模块依赖，避免在业务层四处分散 `init`；
///   - 对外暴露只读属性，让 `AppDelegate` 在整个生命周期内持有并读取；
///   - 通过显式依赖注入，使 Swift 6 严格并发下的 `Sendable` 边界清晰可控。
///
/// 线程模型：`@MainActor` 限定，保证所有 UI 面板 / 监视器的创建都发生在主线程。
/// 生命周期：由 `AppDelegate` 在构造函数中实例化一次，随进程存活。
@MainActor
final class AppContainer {

    /// 配置文件读写 actor；路径固定为 `~/Library/Application Support/SliceAI/config.json`
    let configStore: FileConfigurationStore
    /// macOS Keychain 读写结构体；按 providerId 查 API Key
    let keychain: KeychainStore
    /// 选中文字捕获协调器；AX 为主、Clipboard 为备
    let selectionService: SelectionService
    /// 全局快捷键注册器（Carbon）
    let hotkeyRegistrar: HotkeyRegistrar
    /// 工具执行中枢；渲染 prompt、拉取 key、转发 LLM 流
    let toolExecutor: ToolExecutor
    /// 划词浮条面板（A 模式）
    let floatingToolbar: FloatingToolbarPanel
    /// 命令面板（⌥Space 调出）
    let commandPalette: CommandPalettePanel
    /// 流式结果面板
    let resultPanel: ResultPanel
    /// 辅助功能权限轮询监视器
    let accessibilityMonitor: AccessibilityMonitor
    /// 设置界面视图模型
    let settingsViewModel: SettingsViewModel
    /// 主题管理器：持有当前 AppearanceMode，驱动 SwiftUI ColorScheme 与 NSAppearance
    let themeManager: ThemeManager

    /// 组合根构造：所有依赖都在此处装配完毕，外部不再修改
    init() {
        // 1. 基础设施层：配置存储 + Keychain
        configStore = FileConfigurationStore(fileURL: FileConfigurationStore.standardFileURL())
        keychain = KeychainStore()

        // 2. 选中文字捕获服务：AX 主路径 + 剪贴板备用路径
        //    focusProvider 声明为 `@MainActor @Sendable`，与闭包内访问的
        //    NSWorkspace / NSEvent 等 MainActor 隔离 API 保持一致。调用方
        //    （ClipboardSelectionSource.readSelection）通过 `await` 主动跳到主线程，
        //    从根本上避免在非 actor 隔离的 async 上下文里误用 assumeIsolated 造成运行时陷阱。
        selectionService = SelectionService(
            primary: AXSelectionSource(),
            fallback: ClipboardSelectionSource(
                pasteboard: SystemPasteboard(),
                copyInvoker: SystemCopyKeystrokeInvoker(),
                focusProvider: { @MainActor in
                    guard let app = NSWorkspace.shared.frontmostApplication else {
                        return nil
                    }
                    return FocusInfo(
                        bundleID: app.bundleIdentifier ?? "",
                        appName: app.localizedName ?? "",
                        url: nil,
                        screenPoint: NSEvent.mouseLocation
                    )
                }
            )
        )

        // 3. 全局快捷键注册器：由 AppDelegate 在运行时按配置注册
        hotkeyRegistrar = HotkeyRegistrar()

        // 4. 工具执行中枢：注入 configStore（读工具/供应商）+ providerFactory + keychain
        toolExecutor = ToolExecutor(
            configurationProvider: configStore,
            providerFactory: OpenAIProviderFactory(),
            keychain: keychain
        )

        // 5. 展示层：三类面板
        floatingToolbar = FloatingToolbarPanel()
        commandPalette = CommandPalettePanel()
        resultPanel = ResultPanel()

        // 6. 权限与设置
        accessibilityMonitor = AccessibilityMonitor()
        settingsViewModel = SettingsViewModel(store: configStore, keychain: keychain)

        // 7. 主题管理器
        //    init() 是同步上下文，无法 await configStore.current()，
        //    因此先用 .auto 占位；AppDelegate.applicationDidFinishLaunching 中
        //    会异步读取配置并调用 themeManager.setMode(_:) 同步实际值。
        themeManager = ThemeManager(initialMode: .auto)

        // 8. 连接 onModeChange → 持久化到 config.json
        //    捕获 themeManager 与 configStore，在 @MainActor 闭包内发起 async Task
        //    以满足 actor 方法的 async 调用要求
        let store = configStore
        themeManager.onModeChange = { @MainActor mode in
            Task {
                // updateAppearance 是 actor 方法，需 await；失败静默忽略（磁盘 IO 不应阻断 UI）
                try? await store.updateAppearance(mode)
            }
        }
    }
}
