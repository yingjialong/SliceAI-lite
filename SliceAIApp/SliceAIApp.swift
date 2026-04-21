// SliceAIApp/SliceAIApp.swift
import AppKit
import SwiftUI

/// 应用入口（`@main`）。
///
/// 设计说明：
///   - 真正的 AppKit 生命周期由 `AppDelegate` 承载；这里只是 SwiftUI App 协议的外壳；
///   - 并不通过 SwiftUI 的 `Settings` scene 驱动设置界面——设置窗口由
///     `AppDelegate.showSettings()` 主动创建，以便控制样式和复用。这里保留一个
///     空的 `Settings { EmptyView() }` 仅为满足 `App.body` 协议要求，不会被用户看到。
@main
struct SliceAIApp: App {

    /// 绑定 AppDelegate；`@NSApplicationDelegateAdaptor` 确保其在进程生命周期内唯一存在
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 空 Settings scene：真正的 Settings 窗口由 AppDelegate.showSettings() 触发。
        // 保留此 no-op scene 是为了满足 SwiftUI `App` 协议对 `body` 至少一个 Scene 的要求。
        Settings {
            EmptyView()
        }
    }
}
