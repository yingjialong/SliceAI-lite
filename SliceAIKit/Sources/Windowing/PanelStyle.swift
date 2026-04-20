// SliceAIKit/Sources/Windowing/PanelStyle.swift
import SwiftUI
import AppKit

/// 统一的 NSPanel 外观常量
///
/// 所有常量由 UI 代码在主线程访问，因此整个枚举标注为 `@MainActor`，
/// 以便在 Swift 6 严格并发模式下持有 `NSColor` 等非 Sendable 类型时仍然合法。
@MainActor
public enum PanelStyle {
    public static let cornerRadius: CGFloat = 10
    public static let backgroundColor = NSColor(white: 0.12, alpha: 0.95)
    public static let borderColor = NSColor(white: 0.3, alpha: 0.8)
    public static let shadowBlur: CGFloat = 20
    public static let shadowOpacity: Float = 0.4
    public static let toolbarButtonSize = CGSize(width: 30, height: 30)
    public static let toolbarPadding: CGFloat = 6
}

/// SwiftUI 里使用的暗色主题调色板
///
/// 依赖 `PanelStyle.backgroundColor`，同样标注为 `@MainActor`，
/// 保证与底层 `NSColor` 的访问隔离一致。
@MainActor
public enum PanelColors {
    public static let background = Color(nsColor: PanelStyle.backgroundColor)
    public static let button = Color.white.opacity(0.1)
    public static let buttonHover = Color.white.opacity(0.2)
    public static let text = Color.white.opacity(0.95)
    public static let textSecondary = Color.white.opacity(0.6)
    public static let accent = Color.blue
}
