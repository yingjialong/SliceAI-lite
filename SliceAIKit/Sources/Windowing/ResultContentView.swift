// SliceAIKit/Sources/Windowing/ResultContentView.swift
import AppKit
import DesignSystem
import SwiftUI

/// 结果窗内部视图：顶栏（pin 圆点 + 标题 + 模型 Chip + 4 按钮）+ ProgressStripe + 正文
///
/// 与 `ResultPanel` 分离：Panel 负责 NSPanel 生命周期与 pin/dismiss 状态，
/// 此 View 只负责纯 SwiftUI 渲染，两者通过 `ResultViewModel` 通信。
///
/// 正文区域根据 `streamingState` 切换三种视图：
///   - .idle / .thinking → ThinkingDots 居中等待态
///   - .streaming / .finished → StreamingMarkdownView 流式渲染
///   - .error → ScrollView + ErrorBlock 错误态（含重试/设置按钮）
struct ResultContent: View {
    @ObservedObject var viewModel: ResultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            // 标题与正文之间的流式进度条 / 静态分隔线
            // streaming 期间展示滑动光条，结束后换为 1.5pt 静态分隔线避免布局跳动
            if viewModel.isStreaming {
                ProgressStripe()
            } else {
                Divider()
                    .background(SliceColor.divider)
                    .frame(height: 1.5)
            }

