// SliceAIKit/Sources/Permissions/OnboardingFlow.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 首次启动引导视图，按 欢迎 → 授予辅助功能权限 两步走完首开流程。
///
/// 布局：560×520 固定尺寸，`SliceColor.surface` 底色。
/// 顶部 `StepIndicator` 显示两步进度；中部 `switch step` 切换内容；
/// 底部 footer 左侧"稍后/返回"文字按钮 + 右侧 `PillButton(.primary)` 主按钮。
///
/// 视图由 `AppDelegate` 在首次启动时呈现，完成或跳过时通过 ``onFinish`` 回调
/// 通知宿主推进运行时接线。Provider / API Key 的配置已从 Onboarding 移除，
/// 用户需在「设置 → Providers」中自行添加；错误态的 ErrorBlock 提供了
/// "打开设置"入口做兜底。`accessibilityMonitor` 由外部持有以便轮询
/// 生命周期可控，视图只在第 2 步 `onAppear` 时启动监听。
public struct OnboardingFlow: View {

    // MARK: - 注入依赖

    /// 权限监听器；由外部注入，视图通过 `@ObservedObject` 订阅其状态变化。
    @ObservedObject var accessibilityMonitor: AccessibilityMonitor

    /// 完成或跳过时触发的回调；宿主据此关闭窗口并接线运行时。
    let onFinish: () -> Void

    // MARK: - 内部状态

    /// 当前展示的步骤；初始值为欢迎页。
    @State private var step: Step = .welcome

    // MARK: - 常量

    /// StepIndicator 步骤数据（id 从 1 开始，符合 StepIndicator.Step 约定）。
    private let stepItems = [
        StepIndicator.Step(id: 1, label: "欢迎"),
        StepIndicator.Step(id: 2, label: "权限")
    ]

    // MARK: - Init

    /// 创建引导视图
    /// - Parameters:
    ///   - accessibilityMonitor: 由宿主持有的权限监听器，用于驱动第 2 步 UI 状态
    ///   - onFinish: 完成或跳过时的回调；宿主据此关闭窗口并接线运行时
    public init(accessibilityMonitor: AccessibilityMonitor,
                onFinish: @escaping () -> Void) {
        self.accessibilityMonitor = accessibilityMonitor
        self.onFinish = onFinish
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部：StepIndicator 进度条
            stepIndicatorBar

            // 中部：步骤内容区域（flex 填充剩余空间）
            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeStep()
                case .accessibility:
                    OnboardingAccessibilityStep(monitor: accessibilityMonitor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 分隔线
            Divider()
                .padding(.horizontal, 32)

            // 底部：导航 footer
            footerBar
        }
        .frame(width: 560, height: 520)
        .background(SliceColor.surface)
    }

    // MARK: - Step Indicator

