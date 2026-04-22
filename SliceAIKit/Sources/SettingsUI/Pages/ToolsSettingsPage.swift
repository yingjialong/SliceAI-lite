// SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift
//
// Tools 设置页：列表 + 内联编辑展开区 + Reminders 风格拖拽排序
// 用户点击列表项即展开编辑 SectionCard（单选展开，再点收起）
//
// 拖拽方案（Reminders 风格）：
//   1. gripHandle 挂 `.onDrag`，把 tool.id 装进 NSItemProvider + 同步写 `draggedId`
//   2. 每行挂 `.onDrop(delegate: ToolReorderDropDelegate)`，delegate 的
//      `dropUpdated` 根据光标 y 是否过半判断"插入到本行前还是后"，更新
//      `dropTargetIndex`；**不做 move，只更新插入指示线位置**
//   3. 行上/下沿以 overlay 形式画 `InsertionIndicator`（蓝细线+空心圆）
//   4. `performDrop` 松手时才执行 `tools.move(fromOffsets:toOffset:)`
//   5. 持久化通过 `.onChange(of: tools)` 做 debounce 保存——这也修复了
//      "编辑提示词不保存"的 bug，因为任何 tools 变动都会被捕获
//
// 这套相较于"实时挤开"方案更贴近 macOS 原生拖拽体感（Finder / Reminders）：
// 其他行不抖、被拖项由系统预览跟手、指示线清晰表达落位点。
import DesignSystem
import SliceCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ToolsSettingsPage

/// Tools 设置页
///
/// 布局：
///   - 顶部操作区：右对齐"添加工具"按钮
///   - 工具列表：每行显示图标 + 工具名 + 描述；点击展开编辑区
///   - 编辑区：ToolEditorView 内嵌于内联展开卡片；选另一行或空白处收起
///
/// 持久化：通过 `.onChange(of: tools)` 驱动 debounced save——所有 tools
/// 变动（新增、删除、拖拽排序、ToolEditorView 对 prompt / 名称等的修改）都会
/// 在用户停手 `saveDebounceInterval` 后自动写盘。
public struct ToolsSettingsPage: View {

    /// 写盘前的静默等待时长：用户连续编辑时避免频繁写盘
    private static let saveDebounceInterval: UInt64 = 600_000_000  // 600 ms

    /// 拖拽上/下半判定用的行高估算值（硬编码）
    ///
    /// ToolRow 内容：icon 32pt + 上下 padding 8pt×2 = 48pt，加上文字换行约 50pt。
    /// 2~3pt 误差对"过半 / 未过半"判定不敏感；真实需要时再改为 PreferenceKey 测量。
    private static let estimatedRowHeight: CGFloat = 50

    /// 设置视图模型，用于读写 configuration.tools
    @ObservedObject private var viewModel: SettingsViewModel

    /// 当前展开编辑的 Tool id；nil 表示无选中
    @State private var expandedId: String?

    /// 待确认删除的 Tool id；非 nil 时弹出删除确认 alert
    @State private var pendingDeleteId: String?

    /// 当前被拖动的 Tool.id；非 nil 表示正有一次拖拽进行中
    @State private var draggedId: String?

    /// 如果此刻松手，插入点（Array.move 的 toOffset 语义，0…count）
    ///
    /// - nil：不显示任何指示线
    /// - 0：插入到第一个工具之前
    /// - N：插入到 tools[N] 之前（等于最后位置时在列表尾部）
    @State private var dropTargetIndex: Int?

    /// debounced save 的当前 Task；新变动进来就 cancel 重排
    @State private var saveDebounceTask: Task<Void, Never>?

