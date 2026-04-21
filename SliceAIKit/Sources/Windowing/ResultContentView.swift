// SliceAIKit/Sources/Windowing/ResultContentView.swift
import AppKit
import DesignSystem
import SwiftUI

/// 结果窗内部视图：顶栏（pin 圆点 + 标题 + 模型 Chip + 4 按钮）+ 正文（Markdown 或错误）+ 底部操作区
///
/// 与 `ResultPanel` 分离：Panel 负责 NSPanel 生命周期与 pin/dismiss 状态，
/// 此 View 只负责纯 SwiftUI 渲染，两者通过 `ResultViewModel` 通信。
struct ResultContent: View {
    @ObservedObject var viewModel: ResultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            // 正文区域：错误优先、否则渲染流式 Markdown
            if let err = viewModel.errorMessage {
                errorStateView(message: err)
            } else {
                StreamingMarkdownView(text: viewModel.text, isStreaming: viewModel.isStreaming)
            }
            Divider()
            // 底部操作区：错误态展示 [复制错误详情]/[打开设置]/[重试]；正常态仅"复制"
            bottomBar()
                .padding(10)
        }
        .background(PanelColors.background)
        .foregroundColor(PanelColors.text)
        .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cornerRadius))
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

    /// 错误状态主视图：红色 banner + 折叠详情区
    /// - Parameter message: 用户可见的错误摘要（来自 `SliceError.userMessage`）
    @ViewBuilder
    private func errorStateView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .padding(.top, 2)
                Text(message)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let detail = viewModel.errorDetail, !detail.isEmpty {
                DisclosureGroup(
                    isExpanded: $viewModel.showDetail,
                    content: {
                        ScrollView {
                            Text(detail)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 120)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    },
                    label: { Text("错误详情").font(.caption) }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 底部操作栏：错误态 vs. 正常态两套按钮
    @ViewBuilder
    private func bottomBar() -> some View {
        HStack(spacing: 8) {
            if viewModel.errorMessage != nil {
                Button("复制错误详情") {
                    let text = [viewModel.errorMessage, viewModel.errorDetail]
                        .compactMap { $0 }
                        .joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                if let open = viewModel.onOpenSettings {
                    Button("打开设置") { open() }
                }
                Spacer()
                if let retry = viewModel.onRetry {
                    Button("重试") { retry() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.text, forType: .string)
                }
                Spacer()
            }
        }
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
