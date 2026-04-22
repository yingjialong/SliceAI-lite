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
    ///   - maxTools: 工具栏最多直接展示的工具按钮个数（**不含**溢出时额外追加的「⋯ 更多」按钮），下限 2 上限 20
    ///   - size: 工具栏尺寸档位（.compact 22pt / .regular 30pt），默认 compact
    ///   - onPick: 用户点击某工具时回调
    ///
    /// 尺寸计算策略：因为 `labelStyle == .name / .iconAndName` 的按钮宽度取决于
    /// 具体文字长度，panel 尺寸无法纯靠预计算公式给出。流程改为：
    ///   1. 先用最小占位尺寸建出 NSPanel（因 content 闭包要引用 panel 做 performDrag）
    ///   2. 创建 SwiftUI content；用 `NSHostingView.fittingSize` 测量实际需要的像素
    ///   3. 依据测量尺寸重新算 origin（让 panel 贴近选区又不超屏），再 `setFrame`
    ///      到正确 size + origin；测量失败（返回 0 或 NaN）时退回老式公式作为兜底
    public func show(
        tools: [Tool],
        anchor: CGPoint,
        maxTools: Int = 6,
        size: ToolbarSize = .compact,
        onPick: @escaping (Tool) -> Void
    ) {
        print("[FloatingToolbarPanel] show tools=\(tools.count) maxTools=\(maxTools) size=\(size.rawValue)")
        let split = splitTools(tools, maxTools: maxTools)
        let metrics = ToolbarMetrics(size: size)

        // 1. 用占位尺寸创建 panel——正式尺寸测量后用 setFrame 修正
        let placeholderSize = computeToolbarSize(itemCount: split.itemCount, metrics: metrics)
        let panel = makePanel(size: placeholderSize, origin: anchor)
        let content = makeToolbarContent(split: split, metrics: metrics, panel: panel, onPick: onPick)

        // 2. NSHostingView 测量真实尺寸
        let hosting = NSHostingView(rootView: content)
        hosting.layoutSubtreeIfNeeded()
        let measured = hosting.fittingSize
        let panelSize: CGSize = (measured.width > 0 && measured.height > 0)
            ? measured
            : placeholderSize
        // 3. 根据真实 size 重算 origin，setFrame 修正 panel
        let origin = computeOrigin(anchor: anchor, size: panelSize)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
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

    /// 工具栏尺寸档位对应的具体像素值
    ///
    /// 把配置枚举（ToolbarSize）解耦为布局计算需要的所有像素参数，
    /// 使 show() 逻辑不直接依赖 enum 的 rawValue 做分支
    struct ToolbarMetrics {
        /// 按钮边长（正方形；iconOnly 样式下宽 = 高 = buttonSize）
        let buttonSize: CGFloat
        /// IconButton size 枚举（用于 iconOnly 样式）
        let iconButtonSize: IconButton.Size
        /// 图标字号（emoji Text / SF Symbol 共用）
        let iconFontSize: CGFloat
        /// 带文字按钮的 label 字号
        let labelFontSize: CGFloat
        /// 工具栏外 padding
        let padding: CGFloat
        /// 按钮之间的水平间距
        let buttonSpacing: CGFloat
        /// 更多按钮字体大小
        let moreFontSize: CGFloat

        init(size: ToolbarSize) {
            switch size {
            case .compact:
                self.buttonSize = 22
                self.iconButtonSize = .small
                self.iconFontSize = 12
                self.labelFontSize = 11
                self.padding = 3
                self.buttonSpacing = 2
                self.moreFontSize = 12
            case .regular:
                self.buttonSize = 30
                self.iconButtonSize = .regular
                self.iconFontSize = 15
                self.labelFontSize = 13
                self.padding = 4
                self.buttonSpacing = 2
                self.moreFontSize = 15
            }
        }
    }

    /// 按 maxTools 把工具切分为"直接展示"和"折叠到更多菜单"两部分
    ///
    /// 语义：`maxTools` 指"最多展示多少个工具按钮"，**不含**溢出状态下额外追加的
    /// 「⋯ 更多」按钮。因此当 tools.count > maxTools 时，前 maxTools 个工具直接
    /// 渲染，其余折叠到更多菜单，再在右侧额外放置一个「更多」按钮（itemCount +1）。
    private func splitTools(_ tools: [Tool], maxTools: Int) -> ToolSplit {
        let clampedMax = max(2, min(20, maxTools))
        let hasOverflow = tools.count > clampedMax
        let direct = hasOverflow ? Array(tools.prefix(clampedMax)) : tools
        let overflow = hasOverflow ? Array(tools.dropFirst(clampedMax)) : []
        let itemCount = direct.count + (hasOverflow ? 1 : 0)
        return ToolSplit(direct: direct, overflow: overflow, itemCount: itemCount)
    }

    /// 占位 panel 尺寸（仅用于初始创建；真实 size 由 NSHostingView.fittingSize 测量后 setFrame 覆盖）
    ///
    /// 把手(14pt) + 分隔线(1pt + 3pt×2 padding) = 21pt；HStack 共 itemCount+1 项，
    /// 间距数量 itemCount；每按钮 metrics.buttonSize + metrics.buttonSpacing + 左右 padding×2。
    /// iconOnly 情况下该公式给出的尺寸即为实际尺寸；包含文字样式时仅作兜底使用。
    private func computeToolbarSize(itemCount: Int, metrics: ToolbarMetrics) -> CGSize {
        let handleWidth: CGFloat = 14 + 7
        let buttonsWidth = CGFloat(itemCount) * (metrics.buttonSize + metrics.buttonSpacing)
        let width = handleWidth + buttonsWidth + metrics.padding * 2
        let height: CGFloat = metrics.buttonSize + metrics.padding * 2
        // 紧凑模式下 minWidth 也相应缩小，保证视觉平衡
        let minWidth: CGFloat = metrics.buttonSize == 22 ? 90 : 120
        return CGSize(width: max(width, minWidth), height: height)
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
        metrics: ToolbarMetrics,
        panel: NSPanel,
        onPick: @escaping (Tool) -> Void
    ) -> ToolbarContent {
        ToolbarContent(
            directTools: split.direct,
            overflowTools: split.overflow,
            metrics: metrics,
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
// 文本截断工具（ToolbarLabelFormat）与带文字按钮（ToolbarItemButton）
// 定义在同目录的 FloatingToolbarPanel+Buttons.swift，仅为控制本文件行数。

/// 浮条内部的 SwiftUI 视图：左侧拖拽把手 + 一排可点击的工具按钮 + 可选"更多"菜单
private struct ToolbarContent: View {
    /// 直接显示为按钮的工具列表
    let directTools: [Tool]
    /// 折叠进"更多"菜单的工具列表；为空时不渲染更多按钮
    let overflowTools: [Tool]
    /// 尺寸档位对应的像素参数
    let metrics: FloatingToolbarPanel.ToolbarMetrics
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
        HStack(spacing: metrics.buttonSpacing) {
            // MARK: 拖拽把手区
            DragHandle(isDragging: isDragging)
                .overlay(
                    DragGestureHost { event, phase in
                        switch phase {
                        case .began:
                            isDragging = true
                            pauseAutoDismiss()
                            requestDrag(event)
                        case .ended:
                            isDragging = false
                            resumeAutoDismiss()
                        }
                    }
                )

            // MARK: 工具按钮列表
            // 每两个工具之间插入竖分隔线（与 DragHandle 右侧分隔线同规格：1×16pt divider），
            // 让多按钮时视觉分隔清晰，尤其在 iconAndName 模式下文字按钮比较密。
            //
            // 用 indices 驱动 ForEach 是为了让 `if index > 0` 判断直接内联（对比
            // enumerated() 在复杂 switch 下更不易触发 Swift type-checker 超时）。
            ForEach(directTools.indices, id: \.self) { index in
                if index > 0 {
                    toolDivider
                }
                toolButton(for: directTools[index])
            }

            // MARK: 溢出"更多"按钮
            // 前方同样加一条分隔线（若 directTools 非空）——视觉上把工具栏分成
            // "工具区" 与 "扩展区"两段。
            if !overflowTools.isEmpty {
                if !directTools.isEmpty {
                    toolDivider
                }
                overflowMenu
            }
        }
        .padding(metrics.padding)
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

    /// 工具按钮间的竖向分隔线，规格与左侧 DragHandle 的分隔线一致（1×16pt + divider 色）
    private var toolDivider: some View {
        Rectangle()
            .fill(SliceColor.divider)
            .frame(width: 1, height: 16)
    }

    /// 按 tool.labelStyle 分发到三种渲染：
    ///   - .icon        → 复用 DesignSystem 的 IconButton
    ///   - .name        → ToolbarItemButton 仅文字
    ///   - .iconAndName → ToolbarItemButton 图标+文字
    /// 拆为独立函数避免 ForEach body 内 switch 嵌套太深触发类型推导超时
    @ViewBuilder
    private func toolButton(for tool: Tool) -> some View {
        switch tool.labelStyle {
        case .icon:
            IconButton(text: tool.icon, size: metrics.iconButtonSize, help: tool.name) {
                onPick(tool)
            }
        case .name:
            ToolbarItemButton(
                icon: nil,
                label: ToolbarLabelFormat.shorten(tool.name),
                metrics: metrics,
                help: tool.name
            ) { onPick(tool) }
        case .iconAndName:
            ToolbarItemButton(
                icon: tool.icon,
                label: ToolbarLabelFormat.shorten(tool.name),
                metrics: metrics,
                help: tool.name
            ) { onPick(tool) }
        }
    }

    /// "更多"溢出菜单：样式模拟 IconButton，点击弹出系统 NSMenu 列出折叠工具
    private var overflowMenu: some View {
        Menu {
            ForEach(overflowTools) { tool in
                Button {
                    onPick(tool)
                } label: {
                    Label(tool.name, systemImage: isSFSymbol(tool.icon) ? tool.icon : "hammer")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: metrics.moreFontSize, weight: .medium))
                .foregroundColor(SliceColor.textSecondary)
                .frame(width: metrics.buttonSize, height: metrics.buttonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多工具（\(overflowTools.count)）")
    }

    /// 启发式判定 icon 是否为 SF Symbol 名（首字符为 ASCII 即视为 symbol）
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
