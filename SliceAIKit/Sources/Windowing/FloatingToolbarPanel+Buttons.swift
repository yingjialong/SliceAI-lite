// SliceAIKit/Sources/Windowing/FloatingToolbarPanel+Buttons.swift
//
// 浮条内"带文字按钮"的视图与文本截断工具。
// 拆到独立文件只为控制 FloatingToolbarPanel.swift 的行数不超 SwiftLint 限制。
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - ToolbarLabelFormat

/// 浮条按钮的文本截断工具
enum ToolbarLabelFormat {

    /// 按"最多 4 个中文字或 1 个英文单词"规则截断工具名
    ///
    /// - CJK（中日韩）字符开头：取前 4 个 Character（一个汉字即 1 Character）
    /// - 其他（拉丁字母 / 数字 / 符号）开头：取以空白为分界的首个 token
    /// - 空串直接返回空串
    static func shorten(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        if isCJKCharacter(first) {
            return String(trimmed.prefix(4))
        }
        // 英文 / 数字：按空白拆分取首个 word
        return trimmed.split(whereSeparator: { $0.isWhitespace })
            .first.map(String.init) ?? trimmed
    }

    /// 粗粒度判定：字符是否属于 CJK / 假名 / 谚文等东亚表意区块
    private static func isCJKCharacter(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            let value = scalar.value
            // CJK Unified Ideographs（常用汉字）
            if (0x4E00...0x9FFF).contains(value) { return true }
            // CJK Extension-A（生僻汉字）
            if (0x3400...0x4DBF).contains(value) { return true }
            // Hiragana + Katakana（日文假名）
            if (0x3040...0x30FF).contains(value) { return true }
            // Hangul Syllables（韩文音节）
            if (0xAC00...0xD7AF).contains(value) { return true }
        }
        return false
    }
}

// MARK: - ToolbarItemButton

/// 支持 "仅名称" 与 "图标+名称" 两种渲染的工具按钮
///
/// 仅图标样式走 DesignSystem 里的 `IconButton`；这里只处理带文字的场景，
/// 保持与 IconButton 一致的交互反馈（hover 高亮 / 按压缩放 / help tooltip），
/// 但允许宽度随内容自适应。
struct ToolbarItemButton: View {

    /// 图标（emoji 或 SF Symbol 名）；nil 表示"仅名称"样式
    let icon: String?

    /// 显示的短名称；nil 在本组件里不应出现（调用方保证非 nil）
    let label: String?

    /// 尺寸 / 字号参数（由外层 FloatingToolbarPanel.ToolbarMetrics 提供）
    let metrics: FloatingToolbarPanel.ToolbarMetrics

    /// 完整名称作为 tooltip，避免短缩写遮蔽真实信息
    let help: String

    /// 点击回调
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    iconView(for: icon)
                }
                if let label {
                    Text(label)
                        .font(.system(size: metrics.labelFontSize, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundColor(SliceColor.textSecondary)
            .frame(height: metrics.buttonSize)
            // 带文字的按钮加 6pt 横向内边距，让触控热区和视觉外框更舒展
            .padding(.horizontal, 6)
            .frame(minWidth: metrics.buttonSize)
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: SliceRadius.button)
        }
        .buttonStyle(.plain)
        .pressScale()
        .help(help)
    }

    /// emoji 用 Text 渲染、SF Symbol 用 Image(systemName:) —— 与 IconButton 保持一致
    @ViewBuilder
    private func iconView(for icon: String) -> some View {
        if let scalar = icon.unicodeScalars.first, scalar.isASCII {
            Image(systemName: icon)
                .font(.system(size: metrics.iconFontSize, weight: .medium))
        } else {
            Text(icon)
                .font(.system(size: metrics.iconFontSize))
        }
    }
}
