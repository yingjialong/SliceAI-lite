// SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift
//
// Tools 设置页：列表 + 内联编辑展开区
// 用户点击列表项即展开编辑 SectionCard（单选展开，再点收起）
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - ToolsSettingsPage

/// Tools 设置页
///
/// 布局：
///   - 顶部操作区：右对齐"添加工具"按钮
///   - 工具列表：每行显示图标 + 工具名 + 描述；点击展开编辑区
///   - 编辑区：ToolEditorView 内嵌于内联展开卡片；选另一行或空白处收起
///
/// 持久化策略：ToolEditorView 通过 @Binding 直接修改 configuration，
/// 编辑收起时调用 viewModel.save() 写回磁盘。
public struct ToolsSettingsPage: View {

    /// 设置视图模型，用于读写 configuration.tools
    @ObservedObject private var viewModel: SettingsViewModel

    /// 当前展开编辑的 Tool id；nil 表示无选中
    @State private var expandedId: String?

    /// 待确认删除的 Tool id；非 nil 时弹出删除确认 alert
    @State private var pendingDeleteId: String?

    /// 构造 Tools 设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "Tools", subtitle: "管理工具列表与提示词。") {
            // 顶部操作按钮行
            actionRow

            // 工具列表
            if viewModel.configuration.tools.isEmpty {
                emptyState
            } else {
                toolList
            }
        }
        // 删除确认：用户误点垃圾桶时提供二次确认兜底
        .alert("删除工具", isPresented: deleteAlertPresented, presenting: pendingDeleteTool) { tool in
            Button("删除", role: .destructive) {
                performDelete(id: tool.id)
                pendingDeleteId = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteId = nil
            }
        } message: { tool in
            Text("确定要删除「\(tool.name)」吗？此操作不可撤销。")
        }
    }

    /// 将 pendingDeleteId 适配为 alert 的 Bool 绑定
    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )
    }

    /// 当前待删除的 Tool 对象，用于 alert 展示真实名称
    private var pendingDeleteTool: Tool? {
        guard let id = pendingDeleteId else { return nil }
        return viewModel.configuration.tools.first { $0.id == id }
    }

    // MARK: - 顶部操作行

    /// 顶部右对齐"添加工具"按钮
    private var actionRow: some View {
        HStack {
            Spacer()
            PillButton("添加工具", icon: "plus", style: .primary) {
                addTool()
            }
        }
    }

    // MARK: - 空态

    /// 空列表提示
    private var emptyState: some View {
        SectionCard {
            VStack(spacing: SliceSpacing.base) {
                Image(systemName: "hammer")
                    .font(.system(size: 28))
                    .foregroundColor(SliceColor.textTertiary)
                Text("暂无工具，点击\u{201C}添加工具\u{201D}开始配置。")
                    .font(SliceFont.callout)
                    .foregroundColor(SliceColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SliceSpacing.xl)
        }
    }

    // MARK: - 工具列表

    /// 完整工具列表（含内联编辑展开区）
    private var toolList: some View {
        VStack(spacing: SliceSpacing.sm) {
            ForEach($viewModel.configuration.tools) { $tool in
                toolListItem(for: $tool)
            }
        }
    }

    /// 单个工具列表项（行 + 展开编辑区 + 背景描边）
    ///
    /// 独立为方法以避免 Swift 类型推导超时（toolList ForEach body 过深）。
    @ViewBuilder
    private func toolListItem(for binding: Binding<Tool>) -> some View {
        let tool = binding.wrappedValue
        let isExpanded = expandedId == tool.id
        // 计算描边颜色，避免在 overlay 闭包里做三目表达式
        let strokeColor = isExpanded ? SliceColor.accent.opacity(0.4) : SliceColor.border

        VStack(spacing: 0) {
            // 列表行
            ToolRow(
                tool: tool,
                isExpanded: isExpanded
            ) {
                // 点击同行收起，点击另一行切换
                withAnimation(SliceAnimation.standard) {
                    expandedId = isExpanded ? nil : tool.id
                }
            } onDelete: {
                // 不直接删，先设置 pendingDeleteId 弹出 alert 二次确认
                pendingDeleteId = tool.id
            }

            // 内联编辑区（展开时显示）
            // 用 .opacity 淡入淡出 + VStack 高度随 withAnimation 自然扩张，
            // 视觉上呈现从 row 底部"推开"的展开动画；避免 .move(edge:.top)
            // 带来的从外部飞入感。
            if isExpanded {
                toolEditor(for: binding)
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

    /// 展开的 Tool 编辑区（嵌入 ToolEditorView）
    private func toolEditor(for binding: Binding<Tool>) -> some View {
        VStack(spacing: 0) {
            // 分隔线
            Rectangle()
                .fill(SliceColor.divider)
                .frame(height: 0.5)

            // 编辑表单
            ToolEditorView(
                tool: binding,
                providers: viewModel.configuration.providers
            )
            .padding(SliceSpacing.xl)
        }
    }

    // MARK: - 数据操作

    /// 添加新工具并自动展开编辑区
    private func addTool() {
        // 生成唯一 id，使用时间戳后缀避免重复
        let newId = "tool-\(Int(Date().timeIntervalSince1970))"
        // 关联第一个可用 Provider（若有）
        let providerId = viewModel.configuration.providers.first?.id ?? ""
        let newTool = Tool(
            id: newId,
            name: "新工具",
            icon: "wand.and.stars",
            description: nil,
            systemPrompt: nil,
            userPrompt: "{{selection}}",
            providerId: providerId,
            modelId: nil,
            temperature: nil,
            displayMode: .window,
            variables: [:]
        )
        print("[ToolsSettingsPage] addTool: id=\(newId)")
        viewModel.configuration.tools.append(newTool)
        // 立即展开新工具的编辑区
        withAnimation(SliceAnimation.standard) {
            expandedId = newId
        }
        // 异步持久化
        Task {
            do {
                try await viewModel.save()
                print("[ToolsSettingsPage] addTool: saved OK")
            } catch {
                print("[ToolsSettingsPage] addTool: save failed – \(error.localizedDescription)")
            }
        }
    }

    /// 实际执行删除（alert 确认后才调用）
    private func performDelete(id: String) {
        print("[ToolsSettingsPage] performDelete: id=\(id)")
        withAnimation(SliceAnimation.standard) {
            viewModel.configuration.tools.removeAll { $0.id == id }
            // 若删的是当前展开项，收起
            if expandedId == id {
                expandedId = nil
            }
        }
        Task {
            do {
                try await viewModel.save()
                print("[ToolsSettingsPage] performDelete: saved OK")
            } catch {
                print("[ToolsSettingsPage] performDelete: save failed – \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ToolRow

/// 工具列表行：图标 + 名称 + 描述 + 展开 chevron
///
/// 作为纯展示组件，点击事件通过 onToggle / onDelete 回调向上传递。
private struct ToolRow: View {

    /// 当前行对应的 Tool（只读展示）
    let tool: Tool

    /// 当前行是否展开
    let isExpanded: Bool

    /// 点击行时的切换回调
    let onToggle: () -> Void

    /// 点击删除按钮的回调
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: SliceSpacing.base) {
            // 工具图标区域
            iconView

            // 名称 + 描述副标题
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textPrimary)

                // 描述优先，无描述时展示 userPrompt 截断预览
                let subtitle = tool.description ?? String(tool.userPrompt.prefix(40))
                Text(subtitle)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textSecondary)
                    .lineLimit(1)
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

    /// 工具图标：emoji 字符走 Text；ASCII 字符串按 SF Symbol 解析
    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SliceRadius.control)
                .fill(SliceColor.hoverFill)
                .frame(width: 32, height: 32)

            // 启发式：首字符非 ASCII 视为 emoji（默认工具 🌐📝✨💡 走此分支），
            // 否则当成 SF Symbol 名（如 "hammer" / "doc.on.doc"）
            if let scalar = tool.icon.unicodeScalars.first, !scalar.isASCII {
                Text(tool.icon).font(.system(size: 18))
            } else {
                Image(systemName: tool.icon)
                    .font(.system(size: 14))
                    .foregroundColor(SliceColor.accent)
            }
        }
    }
}
