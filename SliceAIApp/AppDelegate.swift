// SliceAIApp/AppDelegate.swift
import AppKit
import DesignSystem
import HotkeyManager
import OSLog
import Permissions
import SelectionCapture
import SettingsUI
import SliceCore
import SwiftUI
import Windowing

/// 应用委托：承载全生命周期钩子、全局事件监视、窗口编排。
///
/// 职责：
///   - `applicationDidFinishLaunching`：安装菜单栏、权限监控、onboarding 或直接接线；
///   - `wireRuntime`：注册全局热键 + 安装鼠标监视器，启动划词触发链路；
///   - `execute`：组装工具执行结果到 `ResultPanel`，统一错误分类为 `SliceError`。
///
/// 线程模型：`@MainActor` 限定；所有 AppKit / SwiftUI / 面板 API 在主线程调用。
@MainActor
// swiftlint:disable type_body_length
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 诊断日志器；用于追踪划词触发链路在哪一层断开
    ///
    /// 与 `ConfigurationStore` 的 `Logger` 模式一致；subsystem 取 App 而非 Kit
    /// 以便在 Console.app 用 `subsystem:com.sliceai.lite` 一键过滤本进程的日志。
    /// 默认级别为 `.info`，Console.app 需要在菜单栏开启 "Action → Include Info
    /// Messages"；命令行可用：
    /// `log stream --predicate 'subsystem == "com.sliceai.lite"' --level info`
    private static let log = Logger(subsystem: "com.sliceai.lite", category: "AppDelegate")

    /// 应用的 DI 组合根，生命周期与 AppDelegate 相同
    let container: AppContainer

    /// 全局鼠标抬起监视器句柄；移除时需要 `NSEvent.removeMonitor`
    /// 声明为 Any? 而非 NSObject? 是 AppKit API 的约定
    private var globalMouseMonitor: Any?

    /// 全局鼠标按下监视器句柄；用于记录拖拽起点以区分单击与划词
    private var mouseDownMonitor: Any?

    /// 最近一次 mouseDown 的屏幕坐标；mouseUp 时用于计算位移判断是否为拖拽
    /// 在 @MainActor 上读写，避免与 mouseUp 回调产生竞态
    private var lastMouseDownLocation: CGPoint?

    /// mouseUp 之后的 debounce Task，保证同一次操作只触发一次划词捕获
    private var debounceTask: Task<Void, Never>?

    /// 菜单栏控制器；由 applicationDidFinishLaunching 创建
    private var menuBarController: MenuBarController?

    /// 当前打开的 Settings 窗口；关闭时仅 orderOut 以便下次复用
    private var settingsWindow: NSWindow?

    /// 当前打开的 Onboarding 窗口；完成或跳过后置 nil
    private var onboardingWindow: NSWindow?

    /// thinking toggle 进行中标志：防御快速连点 toggle 派出多个并发 task
    /// 上一个 toggle action 完整跑完前忽略新点击；@MainActor 隔离保证无 race
    private var thinkingToggleInFlight: Bool = false

    /// 构造：创建并持有 AppContainer；其余子系统在 didFinishLaunching 中装配
    override init() {
        self.container = AppContainer()
        super.init()
    }

    /// 应用启动完成回调：安装菜单栏、判断权限并决定走 onboarding 还是直接接线
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.log.info("applicationDidFinishLaunching")

        // 1. 菜单栏图标与菜单；创建后立即评估 provider 配置状态（是否需要显示小红点）
        menuBarController = MenuBarController(container: container, delegate: self)
        menuBarController?.refreshConfigStateIndicator()

        // 2. 权限监控：先启动轮询再根据当前状态分流
        //    未授予辅助功能 → 展示 onboarding；授予后再 wireRuntime
        container.accessibilityMonitor.startMonitoring()
        let trusted = container.accessibilityMonitor.isTrusted
        Self.log.info("AX trusted=\(trusted, privacy: .public)")
        if !trusted {
            Self.log.info("showOnboarding (AX not trusted)")
            showOnboarding()
        } else {
            wireRuntime()
        }

        // 3. 异步同步 ThemeManager 初始模式（init 是同步的无法 await），并启动主题跟踪
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cfg = await self.container.configStore.current()
            self.container.themeManager.setMode(cfg.appearance)
            self.applyAppearanceToAllWindows()
            self.startTrackingTheme()
        }
    }

    // MARK: - 主题跟踪

    /// 将当前 ThemeManager.mode 对应的 NSAppearance 应用到所有 NSWindow
    ///
    /// 当 mode == .auto 时 nsAppearance 为 nil，窗口自动跟随系统外观；
    /// light/dark 则强制指定对应外观。
    private func applyAppearanceToAllWindows() {
        let appearance = container.themeManager.nsAppearance
        NSApp.windows.forEach { $0.appearance = appearance }
    }

    /// 用 withObservationTracking 订阅 ThemeManager.mode 变化
    ///
    /// 每次 mode 变化时：
    ///   1. 应用新外观到所有窗口；
    ///   2. 递归重新订阅，保证后续变化仍能触发。
    /// 此模式是 Swift Observation 框架的标准订阅惯用法。
    private func startTrackingTheme() {
        withObservationTracking {
            // 读取 mode 以注册观察依赖；实际值不在这里使用
            _ = container.themeManager.mode
        } onChange: { [weak self] in
            // onChange 回调不在 MainActor，显式跳回主线程操作 UI
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyAppearanceToAllWindows()
                // 递归重订阅，以便追踪下一次变化
                self.startTrackingTheme()
            }
        }
    }

    // MARK: - 运行时接线

    /// 接线运行时触发链：全局热键 + 鼠标抬起监视器
    func wireRuntime() {
        Self.log.info("wireRuntime: start")
        reloadHotkey()
        installMouseMonitor()
        // 注入 "设置页录完新热键 → 重新向 Carbon 注册" 回调。放在 wireRuntime
        // 里而不是 init 是为了只有 AX 授权通过 / 用户完成 onboarding 后才接线；
        // 与 ThemeManager.onModeChange 的回调注入模式同构。
        container.settingsViewModel.onHotkeysChanged = { [weak self] in
            self?.reloadHotkey()
        }
        Self.log.info("wireRuntime: done")
    }

    /// 按配置中的 `hotkeys.toggleCommandPalette` （重新）注册全局热键
    ///
    /// 每次调用都会先 `unregisterAll` 清空上一次的 Carbon 注册，再按最新配置注册。
    /// 这样设置页改完热键立即生效，且避免旧热键遗留。
    ///
    /// 实现要点：
    ///   - 仅在 `triggers.commandPaletteEnabled == true` 时注册；
    ///   - 解析失败或 Carbon 注册失败均静默忽略，遵循"无自由日志"规范（详见任务 26
    ///     提交 804010f）。未来可由 Settings 面板上的错误指示来暴露；
    ///   - 回调中显式跳回 MainActor 以保持 UI 操作安全。
    func reloadHotkey() {
        // 先清空旧注册——必须同步完成，避免与下面 async register 产生窗口期
        container.hotkeyRegistrar.unregisterAll()
        Task { [weak self] in
            guard let self else { return }
            let cfg = await self.container.configStore.current()
            guard cfg.triggers.commandPaletteEnabled else {
                Self.log.info("hotkey: commandPaletteEnabled=false, skip")
                return
            }
            // parse 或 register 异常时仍按"无自由日志"规范不向用户抛错；
            // 但落一条 .info 诊断日志，便于在 Console.app 自检"⌥Space 为何没用"
            let raw = cfg.hotkeys.toggleCommandPalette
            guard let hk = try? Hotkey.parse(raw) else {
                Self.log.info("hotkey: parse failed for '\(raw, privacy: .public)'")
                return
            }
            do {
                _ = try self.container.hotkeyRegistrar.register(hk) { [weak self] in
                    // Carbon 回调已经在主线程，但 Swift 6 严格并发需要显式跳回 MainActor
                    Task { @MainActor in self?.showCommandPalette() }
                }
                Self.log.info("hotkey: registered \(hk.description, privacy: .public)")
            } catch {
                Self.log.info("hotkey: register failed \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// 安装全局鼠标监视器；同时追踪 mouseDown 起点与 mouseUp 终点
    ///
    /// 实现要点：
    ///   - 仅监听 mouseUp 会导致"任何单击"都进入 debounce 流程，产生 PopClip 类应用
    ///     不应出现的"点一下就弹浮条"的交互。
    ///   - 本方法改为同时监听 leftMouseDown（记录起点）与 leftMouseUp（算位移），
    ///     只有位移 ≥ 5pt（拖拽）才继续后续流程；小于阈值视为单击/抖动直接丢弃。
    ///   - `global monitor` 不会收到本应用的事件，这正是划词场景需要的；
    ///     监视器回调是 @Sendable，需显式跳回 MainActor 再读写 lastMouseDownLocation。
    private func installMouseMonitor() {
        // 记录 mouseDown 起点；locationInWindow 在全局监视器语境下即为屏幕坐标
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] ev in
            let loc = ev.locationInWindow
            Task { @MainActor in
                self?.lastMouseDownLocation = loc
            }
        }
        // mouseUp：若位移 < 5pt 判定为单击，不进入 debounce；≥ 5pt 认为是划词拖拽
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] ev in
            let upLoc = ev.locationInWindow
            Task { @MainActor in
                guard let self else { return }
                guard let downLoc = self.lastMouseDownLocation else { return }
                // 无论是否触发后续流程，都清空起点防止下一次 mouseUp 误用旧值
                self.lastMouseDownLocation = nil
                let dx = upLoc.x - downLoc.x
                let dy = upLoc.y - downLoc.y
                let dist = (dx * dx + dy * dy).squareRoot()
                // 阈值 5pt：过滤单击与轻微抖动，仅拖拽选区进入 onMouseUp
                guard dist >= 5 else {
                    // 走 .debug 以免大量单击刷屏；用户用 `log stream --level debug` 才能看到
                    Self.log.debug("mouseUp: dist=\(dist, privacy: .public) below threshold")
                    return
                }
                Self.log.info("mouseUp: dist=\(dist, privacy: .public) >= 5pt, scheduling capture")
                self.onMouseUp()
            }
        }
        // 两个 global monitor 依赖 Accessibility 权限；权限缺失时回调不会被触发
        Self.log.info("installMouseMonitor: monitors installed (mouseDown + mouseUp)")
    }

    /// 鼠标抬起事件处理：读配置 → 取消旧 debounce → 按延迟启动捕获
    private func onMouseUp() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cfg = await self.container.configStore.current()
            guard cfg.triggers.floatingToolbarEnabled else {
                Self.log.info("onMouseUp: floatingToolbarEnabled=false, skip")
                return
            }
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
        // spec §1.4 #2 / §3.1 / §7.2 都要求 mouseUp 路径走 "AX 优先 → Cmd+C
        // fallback 透明降级"，否则 Sublime / VSCode / Figma / Slack 等不暴露 AX
        // 的应用根本拿不到选中文字。
        //
        // 防御"虚假浮条"（拖动 UI / 拖窗口等非选区操作触发）的三道防线：
        //   1. installMouseMonitor 内的位移阈值：拖拽 < 5pt 直接 return；
        //   2. ClipboardSelectionSource 的 changeCount 校验：用户未真正选中文字时
        //      ⌘C 在系统标准控件下是 no-op，pasteboard.changeCount 不变即返回 nil，
        //      不会把旧剪贴板内容误当成"选中"；
        //   3. minimumSelectionLength 长度过滤：偶发 1-2 字误读丢弃。
        let payload: SelectionPayload?
        do {
            payload = try await container.selectionService.capture()
        } catch {
            // capture() 内部已把子 source 的异常吞成 nil；这里兜底只是防御性，
            // 万一未来某个 SelectionSource 改为透传错误也能在 Console 看到
            Self.log.info("capture: throw \(String(describing: error), privacy: .public)")
            return
        }
        guard let payload else {
            Self.log.info("capture: nil (AX 与 Cmd+C fallback 均未拿到选区)")
            return
        }
        // 黑名单应用：命中则忽略该次触发
        if cfg.appBlocklist.contains(payload.appBundleID) {
            Self.log.info("capture: blocked by appBlocklist \(payload.appBundleID, privacy: .public)")
            return
        }
        // 选区过短：避免偶发的 1-2 字选中误触发
        let len = payload.text.count
        let minLen = cfg.triggers.minimumSelectionLength
        guard len >= minLen else {
            Self.log.info("capture: too short len=\(len, privacy: .public) min=\(minLen, privacy: .public)")
            return
        }
        // 把字段值先存短别名，以让 log 模板控制在 SwiftLint line_length=120 以内。
        // src（source）便于在 Console 里区分"AX 命中"还是"Cmd+C fallback 命中"。
        let app = payload.appBundleID
        let src = payload.source.rawValue
        Self.log.info(
            "capture: shown bundle=\(app, privacy: .public) len=\(len, privacy: .public) src=\(src, privacy: .public)"
        )
        // 展示浮条：回调中按选中工具执行；autoDismiss 读配置（0=不自动消失）
        container.floatingToolbar.show(
            tools: cfg.tools,
            anchor: payload.screenPoint,
            maxTools: cfg.triggers.floatingToolbarMaxTools,
            size: cfg.triggers.floatingToolbarSize,
            autoDismissSeconds: cfg.triggers.floatingToolbarAutoDismissSeconds
        ) { [weak self] tool in
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

    /// 触发一次工具执行：先启 stream task，再开结果窗并把 task.cancel 挂到 onDismiss
    /// - Parameters:
    ///   - tool: 要执行的工具定义
    ///   - payload: 选中文字及其来源上下文
    func execute(tool: SliceCore.Tool, payload: SelectionPayload) {
        let streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 在 stream 创建前 snapshot 当前 generation；后续 toggle/regenerate 触发的新 open()
            // 会让 panel.generation 递增，此处 hold 的 gen 失效，append/finish 被丢弃
            // 这是协作式 cancel 的兜底：cancel 后 for-await 还会处理已 buffer 的 chunk，
            // 必须靠 generation stamp 防止旧 stream 污染新 panel 内容
            let gen = self.container.resultPanel.currentGeneration()
            do {
                let stream = try await self.container.toolExecutor.execute(tool: tool, payload: payload)
                // 传递完整 ChatChunk（含 reasoningDelta），由 ResultPanel.append 分发到正文和推理区
                for try await chunk in stream {
                    self.container.resultPanel.append(chunk, generation: gen)
                }
                self.container.resultPanel.finish(generation: gen)
            } catch {
                self.handleStreamError(error, tool: tool, payload: payload)
            }
        }
        let showToggle = shouldShowThinkingToggle(for: tool)
        Self.log.info("execute: tool=\(tool.name, privacy: .public) showToggle=\(showToggle, privacy: .public)")
        // open panel：onDismiss 捕获 streamTask，onToggleThinking 持久化后用最新 tool 重执行
        container.resultPanel.open(
            toolName: tool.name,
            model: tool.modelId ?? "default",
            anchor: payload.screenPoint,
            onDismiss: { streamTask.cancel() },
            onRegenerate: { [weak self] in
                streamTask.cancel()
                Self.log.info("onRegenerate: re-running tool=\(tool.name, privacy: .public)")
                self?.execute(tool: tool, payload: payload)
            },
            showThinkingToggle: showToggle,
            thinkingEnabled: tool.thinkingEnabled,
            onToggleThinking: makeToggleThinkingAction(
                for: tool,
                payload: payload,
                cancelStream: { streamTask.cancel() }
            )
        )
    }

    /// thinking 切换按钮显隐逻辑：provider.thinking 非 nil，且 byModel 时 tool 有 thinkingModelId
    ///
    /// 使用 settingsViewModel.configuration（@MainActor @Published）同步读取，无需 await。
    private func shouldShowThinkingToggle(for tool: SliceCore.Tool) -> Bool {
        let provider = container.settingsViewModel.configuration.providers
            .first(where: { $0.id == tool.providerId })
        guard let thinking = provider?.thinking else { return false }
        switch thinking {
        case .byModel:
            return tool.thinkingModelId != nil
        case .byParameter:
            return true
        }
    }

    /// 构造 thinking 切换 closure：先取消当前 stream，持久化后用最新 tool 快照重新执行
    ///
    /// 关键点：
    /// - 必须先 `cancelStream()` 再 `execute()`，否则旧 stream 会继续 append chunk，
    ///   与新 stream 的 chunk 在 ResultPanel 内并发写入 viewModel.text 导致输出乱序
    /// - `cancelStream` 由 caller 注入（捕获 streamTask），helper 不持有 streamTask 引用
    /// - toggleThinking 后 `tool` 局部变量 stale，需从最新 configuration 取 fresh 快照
    private func makeToggleThinkingAction(
        for tool: SliceCore.Tool,
        payload: SelectionPayload,
        cancelStream: @escaping @Sendable () -> Void
    ) -> (@MainActor () -> Void) {
        { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // 防止快速连点：上一个 toggle 完整跑完前忽略后续点击。
                // generation counter 已经能阻止旧 stream 污染内容，这里追加防御主要是
                // 避免无意义地派多个 streamTask + open() 闪烁
                guard !self.thinkingToggleInFlight else { return }
                self.thinkingToggleInFlight = true
                defer { self.thinkingToggleInFlight = false }
                cancelStream()
                await self.container.settingsViewModel.toggleThinking(for: tool.id)
                guard let fresh = self.container.settingsViewModel.configuration.tools
                    .first(where: { $0.id == tool.id }) else { return }
                // swiftlint:disable:next line_length
                Self.log.info("onToggleThinking: re-run tool=\(fresh.name, privacy: .public) enabled=\(fresh.thinkingEnabled, privacy: .public)")
                self.execute(tool: fresh, payload: payload)
            }
        }
    }

    /// 统一处理 stream task 的错误：取消错误静默退出，其他错误映射到 SliceError 展示给用户
    /// - Parameters:
    ///   - error: stream task 抛出的原始错误
    ///   - tool: 触发本次执行的工具（用于重试 closure 捕获）
    ///   - payload: 本次执行的选区 payload（用于重试 closure 捕获）
    private func handleStreamError(_ error: Error, tool: SliceCore.Tool, payload: SelectionPayload) {
        // 用户主动 dismiss panel 触发 task.cancel()：静默退出，panel 已不可见
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return
        }
        // 映射到 SliceError；developerContext 内的字符串 payload 已在 SliceError 层脱敏
        let sliceError: SliceError
        if let err = error as? SliceError {
            sliceError = err
        } else {
            sliceError = .provider(.invalidResponse(String(describing: error)))
        }
        container.resultPanel.fail(
            with: sliceError,
            onRetry: { [weak self] in
                guard let self else { return }
                self.execute(tool: tool, payload: payload)
            },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )
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
        // 注入 themeManager 使设置页内的 @Environment(ThemeManager.self) 可用
        let rootView = SettingsScene(viewModel: container.settingsViewModel)
            .environment(container.themeManager)
        let hosting = NSHostingController(rootView: rootView)
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

    /// 显示首次启动引导：权限授予后回调关闭窗口并接线运行时
    ///
    /// Provider / API Key 的配置已从 Onboarding 移除，用户需在「设置 → Providers」
    /// 中自行添加。首次划词若未配置 Provider，会命中 ResultPanel 的错误态，
    /// 其"打开设置"按钮会引导用户到设置页。
    func showOnboarding() {
        let view = OnboardingFlow(
            accessibilityMonitor: container.accessibilityMonitor,
            onFinish: { [weak self] in
                Task { @MainActor in self?.finishOnboarding() }
            }
        )
        // 注入 themeManager 使 OnboardingFlow 内部视图也能读取当前主题
        let hosting = NSHostingController(rootView: view.environment(container.themeManager))
        let win = NSWindow(contentViewController: hosting)
        win.title = "Welcome to SliceAI"
        win.styleMask = [.titled]
        win.setContentSize(NSSize(width: 560, height: 520))
        win.isReleasedWhenClosed = false
        win.center()
        onboardingWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Onboarding 完成：关闭窗口、接线运行时并刷新菜单栏图标状态
    private func finishOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        wireRuntime()
        // Onboarding 完成后重新评估是否已有 Provider，刷新菜单栏小红点状态
        menuBarController?.refreshConfigStateIndicator()
    }
} // swiftlint:enable type_body_length
