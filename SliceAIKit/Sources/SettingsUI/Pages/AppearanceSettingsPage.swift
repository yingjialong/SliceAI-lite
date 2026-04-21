// SliceAIKit/Sources/SettingsUI/Pages/AppearanceSettingsPage.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 外观设置页
///
/// 提供三选一外观模式切换（跟随系统 / 浅色 / 深色），
/// 用户点击后立即通过 `SettingsViewModel.setAppearance(_:)` 持久化，
/// 无需额外的"保存"操作——即时生效。
///
/// 依赖：
///   - `SettingsViewModel` 通过 `@ObservedObject` 注入，读取 `viewModel.appearance`
///     并调用 `viewModel.setAppearance(_:)`
///   - `AppearanceMode.displayName`（DesignSystem 扩展）提供中文展示名
///   - `SectionCard`（DesignSystem）提供圆角卡片样式分组
public struct AppearanceSettingsPage: View {

    /// 设置视图模型，外观页通过它读取当前模式并触发持久化
    @ObservedObject private var viewModel: SettingsViewModel

    /// 构造外观设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(
            title: "外观",
            subtitle: "选择应用的颜色主题，切换后立即生效。"
        ) {
            SectionCard("主题模式") {
                // 遍历全部 AppearanceMode 枚举值，渲染三行选项
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    AppearanceModeRow(
                        mode: mode,
                        isSelected: viewModel.appearance == mode,
                        onSelect: {
                            // 点击后立即启动 async 任务持久化，不阻塞主线程
                            Task {
                                await viewModel.setAppearance(mode)
                            }
                        }
                    )
                    // 非最后一项加分隔线
                    if mode != AppearanceMode.allCases.last {
                        Divider()
                            .padding(.leading, SliceSpacing.xxl)
                    }
                }
            }
        }
    }
}

// MARK: - AppearanceModeRow

/// 外观模式选择行：图标 + 名称 + 选中标记
///
/// 设计为内部类型，只在本文件使用，避免污染 SettingsUI 公共命名空间。
private struct AppearanceModeRow: View {

    /// 对应的外观模式
    let mode: AppearanceMode

    /// 该行是否被选中
    let isSelected: Bool

    /// 用户点击该行时的回调
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SliceSpacing.base) {
                // 模式图标
                Image(systemName: modeIconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? SliceColor.accent : SliceColor.textSecondary)
                    .frame(width: 24, height: 24)

                // 中文展示名
                Text(mode.displayName)
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textPrimary)

                Spacer()

                // 选中状态：对勾标记
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SliceColor.accent)
                }
            }
            .contentShape(Rectangle()) // 扩大点击热区到整行
            .padding(.vertical, SliceSpacing.sm)
            .padding(.horizontal, SliceSpacing.base)
        }
        .buttonStyle(.plain)
    }

    /// 根据外观模式返回 SF Symbol 名称
    private var modeIconName: String {
        switch mode {
        case .auto:  return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark:  return "moon"
        }
    }
}
