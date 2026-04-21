import AppKit
import SwiftUI

/// SwiftUI 对 `NSVisualEffectView` 的薄封装
///
/// SwiftUI macOS 原生虽然提供 `.regularMaterial` 等 `Material` 语义，但 `NSVisualEffectView`
/// 可以精细控制 `material`（hudWindow / sidebar / popover / windowBackground）和
/// `blendingMode`（behindWindow / withinWindow），对 HUD 窗口观感更可控。
///
/// 使用方式：
/// ```swift
/// SomeView()
///     .background(VisualEffectView(material: .hudWindow))
/// ```
/// 或通过便利 modifier `.glassBackground(_:)`（见 Modifiers/GlassBackground.swift）。
public struct VisualEffectView: NSViewRepresentable {
    /// 毛玻璃材质类型
    public let material: NSVisualEffectView.Material
    /// 混合模式：behindWindow 透出桌面；withinWindow 透出同窗口底层
    public let blendingMode: NSVisualEffectView.BlendingMode
    /// 活动状态：固定 `.active` 保证毛玻璃不因窗口失焦变暗
    public let state: NSVisualEffectView.State

    /// 构造
    /// - Parameters:
    ///   - material: 材质类型，默认 hudWindow（最适合浮层）
    ///   - blendingMode: 混合模式，默认 behindWindow
    ///   - state: 活动状态，默认 active（避免失焦变浊）
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    /// 创建底层 NSVisualEffectView
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    /// 响应 SwiftUI 状态变更（material / blending 切换时同步到 AppKit 层）
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
