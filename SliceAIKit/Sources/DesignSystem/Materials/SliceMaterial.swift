import AppKit

/// 毛玻璃材质的语义枚举（对应 spec §3.7）
///
/// 每个场景绑定到一个具体的 `NSVisualEffectView.Material`；UI 代码通过
/// `SliceMaterial.hud` 引用，而非直接裸露 AppKit 枚举值。
public enum SliceMaterial {
    /// 悬浮工具栏 / 结果面板（最浓郁的毛玻璃）
    case hud
    /// 设置侧栏（较柔和）
    case sidebar
    /// 命令面板（介于 hud 与 popover 之间）
    case popover
    /// 设置窗口主区
    case window

    /// 对应的 AppKit 材质值
    public var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hud:     return .hudWindow
        case .sidebar: return .sidebar
        case .popover: return .popover
        case .window:  return .windowBackground
        }
    }
}
