// SliceAIKit/Sources/SettingsUI/Pages/TriggerSettingsPage.swift
//
// 触发行为设置页：控制划词浮条与命令面板的触发策略。
// onChange 使用 macOS 14+ 新签名（_, newValue）避免 deprecated warning。
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - TriggerSettingsPage

/// 触发行为设置页
///
/// 提供四项可配置开关/数值：
///   - 浮动工具栏开关（floatingToolbarEnabled）
///   - 命令面板开关（commandPaletteEnabled）
///   - 最小触发字符数（minimumSelectionLength）
///   - mouseUp 后 debounce 延迟（triggerDelayMs）
///
/// 持久化策略：每项 `.onChange` 触发后立即调用 `viewModel.saveTriggers()`，
/// 无需单独保存按钮。
public struct TriggerSettingsPage: View {

    /// 设置视图模型，用于读写 configuration.triggers
    @ObservedObject private var viewModel: SettingsViewModel

    /// 构造触发行为设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "触发行为", subtitle: "控制划词与命令面板的触发策略。") {
            // 触发开关组
            triggerSwitchesCard

            // 灵敏度数值组
            sensitivityCard

            // 浮动工具栏展示组
            floatingToolbarCard
        }
    }

    // MARK: - 开关卡片

    /// 浮动工具栏 / 命令面板开关卡片
    private var triggerSwitchesCard: some View {
        SectionCard("触发开关") {
            // 浮动工具栏开关：划词后弹出工具栏
            SettingsRow("浮动工具栏") {
                Toggle("", isOn: $viewModel.configuration.triggers.floatingToolbarEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    // macOS 14+ onChange 新签名：(oldValue, newValue)
                    .onChange(of: viewModel.configuration.triggers.floatingToolbarEnabled) { _, _ in
                        // 立即将 triggers 变化写回磁盘
                        Task { await viewModel.saveTriggers() }
                    }
            }

            // 命令面板开关：⌥Space 调出命令面板
            SettingsRow("命令面板") {
                Toggle("", isOn: $viewModel.configuration.triggers.commandPaletteEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: viewModel.configuration.triggers.commandPaletteEnabled) { _, _ in
                        Task { await viewModel.saveTriggers() }
                    }
            }
        }
    }

    // MARK: - 灵敏度卡片

    /// 最小字符数 / debounce 延迟数值卡片
    private var sensitivityCard: some View {
        SectionCard("灵敏度") {
            // 最小触发字符数：1–50，低于此值的选区不触发浮条
            SettingsRow("最小触发字符数") {
                HStack(spacing: SliceSpacing.base) {
                    // 当前值展示
                    Text("\(viewModel.configuration.triggers.minimumSelectionLength) 字符")
                        .font(SliceFont.subheadline)
                        .foregroundColor(SliceColor.textSecondary)
                        .frame(minWidth: 52, alignment: .trailing)

                    Stepper(
                        "",
                        value: $viewModel.configuration.triggers.minimumSelectionLength,
                        in: 1...50
                    )
                    .labelsHidden()
                    .onChange(of: viewModel.configuration.triggers.minimumSelectionLength) { _, _ in
                        Task { await viewModel.saveTriggers() }
                    }
                }
            }

            // mouseUp debounce 延迟：50–500ms，值越大划词越不灵敏
            SettingsRow("触发延迟") {
                HStack(spacing: SliceSpacing.base) {
                    // 当前值展示
                    Text("\(viewModel.configuration.triggers.triggerDelayMs) ms")
                        .font(SliceFont.subheadline)
                        .foregroundColor(SliceColor.textSecondary)
                        .frame(minWidth: 52, alignment: .trailing)

                    Stepper(
                        "",
                        value: $viewModel.configuration.triggers.triggerDelayMs,
                        in: 50...500,
                        step: 50
                    )
                    .labelsHidden()
                    .onChange(of: viewModel.configuration.triggers.triggerDelayMs) { _, _ in
                        Task { await viewModel.saveTriggers() }
                    }
                }
            }
        }
    }

    // MARK: - 浮动工具栏展示卡片

    /// 控制划词浮条每次最多显示多少个工具位（含"更多"按钮），超出部分折叠到溢出菜单
    private var floatingToolbarCard: some View {
        SectionCard("浮动工具栏") {
            // 最多显示工具数：2–20；超出的工具会折叠到"更多"按钮里
            SettingsRow("最多显示") {
                HStack(spacing: SliceSpacing.base) {
                    // 当前值展示：2 个工具位时会显示"2 个（含更多）"提示
                    Text("\(viewModel.configuration.triggers.floatingToolbarMaxTools) 个")
                        .font(SliceFont.subheadline)
                        .foregroundColor(SliceColor.textSecondary)
                        .frame(minWidth: 52, alignment: .trailing)

                    Stepper(
                        "",
                        value: $viewModel.configuration.triggers.floatingToolbarMaxTools,
                        in: 2...20
                    )
                    .labelsHidden()
                    .onChange(of: viewModel.configuration.triggers.floatingToolbarMaxTools) { _, _ in
                        Task { await viewModel.saveTriggers() }
                    }
                }
            }

            // 说明行：解释"更多"按钮行为
            HStack {
                Text("工具总数超过此值时，最后一位会变成「⋯ 更多」按钮，点击展开剩余工具。工具在浮条中的顺序与「Tools」页的排序一致，可在那里调整优先级。")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, SliceSpacing.base)
        }
    }
}
