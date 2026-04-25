// SliceAIApp/AppDelegate+Thinking.swift
import AppKit
import SliceCore

/// AppDelegate 的 thinking-mode toggle 相关逻辑
///
/// 拆出独立 extension 文件的原因：AppDelegate 主文件加入 thinking 桥接代码后
/// 行数超出 SwiftLint file_length 警告阈值（500 行）。Extension 不允许声明
/// stored property，所以 `thinkingToggleInFlight` 字段仍留在主类，仅方法
/// `shouldShowThinkingToggle` 与 `makeToggleThinkingAction` 移过来。
extension AppDelegate {

    /// thinking 切换按钮显隐逻辑：provider.thinking 非 nil，且 byModel 时 tool 有 thinkingModelId
    ///
    /// 使用 settingsViewModel.configuration（@MainActor @Published）同步读取，无需 await。
    func shouldShowThinkingToggle(for tool: SliceCore.Tool) -> Bool {
        let provider = container.settingsViewModel.configuration.providers
            .first(where: { $0.id == tool.providerId })
        guard let thinking = provider?.thinking else { return false }
        switch thinking {
        case .byModel:
            return tool.thinkingModelId != nil
        case .byParameter:
            return true
        }
    }

    /// 构造 thinking 切换 closure：先取消当前 stream，持久化后用最新 tool 快照重新执行
    ///
    /// 关键点：
    /// - 必须先 `cancelStream()` 再 `execute()`，否则旧 stream 会继续 append chunk
    /// - `cancelStream` 由 caller 注入（捕获 streamTask），helper 不持有 streamTask 引用
    /// - toggleThinking 后 `tool` 局部变量 stale，需从最新 configuration 取 fresh 快照
    /// - thinkingToggleInFlight 防止快速连点派出多个并发 task；defer 保证总会清零
    func makeToggleThinkingAction(
        for tool: SliceCore.Tool,
        payload: SelectionPayload,
        cancelStream: @escaping @Sendable () -> Void
    ) -> (@MainActor () -> Void) {
        { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // 防止快速连点：上一个 toggle 完整跑完前忽略后续点击
                guard !self.thinkingToggleInFlight else { return }
                self.thinkingToggleInFlight = true
                defer { self.thinkingToggleInFlight = false }
                cancelStream()
                await self.container.settingsViewModel.toggleThinking(for: tool.id)
                guard let fresh = self.container.settingsViewModel.configuration.tools
                    .first(where: { $0.id == tool.id }) else { return }
                // swiftlint:disable:next line_length
                Self.log.info("onToggleThinking: re-run tool=\(fresh.name, privacy: .public) enabled=\(fresh.thinkingEnabled, privacy: .public)")
                self.execute(tool: fresh, payload: payload)
            }
        }
    }
}
