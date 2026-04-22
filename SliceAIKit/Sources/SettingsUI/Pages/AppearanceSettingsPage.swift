// SliceAIKit/Sources/SettingsUI/Pages/AppearanceSettingsPage.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 外观设置页
///
/// 提供三选一外观模式切换（跟随系统 / 浅色 / 深色）。
/// 切换走 `ThemeManager.setMode(_:)`——这是**应用主题的唯一真相源**：
///   - 菜单栏「外观」子菜单也走这条路径；
///   - AppContainer 启动时把 `themeManager.onModeChange` 接到 ConfigurationStore，
///     所以一次 setMode 调用同时完成：UI 切换（`AppDelegate.applyAppearanceToAllWindows`
///     的 Observation 追踪会触发）+ 持久化（onModeChange 回调写 config.json）。
///
/// 历史坑：早先版本此页调的是 `SettingsViewModel.setAppearance(_:)`，只更新
/// `configuration.appearance` 与 `viewModel.appearance` 并写盘，**没触发 ThemeManager**，
/// 造成勾选看起来切换了但窗口 NSAppearance 没变。现在统一走 ThemeManager。
///
/// 依赖：
///   - `@Environment(ThemeManager.self)`：由 AppDelegate 注入到 SettingsScene 子树，
///     负责读写当前 mode
///   - `SettingsViewModel`：保留 viewModel 参数以兼容 SettingsScene 调用点，
///     当前实现不直接使用（appearance 读写全部委托给 ThemeManager）
///   - `AppearanceMode.displayName`（DesignSystem 扩展）提供中文展示名
///   - `SectionCard`（DesignSystem）提供圆角卡片样式分组
public struct AppearanceSettingsPage: View {

    /// 设置视图模型——保留以兼容 SettingsScene 当前调用签名；本页不读写它
    @ObservedObject private var viewModel: SettingsViewModel

    /// 全局主题管理器，点击切换时直接调 setMode；同时 mode 变化会驱动本页重绘
    @Environment(ThemeManager.self) private var themeManager

    /// 构造外观设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型（当前未使用，保留以避免破坏调用签名）
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
                        isSelected: themeManager.mode == mode,
                        onSelect: {
                            // 统一走 ThemeManager：UI 切换由 withObservationTracking 驱动，
                            // 持久化由 onModeChange 回调完成——无需再触发 viewModel
                            themeManager.setMode(mode)
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
