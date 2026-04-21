import AppKit
import ApplicationServices
import Foundation

/// 监控 Accessibility 权限状态。
///
/// AX API 不提供权限变更通知，因此采用 1s 间隔轮询来同步 ``isTrusted`` 状态。
/// 由 onboarding 流程与 AppDelegate 消费，驱动授权引导与特性开关。
@MainActor
public final class AccessibilityMonitor: ObservableObject {

    /// 当前进程是否已被授予 Accessibility 权限。
    @Published public private(set) var isTrusted: Bool = false

    /// 轮询使用的计时器，仅在主线程创建与失效。
    private var timer: Timer?

    /// 构造时立即读取一次权限状态，避免 UI 首帧出现错误的 `false`。
    public init() {
        refresh()
    }

    /// 启动轮询（每 1 秒检查一次）。
    ///
    /// 多次调用安全：会先让旧计时器失效再重建，避免并行触发。
    public func startMonitoring() {
        // 先同步一次，保证调用方立刻拿到最新状态
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer 回调非 Sendable，显式切回 MainActor 再刷新状态
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 停止轮询，释放计时器资源。
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// 请求权限并打开系统偏好面板（非阻塞，用户授予后由 monitor 自动反映）。
    ///
    /// 首次调用 `AXIsProcessTrustedWithOptions` 会弹出系统授权提示；
    /// 后续调用为 no-op。随后打开「隐私与安全性 → 辅助功能」便于用户手动开关。
    public func requestTrust() {
        // Swift 6 严格并发下 `kAXTrustedCheckOptionPrompt` 作为可变全局被标为 non-Sendable，
        // 直接使用其稳定的字符串值作为字典 key（自 10.9 起即为 "AXTrustedCheckOptionPrompt"）。
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options: [CFString: Any] = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        // 打开 Accessibility 偏好面板（macOS 13+ 有效）
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 从 AX API 读取并发布最新的权限状态。
    ///
    /// 设为 public 以便外部（如 OnboardingFlow 的"立即检测"按钮）强制刷新，
    /// 无需等待下一个轮询周期（1s）。
    public func refresh() {
        isTrusted = AXIsProcessTrusted()
    }
}
