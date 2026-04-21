// SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift
import AppKit
import DesignSystem
import SliceCore
import SwiftUI

/// 划词后弹出的紧贴选区浮条（A 模式）· 美化版
///
/// 职责：根据选区中心点 `anchor`，在屏幕合适位置展示一排工具图标；
/// 用户点击工具或 5 秒无交互后自动关闭；左侧拖拽把手支持整窗移动。
/// 线程模型：整个类在主 actor 上运行，避免 `NSPanel` / `NSHostingView` 跨线程访问。
@MainActor
public final class FloatingToolbarPanel {

    /// 当前承载浮条的 NSPanel，dismiss 后置 nil
    private var panel: NSPanel?

    /// 屏幕边界感知的坐标计算器（无状态，可复用）
    private let positioner = ScreenAwarePositioner()

    /// 5 秒自动关闭任务，每次 show 都会取消旧任务重新计时；
    /// 拖动期间暂停，松手后恢复。
    private var autoDismissTask: Task<Void, Never>?

    /// 全局 mouseDown 监视器：实现"点 panel 外部即消失"的 PopClip 标准交互
    ///
    /// 关键不变量：`NSEvent.addGlobalMonitorForEvents` 不接收本进程内窗口产生
    /// 的事件。所以点 panel 内的工具按钮、拖动 panel 都不会触发该 monitor，
    /// 只有点击其他 App / 桌面 / 本 App 其他窗口时才会触发 → 直接 dismiss。
    private var outsideClickMonitor: Any?

    /// 无状态构造器
    public init() {}

    // MARK: - 公开接口

    /// 显示浮条
    ///
    /// - Parameters:
    ///   - tools: 要展示的工具列表（按顺序从左至右）
    ///   - anchor: 选区中心（屏幕坐标，左下原点）
    ///   - onPick: 用户点击某工具时回调
    public func show(tools: [Tool], anchor: CGPoint, onPick: @escaping (Tool) -> Void) {
        // 宽度计算：把手(14pt) + 分隔线(1pt + 3pt×2 padding) = 21pt
        // 每个按钮 30pt + 按钮间距 2pt + 左右 padding 4pt×2
        let handleWidth: CGFloat = 14 + 7  // 把手 + 分隔线区域宽度
        let buttonsWidth = CGFloat(tools.count) * 30 + CGFloat(max(0, tools.count - 1)) * 2
        let padding: CGFloat = 4
        let width = handleWidth + buttonsWidth + padding * 2
        let height: CGFloat = 30 + padding * 2  // 按钮高度 + 上下 padding
        let size = CGSize(width: max(width, 120), height: height)

        // 选锚点所在屏幕，fallback 到主屏；再 fallback 到零矩形避免 nil
        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.contains(anchor)
        })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 通过 positioner 计算 origin：默认锚点下方 8px，越界时翻到上方并水平夹紧
        let origin = positioner.position(anchor: anchor, size: size, screen: screen, offset: 8)

        // 构造 NSPanel
        let panel = makePanel(size: size, origin: origin)

        // 构造 SwiftUI 内容视图，注入拖拽、暂停/恢复计时器的回调
        let content = ToolbarContent(
            tools: tools,
            onPick: { [weak self] tool in
                // 点击工具后先回调业务方，再关闭浮条，避免回调中再次读取已失效状态
                onPick(tool)
                self?.dismiss()
            },
            pauseAutoDismiss: { [weak self] in
                // 拖动开始时暂停自动关闭
                self?.autoDismissTask?.cancel()
            },
            resumeAutoDismiss: { [weak self] in
                // 拖动结束时重新启动计时
                self?.scheduleAutoDismiss()
            },
            requestDrag: { [weak panel] event in
                // 将 mouseDown 事件转交 NSWindow 实现整窗拖动
                panel?.performDrag(with: event)
            }
        )

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        // 启动 5 秒自动关闭
        scheduleAutoDismiss()
        // 安装外部点击监视器，实现"点 panel 外部即消失"
        installOutsideClickMonitor()
    }

    /// 立即关闭浮条并清理状态
    public func dismiss() {
        autoDismissTask?.cancel()
        removeOutsideClickMonitor()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - 私有方法

    /// 启动（或重启）5 秒后自动关闭的 Task
    ///
    /// 使用 @MainActor Task 直接调用 dismiss()，避免嵌套 MainActor.run（Swift 6 推荐写法）
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// 安装全局 mouseDown 监视器；任何 panel 外的点击都会触发 dismiss
    ///
    /// global monitor 回调签名是 `@Sendable`，需显式 hop 回 MainActor 才能安全
    /// 调用 `dismiss()`。监听 left + right + other 三类按下，覆盖三键鼠标 / 触
    /// 控板的所有 click 来源。
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

    /// 创建无边框、悬浮于所有 Space 的 NSPanel，关键配置见注释
    private func makePanel(size: CGSize, origin: CGPoint) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        // 提升到 statusBar 层，避免被普通窗口挡住；同时不抢占焦点
        panel.level = .statusBar
        // canJoinAllSpaces：在任意 Space 都显示；fullScreenAuxiliary：在全屏应用上也可见
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        // 启用窗口拖动，但不允许背景拖动——仅通过把手区的 NSWindow.performDrag 实现
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        // 让 SwiftUI 的圆角背景和毛玻璃透出：设置透明底色 + 非不透明窗体
        panel.backgroundColor = .clear
        panel.isOpaque = false
        return panel
    }
}