            // 正文区域：根据 streamingState 切换视图
            contentArea
        }
        .glassBackground(.hud, cornerRadius: SliceRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: SliceRadius.card)
                .stroke(SliceColor.border, lineWidth: 0.5)
        )
        .foregroundColor(SliceColor.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: SliceRadius.card))
    }

    /// 正文区域：根据 streamingState 切换三种视图
    ///
    /// - .idle / .thinking：ThinkingDots 居中展示等待动效
    /// - .streaming / .finished：StreamingMarkdownView 渲染累积文本
    /// - .error：ScrollView 包裹 ErrorBlock，挂载重试 / 设置按钮
    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.streamingState {
        case .idle, .thinking:
            // 等待首字节：居中展示脉动小点
            ThinkingDots()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, SliceSpacing.xxl)
                .padding(.vertical, SliceSpacing.xl)

        case .streaming, .finished:
            // 流式渲染：isStreaming = true 时 StreamingMarkdownView 会追加闪烁光标
            // 若有 reasoning 文本，先渲染折叠的"思考过程"，再渲染正文
            VStack(alignment: .leading, spacing: 0) {
                reasoningDisclosure
                StreamingMarkdownView(
                    text: viewModel.text,
                    isStreaming: viewModel.streamingState == .streaming
                )
            }

        case .error:
            // 错误态：用 ErrorBlock 展示错误信息 + 可选重试/设置按钮
            // @MainActor 闭包转换为 @Sendable：通过 Task { @MainActor in } 桥接跳回主线程
            ScrollView {
                ErrorBlock(
                    title: "请求失败",
                    message: viewModel.errorMessage ?? "未知错误",
                    detail: viewModel.errorDetail,
                    onRetry: viewModel.onRetry.map { retry in
                        { @Sendable in Task { @MainActor in retry() } }
                    },
                    onOpenSettings: viewModel.onOpenSettings.map { open in
                        { @Sendable in Task { @MainActor in open() } }
                    }
                )
                .padding(SliceSpacing.xxl)
            }
        }
    }

    /// 思考过程折叠区：仅当 thinking 已启用 + 有 reasoning 文本时渲染
    ///
    /// 双重守卫的原因：
    ///   - `thinkingEnabled` 守卫：DeepSeek V4 即便收到 disable 模板（thinking.type=disabled）
    ///     仍可能回传 reasoning_content 字段，UI 层尊重用户偏好直接不显示
    ///   - `!isEmpty` 守卫：按需渲染，避免空 disclosure 占位
    /// DisclosureGroup 绑定到 viewModel.reasoningExpanded，每次新流式任务由 reset() 折叠。
    @ViewBuilder
    private var reasoningDisclosure: some View {
        if viewModel.thinkingEnabled && !viewModel.accumulatedReasoning.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { viewModel.reasoningExpanded },
                set: { viewModel.reasoningExpanded = $0 }
            )) {
                ScrollView {
                    Text(viewModel.accumulatedReasoning)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SliceSpacing.sm)
                }
                .frame(maxHeight: 150)
            } label: {
                HStack {
                    Text("思考过程")
                        .font(SliceFont.captionEmphasis)
                        .foregroundColor(SliceColor.textSecondary)
                    Spacer()
                }
            }
            .padding(.horizontal, SliceSpacing.xl)
            .padding(.top, SliceSpacing.base)
            .padding(.bottom, SliceSpacing.xs)
        }
    }

    /// 顶栏：左侧 pin 圆点 + 工具名 + 模型 Chip / 右侧 4 个 IconButton
    ///
    /// header 空白区通过 DragAreaHost（NSView.performDrag）实现拖动，
    /// 不依赖 `isMovableByWindowBackground = true`。
    private var headerBar: some View {
        HStack(spacing: SliceSpacing.base) {
            // pin 激活时显示 5pt 品牌紫圆点
            if viewModel.isPinned {
                Circle()
                    .fill(SliceColor.accent)
                    .frame(width: 5, height: 5)
            }
            Text(viewModel.toolName)
                .font(SliceFont.bodyEmphasis)
                .kerning(SliceKerning.snug)
                .foregroundColor(SliceColor.textPrimary)
            Chip(viewModel.model, style: .neutral)
            Spacer()
            // 复制：把当前 text 写入系统剪贴板
            IconButton(systemName: "doc.on.doc", size: .small, help: "复制") {
                viewModel.onCopy?()
            }
            // 重新生成：cancel 旧 stream 并重新触发同一 tool + payload
            IconButton(systemName: "arrow.clockwise", size: .small, help: "重新生成") {
                viewModel.onRegenerate?()
            }
            // thinking 切换：仅当 provider 支持 thinking 切换时显示（showThinkingToggle=true）
            // 单图标 + isActive 控制亮/暗：thinking ON 时品牌色高亮，OFF 时与其他控件同灰度
            // 不再做 brain.head.profile <-> brain 的两图标切换——视觉差异太弱、用户难以区分
            if viewModel.showThinkingToggle {
                IconButton(
                    systemName: "brain",
                    size: .small,
                    isActive: viewModel.thinkingEnabled,
                    help: viewModel.thinkingEnabled ? "切换为非思考模式" : "切换为思考模式"
                ) {
                    viewModel.onToggleThinking?()
                }
            }
            // pin：切换 statusBar/floating level + outside-click 监视器
            IconButton(
                systemName: viewModel.isPinned ? "pin.fill" : "pin",
                size: .small,
                isActive: viewModel.isPinned,
                help: viewModel.isPinned ? "取消钉住" : "钉住窗口"
            ) {
                viewModel.onTogglePin?()
            }
            // 关闭：dismiss → onDismiss → cancel stream task
            IconButton(systemName: "xmark", size: .small, help: "关闭") {
                viewModel.onClose?()
            }
        }
        .padding(.horizontal, SliceSpacing.xl)
        .padding(.top, SliceSpacing.lg)
        .padding(.bottom, SliceSpacing.base)
        .background(DragAreaHost())
    }

}

/// 标题栏拖拽宿主：桥接 NSView.performDrag 使 SwiftUI header 空白区可拖动 NSPanel
///
/// 原理：`.background(DragAreaHost())` 铺满 header；用户在按钮以外区域按下鼠标时，
/// `DragArea.mouseDown` 调用 `window?.performDrag`，系统接管窗口拖动。
struct DragAreaHost: NSViewRepresentable {
    /// 创建底层 NSView
    func makeNSView(context: Context) -> DragArea { DragArea() }
    /// 无状态，无需更新
    func updateNSView(_ nsView: DragArea, context: Context) {}

    /// 桥接拖拽的 NSView 子类
    final class DragArea: NSView {
        /// 转发 mouseDown 给窗口，触发系统拖动
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        /// 返回 self 确保命中测试不穿透到父视图链
        override func hitTest(_ point: NSPoint) -> NSView? { self }
    }
}
