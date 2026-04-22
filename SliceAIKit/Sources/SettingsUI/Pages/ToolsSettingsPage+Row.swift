// SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Row.swift
//
// ToolsSettingsPage 的行组件。拆分到独立文件以控制主文件行数。
// 拖拽实现采用 `.onDrag` + `DropDelegate`（见 ToolsSettingsPage.ToolReorderDropDelegate），
// 原因：新式 `.dropDestination(for:)` 没有暴露"拖动进入目标区域"的实时回调，
// 无法在松手前完成数组 swap；老式 `DropDelegate.dropEntered` 可以，其他行因
// `withAnimation` 驱动的 `Array.move` 自然"挤开"，无需自定义几何测量。
import AppKit
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - InsertionIndicator

/// Reminders 风格的拖拽插入指示线
///
/// 视觉：左端一个描边空心小圆 + 右侧一条横贯的细线，整体使用 accent 色。
/// 用法：在行上下沿的 overlay 里按条件渲染即可，父视图通过 `.animation(_:value:)`
/// 控制进出动画，无需自己加 `transition`。
///
/// 尺寸参数：圆 8×8（stroke 2pt）、线 2pt 高。与 Reminders 的指示线视觉体量接近。
struct InsertionIndicator: View {

    /// 固定高度以便父视图精确对齐 overlay 位置（圆心与线的竖向中心线对齐）
    static let height: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            // 左端描边圆（未填充，呼应 Reminders 的空心端点）
            Circle()
                .stroke(SliceColor.accent, lineWidth: 2)
                .frame(width: Self.height, height: Self.height)
            // 指示线——延伸到父容器右沿
            Rectangle()
                .fill(SliceColor.accent)
                .frame(height: 2)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 禁用 hit-test，避免 overlay 挡住下层行的 onDrop/onTap
        .allowsHitTesting(false)
    }
}

// MARK: - ToolRow

/// 工具列表行：拖拽把手 + 工具图标 + 名称 + 描述 + 删除 + 展开 chevron
///
/// 作为纯展示组件，点击事件通过 onToggle / onDelete 回调向上传递。
/// 拖拽排序：行最左侧的 `line.3.horizontal` 把手图标挂 `.onDrag`，
/// 通过 NSItemProvider 把 tool.id 以 NSString 形式上报给系统拖拽管道；
/// drop 目标由外层的 `ToolReorderDropDelegate` 接管并在 `dropEntered` 里实时 reorder。
/// 工具的数组顺序即浮条显示优先级——越靠前在浮条里出现越早。
struct ToolRow: View {

    /// 当前行对应的 Tool（只读展示）
    let tool: Tool

    /// 当前行是否展开
    let isExpanded: Bool

    /// 点击行时的切换回调
    let onToggle: () -> Void

    /// 点击删除按钮的回调
    let onDelete: () -> Void

    /// 拖拽开始时的回调（在 `.onDrag` 闭包里触发）
    ///
    /// 用于让外层把 `draggedId` 设为 tool.id，供 DropDelegate 判断"当前被拖的是谁"
    /// 并在 `dropEntered` 里 swap 数组。SwiftUI 的 `.onDrag` 闭包返回 NSItemProvider
    /// 是同步调用，side-effect（状态写入）可以放在这里。
    let onDragStart: () -> Void

    var body: some View {
        HStack(spacing: SliceSpacing.base) {
            // 最左侧拖拽把手：.onDrag 触发点，tap 在其他区域仍能切换展开
            gripHandle

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

            // 展开 chevron（只有这个是上下箭头，用 chevron 不会和排序图标冲突）
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SliceColor.textSecondary)
        }
        .padding(.horizontal, SliceSpacing.xl)
        .padding(.vertical, SliceSpacing.base)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    /// 拖拽把手：`line.3.horizontal` 图标 + `.onDrag`
    ///
    /// 设计要点：
    ///   - 仅 handle 区挂 `.onDrag`，行内其他区域不响应拖拽，避免用户展开编辑时误触
    ///   - `.onDrag` 返回的 NSItemProvider 以 NSString 承载 tool.id；DropDelegate 不需要
    ///     解析 provider，内部通过外层 @State `draggedId` 判断来源，所以 provider 的
    ///     payload 只是满足 API 契约的占位
    ///   - 先调用 `onDragStart` 再返回 provider，保证 draggedId 赋值发生在 drop 目标
    ///     开始接收 dropEntered 回调之前
    private var gripHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(SliceColor.textTertiary)
            .frame(width: 20, height: 24)
            .contentShape(Rectangle())
            .onHover { hovering in
                // Hover 态切换 openHand，暗示"这里可以抓"
                if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .onDrag {
                // 先通知外层记录 draggedId，再把 tool.id 打包成 NSItemProvider
                onDragStart()
                return NSItemProvider(object: tool.id as NSString)
            }
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
