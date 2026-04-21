// SliceAIKit/Sources/SettingsUI/Pages/ProvidersSettingsPage.swift
//
// Providers 设置页：列表 + 内联编辑展开区
// 用户点击列表项即展开编辑 SectionCard（单选展开，再点收起）
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - ProvidersSettingsPage

/// Providers 设置页
///
/// 布局：
///   - 顶部操作区：右对齐"添加 Provider"按钮
///   - Provider 列表：每行显示首字母头像 + 名称 + 默认模型；点击展开编辑区
///   - 编辑区：ProviderEditorView 内嵌于 SectionCard；选另一行或空白处收起
///
/// 持久化策略：ProviderEditorView 通过 @Binding 直接修改 configuration，
/// 编辑收起时调用 viewModel.save() 写回磁盘。
public struct ProvidersSettingsPage: View {

    /// 设置视图模型，用于读写 configuration.providers
    @ObservedObject private var viewModel: SettingsViewModel

    /// 当前展开编辑的 Provider id；nil 表示无选中
    @State private var expandedId: String?

    /// 构造 Providers 设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "Providers", subtitle: "管理大模型供应商与 API Key。") {
            // 顶部操作按钮行
            actionRow

            // Provider 列表
            if viewModel.configuration.providers.isEmpty {
                emptyState
            } else {
                providerList
            }
        }
    }

    // MARK: - 顶部操作行

    /// 顶部右对齐"添加"按钮
    private var actionRow: some View {
        HStack {
            Spacer()
            PillButton("添加 Provider", icon: "plus", style: .primary) {
                addProvider()
            }
        }
    }

    // MARK: - 空态

    /// 空列表提示
    private var emptyState: some View {
        SectionCard {
            VStack(spacing: SliceSpacing.base) {
                Image(systemName: "network")
                    .font(.system(size: 28))
                    .foregroundColor(SliceColor.textTertiary)
                Text("暂无 Provider，点击\u{201C}添加 Provider\u{201D}开始配置。")
                    .font(SliceFont.callout)
                    .foregroundColor(SliceColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SliceSpacing.xl)
        }
    }

    // MARK: - Provider 列表

    /// 完整 Provider 列表（含内联编辑展开区）
    private var providerList: some View {
        // 用 ForEach 而非 List，保持在 SettingsPageShell 的 ScrollView 中统一滚动
        VStack(spacing: SliceSpacing.sm) {
            ForEach($viewModel.configuration.providers) { $provider in
                providerListItem(for: $provider)
            }
        }
    }

    /// 单个 Provider 列表项（行 + 展开编辑区 + 背景描边）
    ///
    /// 独立为方法以避免 Swift 类型推导超时（providerList ForEach body 过深）。
    @ViewBuilder
    private func providerListItem(for binding: Binding<Provider>) -> some View {
        let provider = binding.wrappedValue
        let isExpanded = expandedId == provider.id
        // 提前计算描边颜色，避免在 overlay 闭包里做三目表达式
        let strokeColor = isExpanded ? SliceColor.accent.opacity(0.4) : SliceColor.border

        VStack(spacing: 0) {
            // 列表行
            ProviderRow(
                provider: provider,
                isExpanded: isExpanded
            ) {
                // 点击同行收起；点击另一行切换展开
                withAnimation(SliceAnimation.standard) {
                    expandedId = isExpanded ? nil : provider.id
                }
            } onDelete: {
                deleteProvider(id: provider.id)
            }

            // 内联编辑区（展开时显示）
            if isExpanded {
                providerEditor(for: binding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SliceRadius.card)
                .fill(SliceColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: SliceRadius.card)
                        .stroke(strokeColor, lineWidth: 0.5)
                )
        )
        .animation(SliceAnimation.standard, value: expandedId)
    }

    // MARK: - 内联编辑区

    /// 展开的 Provider 编辑区（嵌入 ProviderEditorView + 删除按钮）
    private func providerEditor(for binding: Binding<Provider>) -> some View {
        VStack(spacing: 0) {
            // 分隔线
            Rectangle()
                .fill(SliceColor.divider)
                .frame(height: 0.5)

            // 编辑表单（去掉 Form 的 Provider ID 为闭包捕获的副本，用 .id 解耦）
            ProviderEditorView(
                provider: binding,
                onSaveKey: { key in
                    // 转发到 ViewModel 写 Keychain
                    try await viewModel.setAPIKey(key, for: binding.wrappedValue)
                },
                onLoadKey: {
                    // 从 Keychain 读已保存的 key
                    try? await viewModel.readAPIKey(for: binding.wrappedValue)
                },
                onTestKey: { key, url, model in
                    // 转发到 ViewModel 发探测请求
                    try await viewModel.testProvider(apiKey: key, baseURL: url, model: model)
                }
            )
            .padding(SliceSpacing.xl)
        }
    }

    // MARK: - 数据操作

    /// 添加新 Provider 并自动展开编辑区
    private func addProvider() {
        // 生成唯一 id，使用时间戳后缀避免重复
        let newId = "provider-\(Int(Date().timeIntervalSince1970))"
        // 硬编码 OpenAI baseURL 字符串是有效 URL，guard 处理仅为避免 force unwrap 告警
        guard let defaultURL = URL(string: "https://api.openai.com/v1") else { return }
        let newProvider = Provider(
            id: newId,
            name: "新 Provider",
            baseURL: defaultURL,
            apiKeyRef: "keychain:\(newId)",
            defaultModel: "gpt-4o-mini"
        )
        print("[ProvidersSettingsPage] addProvider: id=\(newId)")
        viewModel.configuration.providers.append(newProvider)
        // 立即展开新 Provider 的编辑区
        withAnimation(SliceAnimation.standard) {
            expandedId = newId
        }
        // 异步持久化
        Task {
            do {
                try await viewModel.save()
                print("[ProvidersSettingsPage] addProvider: saved OK")
            } catch {
                print("[ProvidersSettingsPage] addProvider: save failed – \(error.localizedDescription)")
            }
        }
    }

    /// 删除指定 Provider
    private func deleteProvider(id: String) {
        print("[ProvidersSettingsPage] deleteProvider: id=\(id)")
        viewModel.configuration.providers.removeAll { $0.id == id }
        // 若删的是当前展开项，收起
        if expandedId == id {
            expandedId = nil
        }
        Task {
            do {
                try await viewModel.save()
                print("[ProvidersSettingsPage] deleteProvider: saved OK")
            } catch {
                print("[ProvidersSettingsPage] deleteProvider: save failed – \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ProviderRow

/// Provider 列表行：首字母头像 + 名称 + 默认模型 + 展开 chevron
///
/// 作为纯展示组件，点击事件通过 onToggle / onDelete 回调向上传递。
private struct ProviderRow: View {

    /// 当前行对应的 Provider（只读展示）
    let provider: Provider

    /// 当前行是否展开
    let isExpanded: Bool

    /// 点击行时的切换回调
    let onToggle: () -> Void

    /// 点击删除按钮的回调
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: SliceSpacing.base) {
            // 首字母头像
            avatarView

            // 名称 + 默认模型副标题
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textPrimary)
                Text(provider.defaultModel)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textSecondary)
            }

            Spacer()

            // 删除按钮（展开时显示）
            if isExpanded {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(SliceColor.error)
                }
                .buttonStyle(.plain)
                .padding(.trailing, SliceSpacing.xs)
            }

            // 展开 chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SliceColor.textSecondary)
        }
        .padding(.horizontal, SliceSpacing.xl)
        .padding(.vertical, SliceSpacing.base)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    /// 首字母圆形头像
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(SliceColor.accent.opacity(0.15))
                .frame(width: 32, height: 32)
            Text(provider.name.prefix(1).uppercased())
                .font(SliceFont.subheadline)
                .foregroundColor(SliceColor.accent)
        }
    }
}
