// SliceAIKit/Sources/Windowing/StreamingMarkdownView.swift
import DesignSystem
import SwiftUI

/// 流式 Markdown 渲染视图
///
/// 解析策略（三级回退）：
/// 1. 自实现分段解析器：按行扫描出 paragraph / heading / codeBlock / quote / list
/// 2. 行内 `.inlineOnlyPreservingWhitespace`：保留换行，只做 **bold** / _italic_ / `code`
/// 3. 纯文本：全部当成原文
///
/// 为了处理 ```代码块``` 与 `> quote` 等块级元素，本实现采用**分段解析**：
/// 按行逐一扫描，归属到对应 Block 类型，这样不会因局部未闭合影响整体渲染。
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
            VStack(alignment: .leading, spacing: SliceSpacing.lg) {
                ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
                if isStreaming {
                    BlinkingCursor()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SliceSpacing.xxl)
            .padding(.vertical, SliceSpacing.xl)
        }
    }

    // MARK: - Block 分段解析

    /// 解析后的 Block 列表
    private var parsedBlocks: [Block] { parseBlocks(text) }

    /// Markdown 块级元素类型
    private enum Block {
        /// 普通段落（可含行内 markdown）
        case paragraph(String)
        /// 标题（level 1-4，payload 是标题文字）
        case heading(level: Int, content: String)
        /// 代码块（payload 是围栏内的原始代码）
        case codeBlock(String)
        /// 引用块（payload 是去掉 `> ` 前缀后的内容，含换行）
        case quote(String)
        /// 列表（每个 item 是去掉 `- `/`* ` 前缀后的文字）
        case list(items: [String])
    }

    /// 对原始文本按行扫描，返回有序 Block 列表
    ///
    /// 扫描规则（优先级从高到低）：
    /// 1. 行以 ``` 开头 → 收集至下一个 ``` 构成 codeBlock
    /// 2. 行以 `#` 开头且符合标题格式 → heading
    /// 3. 行以 `> ` 开头 → 连续收集构成 quote
    /// 4. 行以 `- ` 或 `* ` 开头 → 连续收集构成 list
    /// 5. 其余 → 连续非空行合并为 paragraph；空行作为段落分隔符
    private func parseBlocks(_ raw: String) -> [Block] {
        var result: [Block] = []
        let lines = raw.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            parseNextBlock(lines: lines, index: &index, into: &result)
        }
        return result
    }

    /// 从 lines[index] 开始解析下一个 Block，并将结果追加到 result；同时推进 index
    private func parseNextBlock(lines: [String], index: inout Int, into result: inout [Block]) {
        let currentLine = lines[index]
        let trimmed = currentLine.trimmingCharacters(in: .whitespaces)

        // 空行：跳过（作为段落分隔）
        if trimmed.isEmpty { index += 1; return }

        // 代码围栏：``` 开头，收集到下一个 ``` 为止
        if trimmed.hasPrefix("```") {
            result.append(parseCodeBlock(lines: lines, index: &index))
            return
        }
        // 标题：# / ## / ### / ####
        if let headingBlock = parseHeadingLine(currentLine) {
            result.append(headingBlock); index += 1; return
        }
        // 引用块：以 `> ` 开头，连续收集
        if currentLine.hasPrefix("> ") {
            result.append(parseQuoteBlock(lines: lines, index: &index, firstLine: currentLine))
            return
        }
        // 无序列表：以 `- ` 或 `* ` 开头，连续收集
        if currentLine.hasPrefix("- ") || currentLine.hasPrefix("* ") {
            result.append(parseListBlock(lines: lines, index: &index, firstLine: currentLine))
            return
        }
        // 普通段落
        if let para = parseParagraphBlock(lines: lines, index: &index, firstLine: currentLine) {
            result.append(para)
        }
    }

    /// 解析代码围栏块（调用时 lines[index] 已是开头 ```）
    private func parseCodeBlock(lines: [String], index: inout Int) -> Block {
        var codeLines: [String] = []
        index += 1
        while index < lines.count,
              !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            codeLines.append(lines[index])
            index += 1
        }
        if index < lines.count { index += 1 } // 跳过结尾 ```
        return .codeBlock(codeLines.joined(separator: "\n"))
    }

    /// 解析引用块（调用时 firstLine 已是第一行 `> ...`）
    private func parseQuoteBlock(lines: [String], index: inout Int, firstLine: String) -> Block {
        var quoteLines = [String(firstLine.dropFirst(2))]
        index += 1
        while index < lines.count, lines[index].hasPrefix("> ") {
            quoteLines.append(String(lines[index].dropFirst(2)))
            index += 1
        }
        return .quote(quoteLines.joined(separator: "\n"))
    }

    /// 解析无序列表块（调用时 firstLine 已是第一个 `- ...` 或 `* ...`）
    private func parseListBlock(lines: [String], index: inout Int, firstLine: String) -> Block {
        var listItems = [String(firstLine.dropFirst(2))]
        index += 1
        while index < lines.count,
              lines[index].hasPrefix("- ") || lines[index].hasPrefix("* ") {
            listItems.append(String(lines[index].dropFirst(2)))
            index += 1
        }
        return .list(items: listItems)
    }

    /// 解析普通段落块；内容为空时返回 nil
    private func parseParagraphBlock(lines: [String], index: inout Int, firstLine: String) -> Block? {
        var paraLines = [firstLine]
        index += 1
        while index < lines.count,
              !lines[index].isEmpty,
              !hasSpecialPrefix(lines[index]) {
            paraLines.append(lines[index])
            index += 1
        }
        let paraText = paraLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        return paraText.isEmpty ? nil : .paragraph(paraText)
    }

    /// 判断某行是否以特殊块级前缀开头（用于段落收集时的终止判断）
    private func hasSpecialPrefix(_ line: String) -> Bool {
        line.hasPrefix("#") ||
        line.hasPrefix("> ") ||
        line.hasPrefix("- ") ||
        line.hasPrefix("* ") ||
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    /// 尝试将一行解析为标题 Block；不匹配时返回 nil
    ///
    /// 合法格式：1-4 个 `#` 后紧跟一个空格，e.g. `## 小节标题`
    private func parseHeadingLine(_ line: String) -> Block? {
        var level = 0
        var remaining = line
        while remaining.hasPrefix("#") {
            level += 1
            remaining.removeFirst()
        }
        guard level >= 1, level <= 4, remaining.hasPrefix(" ") else { return nil }
        let headingText = String(remaining.dropFirst())
        return .heading(level: level, content: headingText)
    }

    // MARK: - 渲染

    /// 根据 Block 类型路由到对应的渲染方法
    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .paragraph(let content):   renderParagraph(content)
        case .heading(let lvl, let content): renderHeading(level: lvl, content: content)
        case .codeBlock(let code):      renderCodeBlock(code)
        case .quote(let content):       renderQuote(content)
        case .list(let items):          renderList(items)
        }
    }

    /// 普通段落：行内 markdown 渲染
    @ViewBuilder
    private func renderParagraph(_ content: String) -> some View {
        inlineText(content)
            .font(SliceFont.body)
            .kerning(SliceKerning.normal)
            .lineSpacing(SliceLineSpacing.body)
            .foregroundColor(SliceColor.textPrimary)
    }

    /// 标题：按 level 选字号，level 1/2 顶部加额外间距
    @ViewBuilder
    private func renderHeading(level: Int, content: String) -> some View {
        Text(content)
            .font(.system(size: headingFontSize(level), weight: .bold))
            .kerning(SliceKerning.snug)
            .foregroundColor(SliceColor.textPrimary)
            .padding(.top, level <= 2 ? SliceSpacing.base : SliceSpacing.sm)
    }

    /// 代码块：等宽字体 + 灰底圆角 + 横向滚动（防止长行溢出）
    @ViewBuilder
    private func renderCodeBlock(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(SliceFont.mono)
                .lineSpacing(SliceLineSpacing.code)
                .foregroundColor(SliceColor.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, SliceSpacing.xl)
                .padding(.vertical, SliceSpacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SliceRadius.control)
                .fill(SliceColor.hoverFill)
        )
    }

    /// 引用块：左侧 2pt 紫色竖线 + 斜体 + 85% 透明度
    @ViewBuilder
    private func renderQuote(_ content: String) -> some View {
        HStack(alignment: .top, spacing: SliceSpacing.lg) {
            Rectangle()
                .fill(SliceColor.accent)
                .frame(width: 2)
            inlineText(content)
                .font(SliceFont.body.italic())
                .foregroundColor(SliceColor.textSecondary)
                .opacity(0.85)
        }
    }

    /// 无序列表：bullet + 缩进 + 每项使用行内 markdown
    @ViewBuilder
    private func renderList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: SliceSpacing.base) {
                    Text("•")
                        .foregroundColor(SliceColor.textTertiary)
                    inlineText(item)
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textPrimary)
                }
            }
        }
        .padding(.leading, SliceSpacing.base)
    }

    /// 返回对应标题级别的字号
    ///
    /// level 1 → 17pt，level 2 → 16pt，level 3 → 15pt，level 4+ → 14pt
    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 17
        case 2: return 16
        case 3: return 15
        default: return 14
        }
    }

    /// 行内 markdown 渲染：优先 `.inlineOnlyPreservingWhitespace`，失败回落纯文本
    ///
    /// 流式输出时可能出现未闭合的 `**` / `_`，回落到纯文本可保证界面不闪烁。
    @ViewBuilder
    private func inlineText(_ content: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed).textSelection(.enabled)
        } else {
            Text(content).textSelection(.enabled)
        }
    }
}

/// 流式输出期间显示在文本末尾的闪烁光标
///
/// 尺寸：6×13pt 紫色方块（spec §5.2）
/// 闪烁频率：500ms 切换一次可见性（约 1Hz）
/// 生命周期：视图 appear 时启动 Task，disappear 时取消，无资源泄漏。
private struct BlinkingCursor: View {
    /// 当前是否可见；由后台 Task 每 500ms 翻转一次
    @State private var visible = true
    /// 驱动闪烁的异步任务，持有以便 onDisappear 时取消
    @State private var blinker: Task<Void, Never>?

    var body: some View {
        Rectangle()
            .frame(width: 6, height: 13)
            .foregroundColor(SliceColor.accent)
            .opacity(visible ? 1 : 0)
            .onAppear {
                // 防止 SwiftUI 快速重绘导致多个 Task 同时跑
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
