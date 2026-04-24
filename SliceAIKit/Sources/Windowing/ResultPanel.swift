// SliceAIKit/Sources/Windowing/ResultPanel.swift
import AppKit
import DesignSystem
import SliceCore
import SwiftUI

/// 流式结果浮窗：选区附近浮出 + 可钉 + 可拖 + 可调整大小
///
/// 用法：
/// ```swift
/// let panel = ResultPanel()
/// panel.open(
///     toolName: "翻译",
///     model: "gpt-4o-mini",
///     anchor: payload.screenPoint,
///     onDismiss: { streamTask.cancel() }   // 用户主动关闭时取消 LLM 请求
/// )
/// panel.append("Hello")     // 每收到一段 delta 调一次
/// panel.finish()            // 流结束
/// // 出错时（带恢复动作）：
/// // panel.fail(with: .provider(.unauthorized),
/// //            onRetry: { ... }, onOpenSettings: { ... })
/// ```
///
/// 行为约定：
/// - **样式**：borderless + nonactivatingPanel + 圆角；无系统 title bar，
///   pin / close 由内容区角落的 SwiftUI 按钮承载
/// - **位置**：用 `ScreenAwarePositioner` 在 selection anchor 附近定位
/// - **尺寸**：默认 480×340，用户可拖右下/边缘调整；新一次 open 复用上次尺寸
/// - **钉**：跨 open() 保留 `isPinned` 状态。pin = `level = .statusBar` + 不装
///   外部点击监视器；非钉 = `level = .floating` + 装 monitor，点 panel 外即
///   触发 `dismiss()`（同时回调 `onDismiss`，让 AppDelegate cancel stream task）
///
/// 线程模型：`@MainActor` 限定，所有公开 API 必须在主线程调用。
@MainActor
public final class ResultPanel {

    /// 承载内容的 NSPanel；首次 open 时懒创建，dismiss 后保留以便复用
    private var panel: NSPanel?
    /// 驱动 SwiftUI 视图的观察对象，open 时 reset、append/finish/fail 时更新
    private let viewModel = ResultViewModel()
    /// 屏幕边界感知的坐标计算器（与 FloatingToolbarPanel 复用同一实现）
    private let positioner = ScreenAwarePositioner()
    /// 全局 mouseDown 监视器；非钉态安装、钉态移除
    ///
    /// 关键不变量：`NSEvent.addGlobalMonitorForEvents` 不接收本进程窗口产生
    /// 的事件，所以点 panel 内按钮、拖动 panel 都不会触发，只有点 panel 外
    /// （其他 App / 桌面 / 本 App 其他窗口）才触发 → dismiss
    private var outsideClickMonitor: Any?
    /// 当前 dismiss 回调；由 `open(...)` 调用方传入，通常用于 cancel 正在跑的
    /// stream Task。`dismiss()` 内调用一次后置 nil，避免重复 cancel
    private var onDismiss: (@MainActor () -> Void)?
    /// 是否钉住；跨 open() 保留，让用户钉过的窗口在新 tool 触发后仍保持钉住
    private var isPinned: Bool = false

    /// 无状态构造器
    public init() {}