// MARK: - SwiftUI 视图

/// 浮条内部的 SwiftUI 视图：左侧拖拽把手 + 一排可点击的工具图标按钮
private struct ToolbarContent: View {
    /// 要展示的工具列表
    let tools: [Tool]
    /// 工具点击回调
    let onPick: (Tool) -> Void
    /// 拖动开始时暂停自动关闭计时
    let pauseAutoDismiss: () -> Void
    /// 拖动结束时恢复自动关闭计时
    let resumeAutoDismiss: () -> Void
    /// 转发 mouseDown 事件给 NSWindow 实现整窗拖动
    let requestDrag: (NSEvent) -> Void

    /// 是否正在拖动（控制 DragHandle 的高亮配色）
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 2) {
            // MARK: 拖拽把手区
            // DragHandle 负责视觉（6点阵 + hover 游标切换），
            // DragGestureHost 负责捕获 mouseDown 并转发给 NSWindow.performDrag
            DragHandle(isDragging: isDragging)
                .background(
                    DragGestureHost { event, phase in
                        switch phase {
                        case .began:
                            // 拖动开始：更新状态、暂停自动关闭、转发拖动事件
                            isDragging = true
                            pauseAutoDismiss()
                            requestDrag(event)
                        case .ended:
                            // 拖动结束：恢复状态和自动关闭计时
                            isDragging = false
                            resumeAutoDismiss()
                        }
                    }
                )

            // MARK: 工具按钮列表
            // Tool 已实现 Identifiable（id: String），ForEach 可直接使用
            ForEach(tools) { tool in
                IconButton(text: tool.icon, size: .regular, help: tool.name) {
                    onPick(tool)
                }
            }
        }
        .padding(4)
        // 毛玻璃背景，材质 .hud 适合小型浮动面板
        .glassBackground(.hud, cornerRadius: SliceRadius.card)
        // 细边框描边，增强视觉边界感
        .overlay(
            RoundedRectangle(cornerRadius: SliceRadius.card)
                .stroke(SliceColor.border, lineWidth: 0.5)
        )
        // 两层阴影：主阴影提升层次感，接触阴影模拟贴近感
        .shadow(SliceShadow.hud)
        .shadow(SliceShadow.hudContact)
    }
}

// MARK: - NSViewRepresentable 桥接

/// 捕获 mouseDown 事件并转发给 NSWindow.performDrag 实现整窗拖动的桥接视图
///
/// SwiftUI 的 DragGesture 无法触发 NSWindow 级别的窗口移动，
/// 必须通过 NSView 直接接收 NSEvent 并调用 `window?.performDrag(with:)` 实现。
private struct DragGestureHost: NSViewRepresentable {
    /// 拖拽阶段枚举
    enum Phase {
        case began  // mouseDown 触发时
        case ended  // mouseDown 处理结束时
    }

    /// 拖拽事件回调：传入原始 NSEvent 和阶段
    let onDrag: (NSEvent, Phase) -> Void

    func makeNSView(context: Context) -> MouseCaptureView {
        let view = MouseCaptureView()
        view.onDrag = onDrag
        return view
    }

    func updateNSView(_ nsView: MouseCaptureView, context: Context) {
        nsView.onDrag = onDrag
    }

    /// 透明 NSView，专门用于捕获 mouseDown 事件
    final class MouseCaptureView: NSView {
        /// 外层注入的回调，注意回调在主线程 NSEvent 回调栈中执行
        var onDrag: ((NSEvent, Phase) -> Void)?

        override func mouseDown(with event: NSEvent) {
            // 通知外层拖动开始（外层调用 NSWindow.performDrag 会阻塞直到 mouseUp）
            onDrag?(event, .began)
            super.mouseDown(with: event)
            // performDrag 返回后，mouseUp 已发生，通知外层拖动结束
            onDrag?(event, .ended)
        }
    }
}
