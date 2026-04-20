// SliceAIKit/Sources/Windowing/StreamingMarkdownView.swift
import SwiftUI

/// 流式 Markdown 文本视图
///
/// MVP 使用 SwiftUI 原生 `AttributedString(markdown:)` 解析（轻量、零依赖）；
/// 若未来需要代码块 / 表格等完整 Markdown 支持，可在 v0.2 替换成 swift-markdown-ui。
/// 解析选项为 `.inlineOnlyPreservingWhitespace`，保留换行，但不把 `# Heading` / `- list`
/// 提升为块级元素——这符合流式片段边拼接边渲染的场景（避免半行误判）。
public struct StreamingMarkdownView: View {
    /// 当前需要渲染的累积文本（每次追加 delta 后由父视图传入完整串）
    public let text: String
    /// 是否仍在流式输出中：为 true 时在文本末尾显示闪烁光标
    public let isStreaming: Bool

    /// 创建一个流式 Markdown 视图
    /// - Parameters:
    ///   - text: 待渲染的完整 Markdown 字符串
    ///   - isStreaming: 是否处于流式输出状态；true 会追加一个闪烁光标
    public init(text: String, isStreaming: Bool) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // 优先尝试 Markdown 解析；解析失败（如 delta 尾部有未闭合的 `**`）时回退为纯文本
                if let attr = try? AttributedString(
                    markdown: text,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    )
                ) {
                    Text(attr)
                        .textSelection(.enabled)
                        .foregroundColor(PanelColors.text)
                        .font(.system(size: 14))
                } else {
                    Text(text)
                        .textSelection(.enabled)
                        .foregroundColor(PanelColors.text)
                        .font(.system(size: 14))
                }
                if isStreaming {
                    BlinkingCursor()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

/// 流式输出期间显示在文本末尾的闪烁光标
///
/// 使用 `Task` + `Task.sleep` 驱动闪烁，避免 `Timer.scheduledTimer` 在 Swift 6
/// 严格并发下对 `@Sendable` 捕获的约束问题；视图消失时自动取消任务，无资源泄漏。
private struct BlinkingCursor: View {
    /// 当前是否可见；由后台 Task 每 500ms 翻转一次
    @State private var visible = true
    /// 驱动闪烁的异步任务，持有以便 onDisappear 时取消
    @State private var blinker: Task<Void, Never>?

    var body: some View {
        Rectangle()
            .frame(width: 7, height: 14)
            .foregroundColor(PanelColors.accent)
            .opacity(visible ? 1 : 0)
            .onAppear {
                // 避免重复 appear 时开多个 Task（如 SwiftUI 快速重绘）
                blinker?.cancel()
                blinker = Task { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        visible.toggle()
                    }
                }
            }
            .onDisappear {
                blinker?.cancel()
                blinker = nil
            }
    }
}