    /// 展示结果窗口
    /// - Parameters:
    ///   - toolName: 当前触发的工具名称（标题栏主标题）
    ///   - model: 当前使用的模型（标题栏副文本）
    ///   - anchor: 选区中心（屏幕坐标，左下原点）；用于把 panel 定位到鼠标附近
    ///   - onDismiss: 用户主动关闭（点关闭按钮 / 点外部）时的回调；通常传入
    ///     `{ streamTask.cancel() }` 让 AppDelegate 取消正在跑的 LLM 请求
    ///   - onRegenerate: 用户点击"重新生成"按钮时的回调；调用方需传入重新触发
    ///     本次 tool + payload 的 closure；nil 时按钮仍显示但点击无效果
    ///   - showThinkingToggle: 是否显示思考切换按钮（仅当 Provider.thinking 非 nil 时为 true）
    ///   - thinkingEnabled: 当前工具的 thinking 开关状态（与 tool.thinkingEnabled 同步）
    ///   - onToggleThinking: 用户点击 thinking 切换按钮时的回调；nil 时按钮隐藏
    public func open(
        toolName: String,
        model: String,
        anchor: CGPoint,
        onDismiss: (@MainActor () -> Void)? = nil,
        onRegenerate: (@MainActor () -> Void)? = nil,
        showThinkingToggle: Bool = false,
        thinkingEnabled: Bool = false,
        onToggleThinking: (@MainActor () -> Void)? = nil
    ) {
        // 缓存 dismiss 回调；下次 open 时会被覆盖（旧 task 应在那之前自然结束）
        self.onDismiss = onDismiss

        // 复用上次尺寸（让用户拖拽过的尺寸跨 open 保持）；首次 open 用默认 480×340
        let size = panel?.frame.size ?? CGSize(width: 480, height: 340)

        // 选锚点所在屏幕；fallback 到主屏；再 fallback 到零矩形避免 nil
        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.contains(anchor)
        })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 用 positioner 计算 origin：默认在锚点下方 16pt；越界则翻到上方并水平夹紧
        let origin = positioner.position(anchor: anchor, size: size, screen: screen, offset: 16)

        if panel == nil {
            // 首次创建 panel
            panel = makePanel(size: size, origin: origin)
        } else {
            // 复用：仅更新位置（保留用户拖拽过的尺寸）
            panel?.setFrameOrigin(origin)
        }

        // 重置 viewModel 的内容字段；onTogglePin / onClose 在每次 open 重新绑定
        // 以确保 weak self 引用始终指向当前实例
        viewModel.reset(toolName: toolName, model: model)
        viewModel.isPinned = isPinned
        viewModel.onTogglePin = { [weak self] in
            self?.togglePin()
        }
        viewModel.onClose = { [weak self] in
            self?.dismiss()
        }
        // 绑定重新生成回调：直接透传调用方 closure
        viewModel.onRegenerate = onRegenerate
        // 绑定复制回调：读取当前 viewModel.text 复制到系统剪贴板
        viewModel.onCopy = { [weak viewModel] in
            guard let viewModel else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(viewModel.text, forType: .string)
        }
        // 绑定 thinking toggle 状态与回调；reset() 已清空 accumulatedReasoning / reasoningExpanded
        viewModel.showThinkingToggle = showThinkingToggle
        viewModel.thinkingEnabled = thinkingEnabled
        viewModel.onToggleThinking = onToggleThinking
        panel?.makeKeyAndOrderFront(nil)
        // 应用 pin 状态：设置 level + 装/卸 outside-click monitor
        applyPinState()
    }

    /// 追加一段流式 ChatChunk 到结果区；同时处理正文 delta 与 reasoning delta
    ///
    /// - Parameter chunk: SSE 流式片段，包含 delta（正文增量）和 reasoningDelta（推理增量）
    /// - Note: 对不支持 thinking 的模型，chunk.reasoningDelta 始终为 nil，不影响正常流程
    public func append(_ chunk: SliceCore.ChatChunk) {
        viewModel.append(delta: chunk.delta, reasoningDelta: chunk.reasoningDelta)
    }

    /// 标记流式输出正常结束（关闭闪烁光标）
    public func finish() {
        viewModel.finish()
    }

    /// 标记流式输出以错误结束；将错误的 userMessage 显示在结果区，并挂载可选恢复动作
    /// - Parameters:
    ///   - error: 统一错误类型；`userMessage` 展示给用户、`developerContext` 填入折叠详情
    ///   - onRetry: 可选的"重试"回调，nil 时不显示重试按钮
    ///   - onOpenSettings: 可选的"打开设置"回调，nil 时不显示该按钮
    ///
    /// 注：`developerContext` 已在 SliceError.swift 层做脱敏（不会携带 API Key/响应原文），
    /// 直接展示在 UI 上是安全的。
    public func fail(
        with error: SliceError,
        onRetry: (@MainActor () -> Void)? = nil,
        onOpenSettings: (@MainActor () -> Void)? = nil
    ) {
        viewModel.fail(
            message: error.userMessage,
            detail: error.developerContext,
            onRetry: onRetry,
            onOpenSettings: onOpenSettings
        )
    }

    /// 关闭窗口（兼容旧 API；行为同 `dismiss()`）
    public func close() {
        dismiss()
    }

    /// 主动关闭浮窗：触发 onDismiss 回调（cancel stream）+ 清理监视器 + 隐藏 panel
    ///
    /// 幂等：多次调用安全。`onDismiss` 只调用一次（调用后置 nil），避免重复 cancel。
    public func dismiss() {
        // 先回调让外部取消 stream，再隐藏 panel；顺序重要——回调内若有耗时
        // 操作也不会阻塞 panel 消失的视觉响应（onDismiss 通常是 task.cancel()，瞬时）
        onDismiss?()
        onDismiss = nil
        removeOutsideClickMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - 钉切换 + 监视器

    /// 切换钉/非钉状态；通过 viewModel 同步给 SwiftUI 按钮的图标
    private func togglePin() {
        isPinned.toggle()
        viewModel.isPinned = isPinned
        applyPinState()
    }

    /// 应用当前 pin 状态：钉 → statusBar 层 + 不监听外部点击；非钉 → floating + 监听
    private func applyPinState() {
        if isPinned {
            // statusBar 层确保钉住的窗口在其他 floating 窗口（包括工具栏浮条）之上
            panel?.level = .statusBar
            removeOutsideClickMonitor()
        } else {
            panel?.level = .floating
            installOutsideClickMonitor()
        }
    }

    /// 安装全局 mouseDown 监视器；任何 panel 外的点击都触发 dismiss
    ///
    /// 监听 left + right + other 三类按下，覆盖三键鼠标 / 触控板的所有 click 来源。
    /// 回调签名是 `@Sendable`，需显式跳回 MainActor 才能安全调用 `dismiss()`。
    private func installOutsideClickMonitor() {
        // 防御：先移除可能残留的旧 monitor，避免叠加多个回调重复 dismiss
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    /// 移除全局 mouseDown 监视器；幂等
    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Panel 构造

    /// 创建 borderless + nonactivatingPanel + resizable 的 NSPanel
    ///
    /// - `borderless`：去掉系统 title bar，pin / close 由内容区按钮承载
    /// - `nonactivatingPanel`：弹出时不抢占焦点，不打断用户在前台 App 的工作
    /// - `resizable`：允许从 4 边 / 4 角拖动调整大小（受 minSize / maxSize 约束）
    /// - `isMovableByWindowBackground`：设为 false；拖动由 header 区的
    ///   DragAreaHost（NSView.performDrag）接管，只有 header 空白区可拖
    private func makePanel(size: CGSize, origin: CGPoint) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        // canJoinAllSpaces：在任意 Space 显示；fullScreenAuxiliary：全屏 App 上也可见
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        // 关闭系统背景拖动；header 区域的拖动由 DragAreaHost（NSView.performDrag）接管
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        // 让 SwiftUI 圆角背景透出：透明底色 + 非不透明窗体
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // resize 范围约束：避免拖到完全不可用 / 撑满屏幕
        panel.minSize = NSSize(width: 320, height: 200)
        panel.maxSize = NSSize(width: 720, height: 520)
        // 关闭按钮走 orderOut，不释放窗口实例，下次 open 继续复用
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: ResultContent(viewModel: viewModel))
        hosting.frame = NSRect(origin: .zero, size: size)
        // SwiftUI hosting 跟着 panel resize 自动伸缩
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }
}