    /// 顶部步骤进度条区域。
    private var stepIndicatorBar: some View {
        VStack(spacing: 0) {
            StepIndicator(steps: stepItems, currentIndex: step.index)
                .padding(.top, 32)
                .padding(.bottom, 24)
            Divider()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Footer

    /// 底部导航 footer：左侧文字按钮（稍后/返回） + 右侧主按钮。
    private var footerBar: some View {
        HStack {
            // 左侧：灰色文字按钮，欢迎页显示"稍后再说"，权限页显示"返回"
            Button {
                handleSecondaryAction()
            } label: {
                Text(step == .welcome ? "稍后再说" : "返回")
                    .font(.system(size: 13))
                    .foregroundColor(SliceColor.textTertiary)
            }
            .buttonStyle(.plain)

            Spacer()

            // 右侧：主行动按钮；权限页要求已授权
            PillButton(primaryButtonTitle, style: .primary) {
                handlePrimaryAction()
            }
            .disabled(!isPrimaryEnabled)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
    }

    /// 当前步骤主按钮标题。
    private var primaryButtonTitle: String {
        switch step {
        case .welcome:       return "开始"
        case .accessibility: return "完成"
        }
    }

    /// 主按钮是否可点击。
    private var isPrimaryEnabled: Bool {
        switch step {
        case .welcome:       return true
        case .accessibility: return accessibilityMonitor.isTrusted
        }
    }

    // MARK: - Actions

    /// 主按钮点击：推进步骤或完成。
    private func handlePrimaryAction() {
        switch step {
        case .welcome:
            // 进入权限步骤
            step = .accessibility
        case .accessibility:
            // 已授权，完成引导流程
            onFinish()
        }
    }

    /// 次按钮点击："稍后再说"或"返回"。
    private func handleSecondaryAction() {
        switch step {
        case .welcome:
            // 跳过整个 onboarding
            onFinish()
        case .accessibility:
            // 返回欢迎页
            step = .welcome
        }
    }

    // MARK: - Step Enum

    /// 引导视图内部的步骤标识及对应的 StepIndicator 下标。
    enum Step {
        case welcome, accessibility

        /// 对应 StepIndicator.currentIndex（0-based）。
        var index: Int {
            switch self {
            case .welcome:       return 0
            case .accessibility: return 1
            }
        }
    }
}

// MARK: - Step 1: Welcome

/// 第 1 步欢迎页内容（fileprivate，仅供 OnboardingFlow 使用）。
private struct OnboardingWelcomeStep: View {

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HeroIcon(gradient: HeroIcon.Preset.violet, symbol: "sparkles", isSFSymbol: true)
                .padding(.bottom, 24)
            Text("欢迎使用 SliceAI")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(SliceColor.textPrimary)
                .padding(.bottom, 8)
            Text("划词即调用大模型的原生工具栏")
                .font(.system(size: 15))
                .foregroundColor(SliceColor.textSecondary)
                .padding(.bottom, 32)
            VStack(alignment: .leading, spacing: 12) {
                infoRow(index: 1, text: "**划词浮条**：选中文字即弹出操作按钮，零打断")
                infoRow(index: 2, text: "**⌥Space 面板**：全局唤起命令面板，Raycast 风格")
            }
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    /// 带序号圆形徽标的说明行，文字支持 markdown `**加粗**`。
    private func infoRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(SliceColor.accentFillLight)
                    .frame(width: 22, height: 22)
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SliceColor.accentText)
            }
            // Text(.init(text)) 通过 LocalizedStringKey 初始化，启用行内 markdown
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundColor(SliceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Step 2: Accessibility

/// 第 2 步辅助功能权限页内容（fileprivate，仅供 OnboardingFlow 使用）。
private struct OnboardingAccessibilityStep: View {

    /// 注入权限监听器（ObservedObject 不能跨 struct 直接传，通过参数传引用）
    @ObservedObject var monitor: AccessibilityMonitor

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HeroIcon(gradient: HeroIcon.Preset.indigo, symbol: "shield.checkered", isSFSymbol: true)
                .padding(.bottom, 24)
            Text("授予辅助功能权限")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(SliceColor.textPrimary)
                .padding(.bottom, 8)
            Text("SliceAI 通过辅助功能 API 读取你选中的文字，无法使用任何其他数据。")
                .font(.system(size: 14))
                .foregroundColor(SliceColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.bottom, 24)
            statusBar
            Spacer()
            HStack(spacing: 12) {
                PillButton("打开辅助功能设置", icon: "arrow.up.right.square", style: .secondary) {
                    monitor.requestTrust()
                }
                PillButton("立即检测", icon: "arrow.clockwise", style: .secondary) {
                    // 手动触发一次权限读取，不等待轮询周期（1s）
                    monitor.refresh()
                }
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 40)
        // 进入本步骤时启动轮询，用户授权后 UI 会自动刷新
        .onAppear { monitor.startMonitoring() }
    }

    /// 权限状态条：已授权绿色，未授权警告黄。
    @ViewBuilder
    private var statusBar: some View {
        if monitor.isTrusted {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(SliceColor.success)
                Text("已获得辅助功能权限")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SliceColor.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(SliceColor.success.opacity(0.12)))
            .padding(.bottom, 20)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(SliceColor.warning)
                Text("等待授权 — 前往「隐私与安全性 → 辅助功能」开启")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SliceColor.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(SliceColor.warningFill))
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("OnboardingFlow · Welcome") {
    OnboardingFlow(
        accessibilityMonitor: AccessibilityMonitor(),
        onFinish: {}
    )
}
#endif
