import AppKit
import SwiftUI

/// 悬浮工具栏左侧的拖拽把手
///
/// 视觉：2×3 共 6 个小圆点，直径 1.8pt、间距 4pt，hover 时底色变浅 + 游标切 openHand。
/// 交互：点击拖动时由外层调用 `NSWindow.performDrag(with:)` 实现整窗移动；
/// 本组件仅负责视觉与游标管理，不直接处理拖拽逻辑。
///
/// 使用方式：
/// ```swift
/// DragHandle()
///     .simultaneousGesture(DragGesture().onChanged { _ in window.performDrag(with: event) })
/// ```
public struct DragHandle: View {
    /// 是否正在被拖拽（由外层控制，影响点的配色与背景色）
    public let isDragging: Bool

    /// Hover 状态（内部自管，通过 onHover 响应）
    @State private var isHovered = false

    /// 初始化拖拽把手
    /// - Parameter isDragging: 外层传入的拖拽状态，默认 false
    public init(isDragging: Bool = false) {
        self.isDragging = isDragging
    }

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: 2×3 点阵 Canvas
            Canvas { ctx, size in
                // 圆点尺寸
                let dot = CGSize(width: 1.8, height: 1.8)
                // 列/行间距
                let step: CGFloat = 4
                // 计算整体点阵居中的起始坐标
                // 2 列占用宽度 = dot.width + step（列间距）
                // 3 行占用高度 = step*(rows-1) + dot.height = 4*2 + 1.8 = 9.8
                let originX = (size.width - dot.width - step) / 2
                let originY = (size.height - dot.height - step * 2) / 2
                for col in 0..<2 {
                    for row in 0..<3 {
                        let rect = CGRect(
                            x: originX + CGFloat(col) * step,
                            y: originY + CGFloat(row) * step,
                            width: dot.width,
                            height: dot.height
                        )
                        ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    }
                }
            }
            .frame(width: 14, height: 28)
            .background(
                RoundedRectangle(cornerRadius: SliceRadius.tight)
                    .fill(backgroundFill)
            )
            .onHover { hovering in
                isHovered = hovering
                // 切换 macOS 系统游标：hover 时换成 openHand，离开时恢复
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            // MARK: 右侧分隔竖线，16pt 高 / 1pt 宽，左右各 3pt 间距
            Rectangle()
                .fill(SliceColor.divider)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 3)
        }
    }

    // MARK: - 私有计算属性

    /// 根据拖拽状态决定点的颜色
    private var dotColor: Color {
        isDragging ? SliceColor.accent : SliceColor.textTertiary
    }

    /// 根据拖拽 / hover 状态决定背景填充色
    private var backgroundFill: Color {
        if isDragging { return SliceColor.accentFillLight }
        if isHovered { return SliceColor.hoverFill }
        return .clear
    }
}