/// 结果窗的 SwiftUI 状态源
///
/// 作为 `ObservableObject` 在主 actor 驱动 UI；`@Published` 字段由 `ResultPanel`
/// 公开方法改写，SwiftUI 视图通过 `@ObservedObject` 订阅变化。
///
/// `onRetry` / `onOpenSettings` / `onTogglePin` / `onClose` 为动作回调，
/// **不**标注 `@Published`——它们不应触发 SwiftUI diff，只需要在主线程可读可写
/// 即可（类已 `@MainActor` 限定）。
@MainActor
final class ResultViewModel: ObservableObject {

    // MARK: - 流式状态机

    /// 流式输出的完整生命周期状态
    ///
    /// 状态转换：
    ///   - open()     → .thinking（请求已发，等待首字节）
    ///   - append()   → .streaming（首字节到达，持续流入）
    ///   - finish()   → .finished（流正常结束）
    ///   - fail(...)  → .error（流异常中止）
    enum StreamingState: Equatable {
        /// 刚创建，未开始请求（复用窗口时的初始态）
        case idle
        /// 请求已发出，等待 LLM 首字节响应
        case thinking
        /// 正在接收流式 delta，文本持续追加中
        case streaming
        /// 流正常结束，文本已完整展示
        case finished
        /// 流以错误结束，切换到错误态视图
        case error
    }

    /// 当前流式状态；驱动正文区域的视图切换
    @Published var streamingState: StreamingState = .idle

    /// 是否处于活跃流式输出中（thinking 或 streaming）；供 ProgressStripe 判断是否展示
    var isStreaming: Bool {
        streamingState == .thinking || streamingState == .streaming
    }

    // MARK: - 内容字段

    /// 当前工具名（标题栏主标题）
    @Published var toolName: String = ""
    /// 当前模型名（标题栏副文本）
    @Published var model: String = ""
    /// 已累积的 Markdown 文本；每次 append 都对现有字符串拼接
    @Published var text: String = ""
    /// 用户可见的错误信息；.error 态时展示在 ErrorBlock 的 message 字段
    @Published var errorMessage: String?
    /// 错误详情（开发者上下文）；供 ErrorBlock 的折叠区展示，已在 SliceError 层脱敏
    @Published var errorDetail: String?
    /// 是否钉住；同步自 ResultPanel.isPinned，用于切换 pin 按钮的图标
    @Published var isPinned: Bool = false
    /// 是否显示 thinking 切换按钮；仅当 Provider.thinking 非 nil 时为 true
    @Published var showThinkingToggle: Bool = false
    /// 当前 thinking 开关状态；与 tool.thinkingEnabled 同步
    @Published var thinkingEnabled: Bool = false
    /// 流式累积的 reasoning 文本（来自 chunk.reasoningDelta）
    @Published var accumulatedReasoning: String = ""
    /// reasoning DisclosureGroup 展开状态；每次 open 时重置为折叠
    @Published var reasoningExpanded: Bool = false

