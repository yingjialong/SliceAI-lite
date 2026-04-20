// SliceAIKit/Sources/SettingsUI/SettingsScene.swift
import SwiftUI
import SliceCore

/// 设置主界面：Tools / Providers / Hotkeys / Triggers 四个标签页
///
/// 由 `SettingsViewModel` 提供数据，视图内只做编排，不直接访问磁盘或 Keychain。
public struct SettingsScene: View {

    /// 设置视图模型；由宿主创建并注入，保证生命周期与窗口一致
    @ObservedObject var viewModel: SettingsViewModel

    /// Tools 标签页当前选中的 Tool id
    @State private var selectedToolID: String?

    /// Providers 标签页当前选中的 Provider id
    @State private var selectedProviderID: String?

    /// 构造设置主视图
    /// - Parameter viewModel: 由宿主创建的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            toolsTab.tabItem { Label("Tools", systemImage: "hammer") }
            providersTab.tabItem { Label("Providers", systemImage: "network") }
            hotkeyTab.tabItem { Label("Hotkeys", systemImage: "keyboard") }
            triggersTab.tabItem { Label("Triggers", systemImage: "cursorarrow.click") }
        }
        .frame(width: 720, height: 480)
    }

    // MARK: - Tabs

    /// Tools 标签页：左侧列表 + 右侧编辑表单，顶部工具栏负责新增 / 保存
    private var toolsTab: some View {
        HSplitView {
            toolsList
            toolsDetail
        }
        .toolbar { toolsToolbar }
    }

    /// Tools 列表，支持选择和删除
    private var toolsList: some View {
        List(selection: $selectedToolID) {
            ForEach($viewModel.configuration.tools) { $tool in
                HStack {
                    Text(tool.icon)
                    Text(tool.name)
                }
                .tag(tool.id as String?)
            }
            .onDelete { offsets in
                viewModel.configuration.tools.remove(atOffsets: offsets)
            }
        }
        .frame(minWidth: 200)
    }

    /// Tools 右侧编辑区：根据选中 id 渲染 ToolEditorView 或占位
    @ViewBuilder
    private var toolsDetail: some View {
        if let id = selectedToolID,
           let idx = viewModel.configuration.tools.firstIndex(where: { $0.id == id }) {
            ToolEditorView(
                tool: $viewModel.configuration.tools[idx],
                providers: viewModel.configuration.providers
            )
        } else {
            Text("Select a tool")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Tools 顶部工具栏：新增按钮 + 保存按钮
    @ToolbarContentBuilder
    private var toolsToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                // 新建 Tool，默认绑定到第一个 Provider（若存在）并选中它
                let firstProviderId = viewModel.configuration.providers.first?.id ?? ""
                let new = Tool(
                    id: UUID().uuidString,
                    name: "New Tool",
                    icon: "⚡",
                    description: nil,
                    systemPrompt: nil,
                    userPrompt: "{{selection}}",
                    providerId: firstProviderId,
                    modelId: nil,
                    temperature: 0.3,
                    displayMode: .window,
                    variables: [:]
                )
                viewModel.configuration.tools.append(new)
                selectedToolID = new.id
            } label: {
                Image(systemName: "plus")
            }

            Button {
                // 存盘失败时仅忽略：UI 层不抛错，但错误已记录在 store 日志
                Task { try? await viewModel.save() }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
        }
    }

    /// Providers 标签页：左侧列表 + 右侧编辑表单
    private var providersTab: some View {
        HSplitView {
            List(selection: $selectedProviderID) {
                ForEach($viewModel.configuration.providers) { $provider in
                    Text(provider.name).tag(provider.id as String?)
                }
            }
            .frame(minWidth: 200)
            providersDetail
        }
    }

    /// Providers 右侧编辑区：根据选中 id 渲染 ProviderEditorView 或占位
    ///
    /// 注意：`onSaveKey` / `onLoadKey` 闭包通过值捕获当前 `provider` 快照，
    /// 让 Keychain 读写的 account 与 `Provider.apiKeyRef` 保持一致，
    /// 这样写入槽位与 `ToolExecutor` 读取槽位对齐，避免 provider.id 与
    /// `apiKeyRef` 指向的 account 不一致时出现“写入后读不到密钥”的情况。
    ///
    /// 值捕获的副作用：若用户在编辑器中修改 `apiKeyRef` 后立即点 Save，
    /// 由于 SwiftUI 对 `$viewModel.configuration.providers` 的绑定改动会重建
    /// 该分支视图与闭包，捕获到的是“最新一次渲染时”的 provider 快照，
    /// 因此在本轮交互下是安全的。
    @ViewBuilder
    private var providersDetail: some View {
        if let id = selectedProviderID,
           let idx = viewModel.configuration.providers.firstIndex(where: { $0.id == id }) {
            // 捕获 provider 值而非 id，确保闭包使用的是当下快照的 apiKeyRef
            let provider = viewModel.configuration.providers[idx]
            ProviderEditorView(
                provider: $viewModel.configuration.providers[idx],
                onSaveKey: { [vm = viewModel, provider] key in
                    try? await vm.setAPIKey(key, for: provider)
                },
                onLoadKey: { [vm = viewModel, provider] in
                    (try? await vm.readAPIKey(for: provider)) ?? nil
                }
            )
        } else {
            Text("Select a provider")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Hotkeys 标签页：当前只暴露命令面板快捷键
    private var hotkeyTab: some View {
        HotkeyEditorView(binding: $viewModel.configuration.hotkeys.toggleCommandPalette)
    }

    /// Triggers 标签页：划词/命令面板的启用开关与阈值
    private var triggersTab: some View {
        Form {
            Toggle(
                "Floating Toolbar 启用",
                isOn: $viewModel.configuration.triggers.floatingToolbarEnabled
            )
            Toggle(
                "Command Palette 启用",
                isOn: $viewModel.configuration.triggers.commandPaletteEnabled
            )
            Stepper(
                "最小选中长度: \(viewModel.configuration.triggers.minimumSelectionLength)",
                value: $viewModel.configuration.triggers.minimumSelectionLength,
                in: 1...100
            )
            Stepper(
                "触发延迟: \(viewModel.configuration.triggers.triggerDelayMs) ms",
                value: $viewModel.configuration.triggers.triggerDelayMs,
                in: 0...2000,
                step: 50
            )
        }
        .formStyle(.grouped)
        .padding()
    }
}
