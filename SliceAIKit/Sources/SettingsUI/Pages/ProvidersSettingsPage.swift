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

    /// 待确认删除的 Provider id；非 nil 时弹出删除确认 alert
    @State private var pendingDeleteId: String?

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
        // 删除确认：用户误点垃圾桶时提供二次确认兜底
        .alert("删除 Provider",
               isPresented: deleteAlertPresented,
               presenting: pendingDeleteProvider) { provider in
            Button("删除", role: .destructive) {
                performDelete(id: provider.id)
                pendingDeleteId = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteId = nil
            }
        } message: { provider in
            Text("确定要删除「\(provider.name)」吗？关联此 Provider 的工具将失效，请先在工具中改绑其他 Provider。")
        }
    }

    /// 将 pendingDeleteId 适配为 alert 的 Bool 绑定
    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )
    }

    /// 当前待删除的 Provider 对象，用于 alert 展示真实名称
    private var pendingDeleteProvider: Provider? {
        guard let id = pendingDeleteId else { return nil }
        return viewModel.configuration.providers.first { $0.id == id }
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
                // 不直接删，先设置 pendingDeleteId 弹出 alert 二次确认
                pendingDeleteId = provider.id
            }

            // 内联编辑区（展开时显示）
            // 用 .opacity 淡入淡出 + VStack 高度随 withAnimation 自然扩张，
            // 视觉上呈现从 row 底部"推开"的展开动画；避免 .move(edge:.top)
            // 带来的从外部飞入感。
            if isExpanded {
                providerEditor(for: binding)
                    .transition(.opacity)
            }
        }
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: SliceRadius.card)
                .fill(SliceColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: SliceRadius.card)
                        .stroke(strokeColor, lineWidth: 0.5)
                )
        )
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

    /// 实际执行删除（alert 确认后才调用）
    private func performDelete(id: String) {
        print("[ProvidersSettingsPage] performDelete: id=\(id)")
        withAnimation(SliceAnimation.standard) {
            viewModel.configuration.providers.removeAll { $0.id == id }
            // 若删的是当前展开项，收起
            if expandedId == id {
                expandedId = nil
            }
        }
        Task {
            do {
                try await viewModel.save()
                print("[ProvidersSettingsPage] performDelete: saved OK")
            } catch {
                print("[ProvidersSettingsPage] performDelete: save failed – \(error.localizedDescription)")
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
