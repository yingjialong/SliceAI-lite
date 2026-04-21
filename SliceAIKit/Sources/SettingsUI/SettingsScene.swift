// SliceAIKit/Sources/SettingsUI/SettingsScene.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 设置主界面：NavigationSplitView 骨架
///
/// 架构说明：
///   - 侧栏（sidebar）：7 个条目，分 3 组（主要功能 / 行为 / 更多）；
///   - 详情区（detail）：根据当前选中条目渲染对应页面；
///   - 每个页面自行负责即时保存，无全局保存栏。
///
/// 窗口固定宽度 720pt、高度 520pt（与前版本保持一致，避免 AppDelegate 改动）。
public struct SettingsScene: View {

    /// 设置视图模型；由宿主创建并注入，生命周期与窗口一致
    @ObservedObject var viewModel: SettingsViewModel

    /// 当前选中的 sidebar 条目；nil 表示未选中（首次打开时自动选第一项）
    @State private var selectedItem: SidebarItem? = .appearance

    /// 构造设置主视图
    /// - Parameter viewModel: 由宿主创建的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .frame(width: 720, height: 520)
        // NavigationSplitView 在 macOS 上默认会有 sidebar 收折按钮，
        // 关闭设置窗口内不需要的导航控件（toolbar 由宿主 WindowGroup 控制）
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    /// 侧栏：7 个条目，分 3 组
    ///
    /// 使用 `List(selection:)` 驱动 `selectedItem` 绑定，保持单一 source of truth。
    /// 各 section 用 `Section(header:)` 区分分组标题，macOS 风格对应设置面板惯例。
    private var sidebarView: some View {
        List(selection: $selectedItem) {
            // 第 1 组：主要功能
            Section {
                SidebarRow(item: .providers)
                SidebarRow(item: .tools)
                SidebarRow(item: .appearance)
            } header: {
                Text("通用")
            }

            // 第 2 组：行为
            Section {
                SidebarRow(item: .hotkey)
                SidebarRow(item: .trigger)
            } header: {
                Text("行为")
            }

            // 第 3 组：更多
            Section {
                SidebarRow(item: .permissions)
                SidebarRow(item: .about)
            } header: {
                Text("更多")
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
    }

    // MARK: - Detail

    /// 详情区：根据 selectedItem 渲染对应页面
    ///
    /// `@ViewBuilder` 让 switch 分支能返回不同类型的 View，
    /// 用 `AnyView` 擦除类型以统一返回值（分支数少，性能影响可忽略）。
    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .providers:
            ProvidersSettingsPage(viewModel: viewModel)
        case .tools:
            ToolsSettingsPage(viewModel: viewModel)
        case .appearance:
            AppearanceSettingsPage(viewModel: viewModel)
        case .hotkey:
            HotkeySettingsPage(viewModel: viewModel)
        case .trigger:
            TriggerSettingsPage(viewModel: viewModel)
        case .permissions:
            PermissionsSettingsPage()
        case .about:
            AboutSettingsPage()
        case .none:
            // 未选中时：默认提示（实际上初始值为 .appearance，通常不触发此分支）
            Text("请从左侧选择一个设置项")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - SidebarItem

/// 侧栏条目枚举
///
/// 每个 case 携带其展示标签与 SF Symbol 图标，统一管理以便 sidebar 行渲染。
/// `Hashable` 保证 `List(selection:)` 的绑定类型安全。
private enum SidebarItem: Hashable, CaseIterable {
    case providers
    case tools
    case appearance
    case hotkey
    case trigger
    case permissions
    case about

    /// 中文展示标签
    var label: String {
        switch self {
        case .providers:   return "Providers"
        case .tools:       return "Tools"
        case .appearance:  return "外观"
        case .hotkey:      return "快捷键"
        case .trigger:     return "触发行为"
        case .permissions: return "权限"
        case .about:       return "关于"
        }
    }

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .providers:   return "network"
        case .tools:       return "hammer"
        case .appearance:  return "paintbrush"
        case .hotkey:      return "keyboard"
        case .trigger:     return "cursorarrow.click"
        case .permissions: return "lock.shield"
        case .about:       return "info.circle"
        }
    }
}

// MARK: - SidebarRow

/// 侧栏单行：图标 + 标签
///
/// 使用 `Label` 保持 macOS 系统设置风格，`tag` 与 `List(selection:)` 绑定。
private struct SidebarRow: View {

    /// 对应的侧栏条目
    let item: SidebarItem

    var body: some View {
        Label(item.label, systemImage: item.iconName)
            .tag(item)
    }
}
