import AppKit
import Foundation
import SliceCore

/// 抽象"按下 ⌘C"的能力，便于测试
public protocol CopyKeystrokeInvoking: Sendable {
    /// 模拟系统级 ⌘C 按键以触发前台 App 把选中文字写入剪贴板
    func sendCopy() async throws
}

/// 提供前台窗口信息，便于测试
public struct FocusInfo: Sendable {
    public let bundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint

    /// 构造一次前台焦点信息快照，用于补全 SelectionReadResult 中的来源元数据
    public init(bundleID: String, appName: String, url: URL?, screenPoint: CGPoint) {
        self.bundleID = bundleID
        self.appName = appName
        self.url = url
        self.screenPoint = screenPoint
    }
}

/// 基于"备份剪贴板 + 模拟 ⌘C + 读 + 恢复"路径的选中文字读取
///
/// 该类型本身只保存不可变依赖（`any PasteboardProtocol`、`any CopyKeystrokeInvoking`、
/// 不可变闭包与数值），依赖均已约束为 `Sendable`。使用 `@unchecked Sendable` 是为了
/// 让编译器接受存在类型（`any`）成员的类在严格并发下被跨 actor 共享。
public final class ClipboardSelectionSource: SelectionSource, @unchecked Sendable {

    private let pasteboard: any PasteboardProtocol
    private let copyInvoker: any CopyKeystrokeInvoking
    private let focusProvider: @Sendable () -> FocusInfo?
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval

    /// 构造剪贴板回退式 SelectionSource
    /// - Parameters:
    ///   - pasteboard: 剪贴板抽象，生产环境注入 `SystemPasteboard()`
    ///   - copyInvoker: ⌘C 注入器，生产环境注入真实 CGEvent 实现
    ///   - focusProvider: 返回当前前台 App 信息的闭包；nil 表示无法读取
    ///   - pollInterval: 轮询剪贴板 changeCount 的间隔，默认 10ms
    ///   - timeout: 最长等待时间；超时后判定为读取失败，默认 150ms
    public init(
        pasteboard: any PasteboardProtocol,
        copyInvoker: any CopyKeystrokeInvoking,
        focusProvider: @escaping @Sendable () -> FocusInfo?,
        pollInterval: TimeInterval = 0.01,
        timeout: TimeInterval = 0.15
    ) {
        self.pasteboard = pasteboard
        self.copyInvoker = copyInvoker
        self.focusProvider = focusProvider
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    /// 读取当前选中文字；流程为 "备份 -> ⌘C -> 轮询 -> 读取 -> 恢复"
    public func readSelection() async throws -> SelectionReadResult? {
        // 1. 备份现有剪贴板内容：记录 changeCount 用于检测变化，缓存字符串用于恢复
        let originalChange = pasteboard.changeCount
        let originalString = pasteboard.string(forType: .string)

        // 2. 发 ⌘C，让前台 App 把选中文字写入剪贴板
        try await copyInvoker.sendCopy()

        // 3. 轮询等待 changeCount 变化；到 deadline 仍未变即视为未选中文字
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != originalChange { break }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        let changed = pasteboard.changeCount != originalChange
        let text = changed ? pasteboard.string(forType: .string) : nil

        // 4. 恢复原剪贴板（只有真的改变时才恢复，避免不必要的 changeCount 增长）
        if changed {
            pasteboard.clearContents()
            if let originalString {
                _ = pasteboard.setString(originalString, forType: .string)
            }
        }

        // 5. 空文本或无前台焦点信息时，返回 nil
        guard let text, !text.isEmpty else { return nil }
        guard let focus = focusProvider() else { return nil }
        return SelectionReadResult(
            text: text,
            appBundleID: focus.bundleID,
            appName: focus.appName,
            url: focus.url,
            screenPoint: focus.screenPoint,
            source: .clipboardFallback
        )
    }
}
