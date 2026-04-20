import AppKit
import CoreGraphics

/// 通过 CGEvent 模拟按下 ⌘C 的生产实现
///
/// 需要 App 获得 Accessibility（辅助功能）权限，否则 `post(tap:)` 会被系统静默吞掉，
/// 前台 App 无法收到按键事件；调用方在调用前应自行完成权限检测与引导。
public struct SystemCopyKeystrokeInvoker: CopyKeystrokeInvoking {

    /// 默认构造器；本类型无状态，创建开销可以忽略
    public init() {}

    /// 合成一次 ⌘C 按键并通过 HID event tap 投递到前台 App
    ///
    /// 实现要点：
    /// 1. 使用 `.hidSystemState` 作为事件源，保证修饰键状态与真实键盘一致；
    /// 2. C 键的 virtual keycode 为 8（`kVK_ANSI_C`）；
    /// 3. keyDown 与 keyUp 都需要带 `.maskCommand`，否则目标 App 只会收到普通 "c"；
    /// 4. `post(tap: .cghidEventTap)` 投递至系统最底层的 HID tap，对绝大多数前台 App 有效。
    public func sendCopy() async throws {
        // 尝试创建事件源；极少数情况下系统可能返回 nil，此时降级为 nil 源（仍可工作）
        let source = CGEventSource(stateID: .hidSystemState)

        // 显式解包：若事件创建失败（通常意味着系统资源异常），直接返回而不崩溃
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        else {
            return
        }

        // 为两个事件都打上 Command 修饰键标志，组合成 ⌘C
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // 顺序投递 keyDown -> keyUp，至 HID event tap，由系统分发给前台 App
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
