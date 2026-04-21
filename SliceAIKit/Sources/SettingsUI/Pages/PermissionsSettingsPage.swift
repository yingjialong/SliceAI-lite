// SliceAIKit/Sources/SettingsUI/Pages/PermissionsSettingsPage.swift
//
// 权限设置页：展示辅助功能授权状态，提供引导入口。
import DesignSystem
import Permissions
import SliceCore
import SwiftUI

// MARK: - PermissionsSettingsPage

/// 权限设置页
///
/// 通过 `AccessibilityMonitor`（每秒轮询 AX API）实时反映辅助功能权限状态，
/// 提供"打开系统设置"按钮引导用户完成授权。
///
/// 设计决策：`AccessibilityMonitor` 在视图内部以 `@StateObject` 持有，
/// 生命周期随页面视图存在，切走后自动 `stopMonitoring()` 释放计时器。
///
/// 构造无参数，与 `SettingsScene` 的调用签名 `PermissionsSettingsPage()` 一致。
public struct PermissionsSettingsPage: View {

    /// 辅助功能权限监控器：每秒轮询 isTrusted 状态
    @StateObject private var monitor = AccessibilityMonitor()

    /// 构造权限设置页（无参数）
    public init() {}

    public var body: some View {
        SettingsPageShell(title: "权限", subtitle: "管理应用所需的系统权限。") {
            accessibilityCard
        }
        .onAppear {
            // 页面出现时启动轮询，确保状态实时同步
            monitor.startMonitoring()
        }
        .onDisappear {
            // 页面消失时停止轮询，释放计时器资源
            monitor.stopMonitoring()
        }
    }

    // MARK: - 辅助功能权限卡片

    /// 辅助功能授权状态卡片
    private var accessibilityCard: some View {
        SectionCard("辅助功能") {
            HStack(spacing: SliceSpacing.xxl) {
                // 左侧：状态灯 + 标题 + 描述
                VStack(alignment: .leading, spacing: SliceSpacing.sm) {
                    HStack(spacing: SliceSpacing.base) {
                        // 状态指示灯：已授权绿色，未授权红色
                        Circle()
                            .fill(monitor.isTrusted ? SliceColor.success : SliceColor.error)
                            .frame(width: 8, height: 8)

                        Text(monitor.isTrusted ? "已授权" : "未授权")
                            .font(SliceFont.bodyEmphasis)
                            .foregroundColor(
                                monitor.isTrusted ? SliceColor.success : SliceColor.error
                            )
                    }

                    Text("划词捕获与全局快捷键需要辅助功能（Accessibility）权限。")
                        .font(SliceFont.callout)
                        .foregroundColor(SliceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // 右侧：未授权时显示"打开系统设置"按钮；已授权时不显示按钮
                if !monitor.isTrusted {
                    Button("打开系统设置") {
                        // 调用 requestTrust：触发系统授权对话框并打开偏好面板
                        monitor.requestTrust()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SliceColor.accent)
                }
            }
            .padding(.vertical, SliceSpacing.base)
        }
    }
}
