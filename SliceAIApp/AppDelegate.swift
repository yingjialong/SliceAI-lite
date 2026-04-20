// SliceAIApp/AppDelegate.swift
import AppKit
import SwiftUI
import SliceCore
import SelectionCapture
import HotkeyManager
import Windowing
import Permissions
import SettingsUI

/// 应用委托：承载全生命周期钩子、全局事件监视、窗口编排。
///
/// 职责：
///   - `applicationDidFinishLaunching`：安装菜单栏、权限监控、onboarding 或直接接线；
///   - `wireRuntime`：注册全局热键 + 安装鼠标监视器，启动划词触发链路；
///   - `execute`：组装工具执行结果到 `ResultPanel`，统一错误分类为 `SliceError`。
///
/// 线程模型：`@MainActor` 限定；所有 AppKit / SwiftUI / 面板 API 在主线程调用。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 应用的 DI 组合根，生命周期与 AppDelegate 相同
    let container: AppContainer

    /// 全局鼠标抬起监视器句柄；移除时需要 `NSEvent.removeMonitor`
    /// 声明为 Any? 而非 NSObject? 是 AppKit API 的约定
    private var globalMouseMonitor: Any?

    /// mouseUp 之后的 debounce Task，保证同一次操作只触发一次划词捕获
    private var debounceTask: Task<Void, Never>?

    /// 菜单栏控制器；由 applicationDidFinishLaunching 创建
    private var menuBarController: MenuBarController?

    /// 当前打开的 Settings 窗口；关闭时仅 orderOut 以便下次复用
    private var settingsWindow: NSWindow?

    /// 当前打开的 Onboarding 窗口；完成或跳过后置 nil
    private var onboardingWindow: NSWindow?

    /// 构造：创建并持有 AppContainer；其余子系统在 didFinishLaunching 中装配
    override init() {
        self.container = AppContainer()
        super.init()
    }

    /// 应用启动完成回调：安装菜单栏、判断权限并决定走 onboarding 还是直接接线
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 菜单栏图标与菜单
        menuBarController = MenuBarController(container: container, delegate: self)

        // 2. 权限监控：先启动轮询再根据当前状态分流
        //    未授予辅助功能 → 展示 onboarding；授予后再 wireRuntime
        container.accessibilityMonitor.startMonitoring()
        if !container.accessibilityMonitor.isTrusted {
            showOnboarding()
        } else {
            wireRuntime()
        }
    }

    // MARK: - 运行时接线

    /// 接线运行时触发链：全局热键 + 鼠标抬起监视器
    func wireRuntime() {
        registerHotkey()
        installMouseMonitor()
    }

    /// 按配置中的 `hotkeys.toggleCommandPalette` 注册全局热键
    ///
    /// 实现要点：
    ///   - 仅在 `triggers.commandPaletteEnabled == true` 时注册；
    ///   - 解析失败或 Carbon 注册失败均静默忽略，遵循"无自由日志"规范（详见任务 26
    ///     提交 804010f）。未来可由 Settings 面板上的错误指示来暴露；
    ///   - 回调中显式跳回 MainActor 以保持 UI 操作安全。
    private func registerHotkey() {
        Task { [weak self] in
            guard let self else { return }
            let cfg = await self.container.configStore.current()
            guard cfg.triggers.commandPaletteEnabled else { return }
            // parse 或 register 异常时静默忽略；避免破坏无自由日志规范
            guard let hk = try? Hotkey.parse(cfg.hotkeys.toggleCommandPalette) else { return }
            _ = try? self.container.hotkeyRegistrar.register(hk) { [weak self] in
                // Carbon 回调已经在主线程，但 Swift 6 严格并发需要显式跳回 MainActor
                Task { @MainActor in self?.showCommandPalette() }
            }
        }
    }

    /// 安装全局鼠标抬起监视器；回调内进入 debounce 流程
    private func installMouseMonitor() {
        // 注意：global monitor 不会收到本应用的事件，这正是划词场景需要的
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            // 监视器回调为 @Sendable，显式跳回主线程再调用业务方法
            Task { @MainActor in self?.onMouseUp() }
        }
    }

    /// 鼠标抬起事件处理：读配置 → 取消旧 debounce → 按延迟启动捕获
    private func onMouseUp() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cfg = await self.container.configStore.current()
            guard cfg.triggers.floatingToolbarEnabled else { return }
            // 取消上一次还未执行的捕获任务，保证高频点击时只触发最后一次
            self.debounceTask?.cancel()
            let delay = cfg.triggers.triggerDelayMs
            self.debounceTask = Task { [weak self] in
                // sleep 以 ns 为单位；delay 配置以 ms 为单位
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                if Task.isCancelled { return }
                await self?.tryCaptureAndShowToolbar(cfg)
            }
        }
    }

    /// 尝试捕获选中文字并按配置过滤后展示浮条
    /// - Parameter cfg: 触发时刻的配置快照，避免与用户编辑产生竞态
    private func tryCaptureAndShowToolbar(_ cfg: Configuration) async {
        // 捕获失败或为空都直接退出；单路失败已在 SelectionService 内被静默降级
        guard let payload = try? await container.selectionService.capture() else { return }
        // 黑名单应用：命中则忽略该次触发
        if cfg.appBlocklist.contains(payload.appBundleID) { return }
        // 选区过短：避免偶发的 1-2 字选中误触发
        guard payload.text.count >= cfg.triggers.minimumSelectionLength else { return }
        // 展示浮条：回调中按选中工具执行
        container.floatingToolbar.show(tools: cfg.tools, anchor: payload.screenPoint) { [weak self] tool in
            self?.execute(tool: tool, payload: payload)
        }
    }

    // MARK: - Command Palette

    /// 显示命令面板：读取当前配置 + 可选地预取一次选区预览
    func showCommandPalette() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cfg = await self.container.configStore.current()
            // 预览不是必选；单路失败允许为空字符串显示
            let payload = try? await self.container.selectionService.capture()
            self.container.commandPalette.show(
                tools: cfg.tools,
                preview: payload?.text
            ) { [weak self] tool in
                guard let self else { return }
                // 只有在确实拿到选区时才执行工具；否则仅关闭面板
                if let payload {
                    self.execute(tool: tool, payload: payload)
                }
            }
        }
    }

    // MARK: - 执行工具

    /// 触发一次工具执行：先开结果窗占位，再把流式 chunk 追加进去
    /// - Parameters:
    ///   - tool: 要执行的工具定义
    ///   - payload: 选中文字及其来源上下文
    func execute(tool: SliceCore.Tool, payload: SelectionPayload) {
        // 结果窗立即显示，避免流式接入前出现"无反馈"视觉停顿
        container.resultPanel.open(toolName: tool.name, model: tool.modelId ?? "default")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // 进入 ToolExecutor actor → 拉 key → 组 request → 得到 AsyncThrowingStream
                let stream = try await self.container.toolExecutor.execute(tool: tool, payload: payload)
                for try await chunk in stream {
                    self.container.resultPanel.append(chunk.delta)
                }
                self.container.resultPanel.finish()
            } catch let err as SliceError {
                // 已分类的应用错误：展示 userMessage，并挂上 [重试]/[打开设置] 恢复动作
                // 重试动作：在主线程重新触发一次本次 execute（参数不变，闭包捕获 tool/payload）
                // 打开设置：跳转到 Settings 窗口，方便用户修正 API Key 等配置
                self.container.resultPanel.fail(
                    with: err,
                    onRetry: { [weak self] in
                        guard let self else { return }
                        self.execute(tool: tool, payload: payload)
                    },
                    onOpenSettings: { [weak self] in
                        self?.showSettings()
                    }
                )
            } catch {
                // 未分类错误：统一降级为 provider.invalidResponse 以复用 userMessage 体系
                // 注：invalidResponse 的字符串 payload 会被 developerContext 脱敏为 <redacted>
                // 同样提供重试 / 打开设置恢复动作，避免把"未知错误"变成死胡同
                self.container.resultPanel.fail(
                    with: .provider(.invalidResponse(String(describing: error))),
                    onRetry: { [weak self] in
                        guard let self else { return }
                        self.execute(tool: tool, payload: payload)
                    },
                    onOpenSettings: { [weak self] in self?.showSettings() }
                )
            }
        }
    }

    // MARK: - Windows

    /// 显示 Settings 窗口；若已存在则复用并置前
    func showSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // NSHostingController 承载 SwiftUI 设置视图；ViewModel 由容器复用
        let hosting = NSHostingController(rootView: SettingsScene(viewModel: container.settingsViewModel))
        let win = NSWindow(contentViewController: hosting)
        win.title = "SliceAI Settings"
        win.styleMask = [.titled, .closable, .resizable]
        win.setContentSize(NSSize(width: 720, height: 480))
        // 不在关闭时释放窗口实例，便于下次 showSettings 快速恢复
        win.isReleasedWhenClosed = false
        win.center()
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 显示首次启动引导：权限授予后回调把 API Key 存入 Keychain 并接线运行时
    func showOnboarding() {
        let view = OnboardingFlow(
            accessibilityMonitor: container.accessibilityMonitor,
            onFinish: { [weak self] apiKey in
                // OnboardingFlow 回调是 @escaping (String) -> Void，跳回 MainActor 以操作 UI
                Task { @MainActor in
                    guard let self else { return }
                    // 仅在用户实际填写 Key 时写入 Keychain；空串语义为"稍后再说"
                    if !apiKey.isEmpty {
                        // 写失败静默忽略：设置面板后续可再次录入
                        try? await self.container.keychain.writeAPIKey(
                            apiKey,
                            providerId: "openai-official"
                        )
                    }
                    // 关闭引导窗口后正式接线运行时
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                    self.wireRuntime()
                }
            }
        )
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Welcome to SliceAI"
        // 只带标题栏、无关闭按钮；强制用户走完引导流程
        win.styleMask = [.titled]
        win.setContentSize(NSSize(width: 480, height: 340))
        win.isReleasedWhenClosed = false
        win.center()
        onboardingWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