    // MARK: - 动作回调

    /// "重试"动作回调；nil 表示当前错误不支持重试
    var onRetry: (@MainActor () -> Void)?
    /// "打开设置"动作回调；nil 表示当前错误不需要跳设置
    var onOpenSettings: (@MainActor () -> Void)?
    /// "钉/取消钉"切换回调；由 ResultPanel 在每次 open 时绑定
    var onTogglePin: (@MainActor () -> Void)?
    /// "关闭窗口"回调；由 ResultPanel 在每次 open 时绑定
    var onClose: (@MainActor () -> Void)?
    /// "复制"回调；由 ResultPanel.open 绑定，复制当前 text 到 NSPasteboard
    var onCopy: (@MainActor () -> Void)?
    /// "重新生成"回调；由调用方（AppDelegate）提供，重新触发同一 tool + payload
    var onRegenerate: (@MainActor () -> Void)?
    /// "切换思考模式"回调；由调用方（AppDelegate）提供；nil 时按钮不显示
    var onToggleThinking: (@MainActor () -> Void)?

    // MARK: - 状态切换方法

    /// 重置视图状态为"新一次对话开始"
    ///
    /// - 状态切至 .thinking：请求已发，等待首字节
    /// - 清空上次文本与错误信息，避免旧内容闪烁
    ///
    /// 注意：onTogglePin / onClose / onCopy / onRegenerate 由 `ResultPanel.open(...)` 在 reset 后绑定，
    /// 这里不要清掉，否则按钮会失去响应；但 reset 时需清空旧 closure 避免残留上一次引用
    func reset(toolName: String, model: String) {
        // 基本字段：标题 + 模型 + 清空上次文本
        self.toolName = toolName
        self.model = model
        self.text = ""
        // 请求已发、等待首字节 → thinking 态
        self.streamingState = .thinking
        // 错误相关字段全部清空，避免上次错误残留
        self.errorMessage = nil
        self.errorDetail = nil
        // 恢复动作清掉，防止误触发上一次的 closure
        self.onRetry = nil
        self.onOpenSettings = nil
        // 复制与重新生成也清空，由 open() 重新绑定
        self.onCopy = nil
        self.onRegenerate = nil
        // thinking 相关：清空 reasoning 文本，折叠 DisclosureGroup
        // showThinkingToggle / thinkingEnabled / onToggleThinking 由 open() 重新绑定
        self.accumulatedReasoning = ""
        self.reasoningExpanded = false
    }

    /// 拼接一段流式 delta 到现有文本，并可选累积 reasoning 内容
    ///
    /// 首次调用（thinking → streaming）时自动切换状态，让 UI 从加载态切至渲染态。
    /// reasoning delta 来自 ChatChunk.reasoningDelta，仅在非 nil 时才累积到 accumulatedReasoning。
    func append(delta: String, reasoningDelta: String? = nil) {
        // 收到首字节时从 thinking 切到 streaming
        // 注意：仅有 reasoning delta 而 delta="" 时同样切换状态（reasoning 先于正文到达）
        let hasContent = !delta.isEmpty || reasoningDelta != nil
        if streamingState == .thinking, hasContent {
            streamingState = .streaming
        }
        if !delta.isEmpty {
            text += delta
        }
        // 累积 reasoning 文本；非思考模型此字段始终为 nil，不影响正常流程
        if let reasoning = reasoningDelta {
            accumulatedReasoning += reasoning
        }
    }

    /// 标记流正常结束，隐藏 ProgressStripe 和闪烁光标
    func finish() {
        streamingState = .finished
    }

    /// 标记流失败；切到错误态并写入错误信息与恢复动作
    /// - Parameters:
    ///   - message: 面向用户的错误摘要（ErrorBlock.message）
    ///   - detail: 开发者上下文（折叠详情），调用方需保证已脱敏
    ///   - onRetry: 可选重试回调
    ///   - onOpenSettings: 可选打开设置回调
    func fail(
        message: String,
        detail: String,
        onRetry: (@MainActor () -> Void)?,
        onOpenSettings: (@MainActor () -> Void)?
    ) {
        // 切到错误态，隐藏 ProgressStripe
        self.streamingState = .error
        self.errorMessage = message
        self.errorDetail = detail
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }
}

// ResultContent 和 DragAreaHost 已提取到 ResultContentView.swift，保持文件行数在 SwiftLint 限制内
