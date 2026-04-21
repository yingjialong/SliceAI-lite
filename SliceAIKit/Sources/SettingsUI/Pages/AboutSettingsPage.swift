// SliceAIKit/Sources/SettingsUI/Pages/AboutSettingsPage.swift
//
// 关于页：展示版本信息、开源声明与 GitHub 链接。
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - AboutSettingsPage

/// 关于设置页
///
/// 展示当前应用版本号（从 Bundle 读取）、开源声明与 GitHub 仓库链接。
/// 无需视图模型注入，页面为纯展示态。
///
/// 构造无参数，与 `SettingsScene` 的调用签名 `AboutSettingsPage()` 一致。
public struct AboutSettingsPage: View {

    // swiftlint:disable force_unwrapping
    // GitHub 仓库 URL（硬编码常量，字符串字面量保证合法，强制解包安全）
    private let githubURL = URL(string: "https://github.com/mjj0903/SliceAI")!
    // swiftlint:enable force_unwrapping

    /// 从 Bundle 读取版本号；未找到时回退到 "Unknown"
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// 从 Bundle 读取 Build 号；未找到时回退到 "-"
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    /// 构造关于页（无参数）
    public init() {}

    public var body: some View {
        SettingsPageShell(title: "关于", subtitle: "版本信息与开源声明。") {
            // 版本信息卡片
            versionCard

            // 开源声明卡片
            openSourceCard
        }
    }

    // MARK: - 版本信息卡片

    /// 应用版本号 + Build 号卡片
    private var versionCard: some View {
        SectionCard("版本") {
            SettingsRow("应用版本") {
                Text("v\(appVersion) (\(buildNumber))")
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textSecondary)
            }

            SettingsRow("平台") {
                Text("macOS 14 Sonoma+")
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textSecondary)
            }
        }
    }

    // MARK: - 开源声明卡片

    /// MIT License 声明 + GitHub 链接卡片
    private var openSourceCard: some View {
        SectionCard("开源") {
            VStack(alignment: .leading, spacing: SliceSpacing.base) {
                // 许可证说明
                Text("SliceAI 以 MIT License 开源，欢迎贡献代码与 PR。")
                    .font(SliceFont.callout)
                    .foregroundColor(SliceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // GitHub 链接按钮
                Link(destination: githubURL) {
                    HStack(spacing: SliceSpacing.base) {
                        Image(systemName: "safari")
                            .font(.system(size: 14))
                        Text("在 GitHub 查看源码")
                            .font(SliceFont.body)
                    }
                    .foregroundColor(SliceColor.accentText)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, SliceSpacing.base)
        }
    }
}
