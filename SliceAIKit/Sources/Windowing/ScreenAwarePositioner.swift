import CoreGraphics

/// 计算工具栏等浮窗的屏幕坐标原点，考虑屏幕边界避让
///
/// 坐标约定：所有坐标均为 AppKit 屏幕坐标（左下原点）。
/// 典型用法：传入选区中心点或鼠标点作为 `anchor`，默认在锚点下方放置窗口；
/// 当下方空间不足时翻到上方；水平方向始终夹紧到屏幕可见区内。
public struct ScreenAwarePositioner: Sendable {

    /// 无状态构造器，供调用方直接实例化
    public init() {}

    /// 根据锚点、尺寸与屏幕可见区计算窗口 origin
    ///
    /// - Parameters:
    ///   - anchor: 锚点（选区中心或鼠标位置），屏幕坐标（左下原点）
    ///   - size: 窗口大小
    ///   - screen: 窗口所在屏幕的 `visibleFrame`
    ///   - offset: 锚点与窗口之间的纵向距离
    /// - Returns: 窗口 origin，屏幕坐标（左下原点）
    public func position(anchor: CGPoint,
                         size: CGSize,
                         screen: CGRect,
                         offset: CGFloat) -> CGPoint {
        // 默认放锚点下方：水平居中对齐，垂直方向留出 offset 间距
        var x = anchor.x - size.width / 2
        var y = anchor.y - offset - size.height

        // 下越界：翻到锚点上方（保留 offset 间距），避免被屏幕底部遮挡
        if y < screen.minY {
            y = anchor.y + offset
        }
        // 上越界（极端情况，如锚点在顶部且窗口很高）：夹紧到屏幕顶部以内
        if y + size.height > screen.maxY {
            y = screen.maxY - size.height
        }
        // 水平夹紧：先按右缘限制上限，再按左缘限制下限，确保窗口完整在屏幕内
        x = max(screen.minX, min(x, screen.maxX - size.width))
        return CGPoint(x: x, y: y)
    }
}
