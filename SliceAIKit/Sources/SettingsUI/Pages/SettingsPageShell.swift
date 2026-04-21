// SliceAIKit/Sources/SettingsUI/Pages/SettingsPageShell.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 设置页面通用外壳
///
/// 提供统一的标题 + 副标题 + 可滚动内容区布局，
/// 所有设置子页面通过此外壳保持风格一致。
///
/// 布局结构：
///   - 顶部标题区（title + subtitle）
///   - ScrollView 包裹的内容区，内容由 `content` 提供
///
/// 用法示例：
/// ```swift
/// SettingsPageShell(title: "外观", subtitle: "控制应用的颜色主题") {
///     // 内容 View
/// }
/// ```
public struct SettingsPageShell<Content: View>: View {

    /// 页面主标题
    private let title: String

    /// 页面副标题（可选），nil 时不渲染该行
    private let subtitle: String?

    /// 页面内容，通过 `@ViewBuilder` 注入
    @ViewBuilder private let content: () -> Content

    /// 构造设置页外壳
    /// - Parameters:
    ///   - title: 页面主标题
    ///   - subtitle: 页面副标题，nil 时不显示
    ///   - content: 页面内容
    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SliceSpacing.lg) {
                // 顶部标题区
                headerView
                // 注入内容区
                content()
            }
            .padding(SliceSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 保证 ScrollView 总是撑满右侧详情区
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SliceColor.background)
    }

    /// 顶部标题 + 副标题区块
    @ViewBuilder
    private var headerView: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            // 主标题：大字重（SliceFont.title = 17pt bold）
            Text(title)
                .font(SliceFont.title)
                .foregroundColor(SliceColor.textPrimary)

            // 副标题：仅在非 nil 时渲染
            if let subtitle {
                Text(subtitle)
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textSecondary)
            }
        }
    }
}
