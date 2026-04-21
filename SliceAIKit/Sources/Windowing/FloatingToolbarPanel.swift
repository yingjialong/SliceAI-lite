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
    ///   - tools: 要展示的工具列表（按顺序从左至右，超出 `maxTools` 的折叠到"更多"菜单）
    ///   - anchor: 选区中心（屏幕坐标，左下原点）
    ///   - maxTools: 工具栏最多显示多少个位置（含溢出位的"更多"按钮），下限 2 上限 20
    ///   - onPick: 用户点击某工具时回调
    public func show(
        tools: [Tool],
        anchor: CGPoint,
        maxTools: Int = 6,
        onPick: @escaping (Tool) -> Void
    ) {
        let split = splitTools(tools, maxTools: maxTools)
        let size = computeToolbarSize(itemCount: split.itemCount)
        let origin = computeOrigin(anchor: anchor, size: size)

        let panel = makePanel(size: size, origin: origin)
        let content = makeToolbarContent(split: split, panel: panel, onPick: onPick)

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

    // MARK: - 私有辅助

    /// 直接显示的工具 + 溢出的工具 + 渲染位数的组合
    private struct ToolSplit {
        let direct: [Tool]
        let overflow: [Tool]
        /// 实际渲染的"按钮位"数（含更多按钮位）
        let itemCount: Int
    }

    /// 按 maxTools 把工具切分为"直接展示"和"折叠到更多菜单"两部分
    ///
    /// maxTools 夹紧到 2...20；tools.count 超过此值时，最后 1 位让给"更多"按钮，
    /// 因此直接渲染的工具数 = clampedMax - 1，其余进入溢出列表。
    private func splitTools(_ tools: [Tool], maxTools: Int) -> ToolSplit {
        let clampedMax = max(2, min(20, maxTools))
        let hasOverflow = tools.count > clampedMax
        let direct = hasOverflow ? Array(tools.prefix(clampedMax - 1)) : tools
        let overflow = hasOverflow ? Array(tools.dropFirst(clampedMax - 1)) : []
        let itemCount = direct.count + (hasOverflow ? 1 : 0)
        return ToolSplit(direct: direct, overflow: overflow, itemCount: itemCount)
    }

    /// 计算工具栏窗口尺寸
    ///
    /// 把手(14pt) + 分隔线(1pt + 3pt×2 padding) = 21pt；HStack 共 itemCount+1 项，
    /// 间距数量 itemCount；每按钮 30pt + 间距 2pt + 左右 padding 4pt×2。
    private func computeToolbarSize(itemCount: Int) -> CGSize {
        let handleWidth: CGFloat = 14 + 7
        let buttonSpacing: CGFloat = 2
        let buttonsWidth = CGFloat(itemCount) * (30 + buttonSpacing)
        let padding: CGFloat = 4
        let width = handleWidth + buttonsWidth + padding * 2
        let height: CGFloat = 30 + padding * 2
        return CGSize(width: max(width, 120), height: height)
    }

    /// 计算工具栏窗口应放置的 origin（屏幕坐标，左下原点）
    ///
    /// 14pt 偏移比原 8pt 多一点空隙，避免浮条紧贴光标遮挡视线；越界时 positioner
    /// 会自动翻到上方并水平夹紧屏幕可见区域。
    private func computeOrigin(anchor: CGPoint, size: CGSize) -> CGPoint {
        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.contains(anchor)
        })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return positioner.position(anchor: anchor, size: size, screen: screen, offset: 14)
    }

    /// 构造 ToolbarContent SwiftUI 视图，绑定 onPick / 拖拽 / 暂停自关闭回调
    private func makeToolbarContent(
        split: ToolSplit,
        panel: NSPanel,
        onPick: @escaping (Tool) -> Void
    ) -> ToolbarContent {
        ToolbarContent(
            directTools: split.direct,
            overflowTools: split.overflow,
            onPick: { [weak self] tool in
                onPick(tool)
                self?.dismiss()
            },
            pauseAutoDismiss: { [weak self] in
                self?.autoDismissTask?.cancel()
            },
            resumeAutoDismiss: { [weak self] in
                self?.scheduleAutoDismiss()
            },
            requestDrag: { [weak panel] event in
                panel?.performDrag(with: event)
            }
        )
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

/// 浮条内部的 SwiftUI 视图：左侧拖拽把手 + 一排可点击的工具图标按钮 + 可选"更多"菜单
private struct ToolbarContent: View {
    /// 直接显示为按钮的工具列表
    let directTools: [Tool]
    /// 折叠进"更多"菜单的工具列表；为空时不渲染更多按钮
    let overflowTools: [Tool]
    /// 工具点击回调（含从更多菜单触发）
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
            //
            // 关键：这里用 .overlay 而不是 .background。DragHandle 内的 Canvas
            // 和分隔线是 SwiftUI 前景视图，会优先响应 hit-test，background 的
            // NSView 永远收不到 mouseDown；overlay 把 NSView 放在最上层，mouseDown
            // 先到 DragGestureHost，performDrag 才能被调用。onHover 不受影响
            // （hover 是独立的 tracking area 机制）。
            DragHandle(isDragging: isDragging)
                .overlay(
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
            ForEach(directTools) { tool in
                IconButton(text: tool.icon, size: .regular, help: tool.name) {
                    onPick(tool)
                }
            }

            // MARK: 溢出"更多"按钮
            // 仅当 overflowTools 非空时显示；点击弹出 NSMenu（SwiftUI Menu 底层实现）
            if !overflowTools.isEmpty {
                overflowMenu
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

    /// "更多"溢出菜单：样式模拟 IconButton，点击弹出系统 NSMenu 列出折叠工具
    private var overflowMenu: some View {
        Menu {
            ForEach(overflowTools) { tool in
                Button {
                    onPick(tool)
                } label: {
                    // menu item 左侧图标 + 右侧工具名；菜单项会继承系统菜单样式
                    Label(tool.name, systemImage: isSFSymbol(tool.icon) ? tool.icon : "hammer")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(SliceColor.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多工具（\(overflowTools.count)）")
    }

    /// 启发式判定 icon 是否为 SF Symbol 名（首字符为 ASCII 即视为 symbol）
    ///
    /// Menu Label 的 systemImage 参数必须是 SF Symbol 名，emoji 会渲染空白；
    /// 判定不通过时回退到通用 "hammer" 图标，工具真实 emoji 由工具名传达。
    private func isSFSymbol(_ icon: String) -> Bool {
        guard let scalar = icon.unicodeScalars.first else { return false }
        return scalar.isASCII
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
