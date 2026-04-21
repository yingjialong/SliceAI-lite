// SliceAIKit/Sources/SettingsUI/Pages/Placeholders.swift
//
// 本文件集中放置尚未实施的设置页占位视图。
// Task 19 已填充 Hotkey / Trigger / Permissions / About（见对应文件）；
// Task 20 会填充 Providers / Tools，届时替换以下两个 struct 的 body 即可。
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - Providers

/// Providers 设置页占位（Task 20 填充）
///
/// 当前展示"待实施"提示，Task 20 完成后替换为真正的 Provider 列表 + 编辑界面。
public struct ProvidersSettingsPage: View {

    /// 设置视图模型，Task 20 实施时用于读写 Providers 列表
    @ObservedObject private var viewModel: SettingsViewModel

    /// 构造 Providers 占位页
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "Providers", subtitle: "管理大模型供应商。") {
            PlaceholderCard(icon: "network", label: "Providers 设置", task: "Task 20")
        }
    }
}

// MARK: - Tools

/// Tools 设置页占位（Task 20 填充）
///
/// 当前展示"待实施"提示，Task 20 完成后替换为工具列表 + 编辑界面。
public struct ToolsSettingsPage: View {

    /// 设置视图模型，Task 20 实施时用于读写 Tools 列表
    @ObservedObject private var viewModel: SettingsViewModel

    /// 构造 Tools 占位页
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "Tools", subtitle: "管理工具列表与提示词。") {
            PlaceholderCard(icon: "hammer", label: "Tools 设置", task: "Task 20")
        }
    }
}

// MARK: - 内部占位卡片辅助

/// 生成统一外观的"待实施"占位卡片
///
/// 设计为私有 View 而非全局函数，避免在非 @MainActor 上下文中构造 SwiftUI View 引发
/// Swift 6 并发诊断（SectionCard.init 使用 @ViewBuilder 会被 SwiftUI 推断为 @MainActor 隔离）。
///
/// - icon: SF Symbol 名称
/// - label: 页面展示标签
/// - task: 计划实施该页面的任务号（仅供开发参考，不会展示给最终用户）
private struct PlaceholderCard: View {
    let icon: String
    let label: String
    let task: String

    var body: some View {
        SectionCard {
            HStack(spacing: SliceSpacing.base) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(SliceColor.textSecondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textPrimary)
                    Text("即将推出（\(task)）")
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, SliceSpacing.sm)
        }
    }
}