    /// 构造 Tools 设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "Tools", subtitle: "管理工具列表与提示词。") {
            actionRow
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
            Button("取消", role: .cancel) { pendingDeleteId = nil }
        } message: { tool in
            Text("确定要删除「\(tool.name)」吗？此操作不可撤销。")
        }
        // 核心持久化钩子：任何对 tools 的改动（编辑 / 排序 / 新增 / 删除）
        // 停手 saveDebounceInterval 后自动落盘；老代码里分散在 addTool / performDelete
        // / 拖拽里的 save 全部撤销，改由这里统一处理。
        .onChange(of: viewModel.configuration.tools) { _, _ in
            scheduleDebouncedSave()
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

    /// 完整工具列表（每行是 drop 目标 + 可能叠加插入指示线）
    ///
    /// 外层 VStack 上挂一个兜底 `.onDrop(delegate:)`——用户把拖拽松手在行
    /// 之间的空隙或者列表底部 padding 区时，行内 delegate 不会触发，这里兜底
    /// commit 一次 reorder；同时也作为 dropUpdated 的默认容器处理最顶/最底的
    /// 特殊插入位置。
    private var toolList: some View {
        VStack(spacing: SliceSpacing.sm) {
            ForEach(viewModel.configuration.tools.indices, id: \.self) { index in
                toolListItem(for: $viewModel.configuration.tools[index], index: index)
            }
        }
        // 插入指示线切换时淡入淡出，避免线在不同 slot 之间"闪"
        .animation(.easeOut(duration: 0.12), value: dropTargetIndex)
        // 兜底 drop：行外空白区松手也能完成 reorder；detecting only）
        .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
            commitReorder()
            return true
        }
    }

    /// 单个工具列表项（行 + 展开编辑区 + drop 接收 + 插入指示线 overlay）
    ///
    /// - Parameters:
    ///   - binding: Tool 的双向绑定，editor 通过此 binding 修改 configuration
    ///   - index: 当前行在 tools 数组中的索引
    @ViewBuilder
    private func toolListItem(for binding: Binding<Tool>, index: Int) -> some View {
        let tool = binding.wrappedValue
        let isExpanded = expandedId == tool.id
        let isLast = index == viewModel.configuration.tools.count - 1

        VStack(spacing: 0) {
            makeToolRow(tool: tool, isExpanded: isExpanded)
            if isExpanded {
                toolEditor(for: binding).transition(.opacity)
            }
        }
        .clipped()
        .background(rowBackground(isExpanded: isExpanded))
        // 顶部指示线（插入到 index 之前）
        .overlay(alignment: .top) {
            if dropTargetIndex == index {
                InsertionIndicator()
                    .padding(.horizontal, SliceSpacing.xs)
                    .offset(y: -(SliceSpacing.sm / 2 + InsertionIndicator.height / 2))
            }
        }
        // 底部指示线（仅最后一行显示——插入到末尾，dropTargetIndex == count）
        .overlay(alignment: .bottom) {
            if isLast && dropTargetIndex == viewModel.configuration.tools.count {
                InsertionIndicator()
                    .padding(.horizontal, SliceSpacing.xs)
                    .offset(y: SliceSpacing.sm / 2 + InsertionIndicator.height / 2)
            }
        }
        // 本行的 drop 委派：更新 dropTargetIndex / commit reorder
        .onDrop(
            of: [UTType.plainText],
            delegate: ToolReorderDropDelegate(
                targetIndex: index,
                rowHeight: Self.estimatedRowHeight,
                tools: $viewModel.configuration.tools,
                draggedId: $draggedId,
                dropTargetIndex: $dropTargetIndex
            )
        )
    }

    /// 构造列表行视图
    /// - Parameters:
    ///   - tool: 当前行对应的工具（只读快照）
    ///   - isExpanded: 是否当前展开编辑区
    private func makeToolRow(tool: Tool, isExpanded: Bool) -> ToolRow {
        ToolRow(
            tool: tool,
            isExpanded: isExpanded,
            onToggle: {
                // 拖动中忽略 tap，避免松手瞬间误触切换
                guard draggedId == nil else { return }
                withAnimation(SliceAnimation.standard) {
                    expandedId = isExpanded ? nil : tool.id
                }
            },
            onDelete: { pendingDeleteId = tool.id },
            onDragStart: {
                if expandedId != nil { expandedId = nil }
                draggedId = tool.id
                dropTargetIndex = nil
                print("[ToolsSettingsPage] drag: start id=\(tool.id)")
            }
        )
    }

    /// 行背景：圆角表面 + 边框描边（展开时描边变 accent 色）
    private func rowBackground(isExpanded: Bool) -> some View {
        let strokeColor = isExpanded ? SliceColor.accent.opacity(0.4) : SliceColor.border
        return RoundedRectangle(cornerRadius: SliceRadius.card)
            .fill(SliceColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SliceRadius.card)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
    }

    // MARK: - 内联编辑区

    /// 展开的 Tool 编辑区（嵌入 ToolEditorView）
    private func toolEditor(for binding: Binding<Tool>) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(SliceColor.divider).frame(height: 0.5)
            ToolEditorView(
                tool: binding,
                providers: viewModel.configuration.providers
            )
            .padding(SliceSpacing.xl)
        }
    }

    // MARK: - 数据操作

    /// 添加新工具并自动展开编辑区（save 由 onChange(tools) 兜底）
    private func addTool() {
        let newId = "tool-\(Int(Date().timeIntervalSince1970))"
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
        withAnimation(SliceAnimation.standard) {
            expandedId = newId
        }
    }

    /// 实际执行删除（alert 确认后才调用；save 由 onChange(tools) 兜底）
    private func performDelete(id: String) {
        print("[ToolsSettingsPage] performDelete: id=\(id)")
        withAnimation(SliceAnimation.standard) {
            viewModel.configuration.tools.removeAll { $0.id == id }
            if expandedId == id { expandedId = nil }
        }
    }

    /// 拖拽结束（行 / 外层兜底）时统一调用：执行 Array.move 并清理状态
    ///
    /// `dropTargetIndex` 在 `dropUpdated` 里实时更新；松手后落盘由
    /// `.onChange(of: tools)` 的 debounced save 自动兜底。
    /// 不清 draggedId / dropTargetIndex 就会污染下一次拖拽，必须 defer 清掉。
    private func commitReorder() {
        defer {
            draggedId = nil
            dropTargetIndex = nil
        }
        guard let sourceId = draggedId,
              let from = viewModel.configuration.tools.firstIndex(where: { $0.id == sourceId }),
              let target = dropTargetIndex else {
            return
        }
        // target == from / target == from + 1 都等价于"不移动"，跳过避免无意义动画
        guard target != from, target != from + 1 else { return }
        print("[ToolsSettingsPage] commitReorder: \(from) → \(target)")
        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.configuration.tools.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: target
            )
        }
    }

    /// 安排一次 debounced save（取消上一个挂起 Task 再启新）
    ///
    /// 这是**唯一的 save 入口**：addTool / performDelete / commitReorder /
    /// ToolEditorView 的 @Binding 写入全都通过 `.onChange(of: tools)` 流到这里。
    /// 好处：不用在各处显式 save、用户停手才写盘、ToolEditorView 的文字输入也会保存。
    private func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.saveDebounceInterval)
            guard !Task.isCancelled else { return }
            do {
                try await viewModel.save()
                print("[ToolsSettingsPage] debounced save OK")
            } catch {
                print("[ToolsSettingsPage] debounced save failed – \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ToolReorderDropDelegate

/// 工具行的 drop 接收代理——只负责更新插入指示线位置，不做实时 reorder
///
/// 与旧版"dropEntered 立即 move"的实现相反：本实现在 `dropUpdated` 里根据
/// 光标在本行的上/下半，更新 `dropTargetIndex`，**不触碰 tools 数组**。
/// 真正的 `tools.move` 发生在 `performDrop`——这让其他行始终不动，被拖项
/// 由系统拖拽预览跟随光标，UI 视觉完全稳定、没有"乱挤开"的抖动。
///
/// 设计取舍：不从 NSItemProvider 解析 draggedId（避免异步 loadObject 的 latency），
/// 而是直接读 @Binding；payload 仅作为 SwiftUI drag 管道的契约占位。
private struct ToolReorderDropDelegate: DropDelegate {

    /// 本行在 tools 数组中的索引
    let targetIndex: Int

    /// 用于判断光标落在本行上半 / 下半的行高估算值
    let rowHeight: CGFloat

    /// 全局工具数组的 @Binding；delegate 在 performDrop 里 mutate
    @Binding var tools: [Tool]

    /// 当前被拖的 Tool.id；由外层 `.onDrag` 写入，commit 后置 nil
    @Binding var draggedId: String?

    /// 若此刻松手，插入位置（Array.move 的 toOffset 语义）；nil 不显示指示线
    @Binding var dropTargetIndex: Int?

    /// 保证系统光标显示"移动"而非"复制"箭头
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedId != nil else { return nil }
        // info.location.y 相对本行坐标系，0 在行顶部、rowHeight 在行底部
        let isUpperHalf = info.location.y < rowHeight / 2
        // 上半 → 插到本行前（index）；下半 → 插到本行后（index+1）
        let newIndex = isUpperHalf ? targetIndex : targetIndex + 1
        // 只在值真正变化时写回，避免 dropUpdated 高频触发导致无效重绘
        if dropTargetIndex != newIndex {
            dropTargetIndex = newIndex
        }
        return DropProposal(operation: .move)
    }

    /// 只有已经发起本页面内部拖拽才接受 drop——防御外部 drag 源误触
    func validateDrop(info: DropInfo) -> Bool {
        draggedId != nil
    }

    /// 拖入本行时：顺便把插入指示设一次，避免 dropUpdated 首帧延迟导致线不显示
    func dropEntered(info: DropInfo) {
        guard draggedId != nil else { return }
        let isUpperHalf = info.location.y < rowHeight / 2
        let newIndex = isUpperHalf ? targetIndex : targetIndex + 1
        if dropTargetIndex != newIndex {
            dropTargetIndex = newIndex
        }
    }

    /// 松手：执行最终的 reorder + 清状态；save 由外层 onChange(tools) 兜底
    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedId = nil
            dropTargetIndex = nil
        }
        guard let sourceId = draggedId,
              let from = tools.firstIndex(where: { $0.id == sourceId }),
              let target = dropTargetIndex else {
            return false
        }
        // target == from / target == from + 1 都等价于"不移动"，跳过无意义动画
        guard target != from, target != from + 1 else { return true }
        withAnimation(.easeInOut(duration: 0.25)) {
            tools.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: target
            )
        }
        return true
    }
}
