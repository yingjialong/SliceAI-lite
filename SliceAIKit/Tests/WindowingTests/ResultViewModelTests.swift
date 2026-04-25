import XCTest
@testable import Windowing

/// `ResultViewModel.append` 在 thinking on/off 下的 reasoning 累积行为测试
///
/// 锁定 bug fix：DeepSeek V4 即便收到 disable 模板（thinking.type=disabled）仍可能
/// 在 SSE 中回传 reasoning_content，UI 层必须按 `thinkingEnabled` 决定是否累积，
/// 避免：(a) "思考过程" disclosure 在 thinking off 下出现，(b) 反复 toggle 时
/// 旧 reasoning 文本残留。
@MainActor
final class ResultViewModelTests: XCTestCase {

    /// thinking off 时收到 reasoning delta：仅累积正文，reasoning 完全丢弃
    func test_append_thinkingDisabled_dropsReasoning() {
        let vm = ResultViewModel()
        vm.thinkingEnabled = false

        vm.append(delta: "hello ", reasoningDelta: "ignored thinking text")
        vm.append(delta: "world", reasoningDelta: "more ignored")

        XCTAssertEqual(vm.text, "hello world")
        XCTAssertEqual(vm.accumulatedReasoning, "")
    }

    /// thinking on 时收到 reasoning delta：正文与 reasoning 同时累积
    func test_append_thinkingEnabled_accumulatesReasoning() {
        let vm = ResultViewModel()
        vm.thinkingEnabled = true

        vm.append(delta: "answer ", reasoningDelta: "thought-1 ")
        vm.append(delta: "here", reasoningDelta: "thought-2")

        XCTAssertEqual(vm.text, "answer here")
        XCTAssertEqual(vm.accumulatedReasoning, "thought-1 thought-2")
    }

    /// thinking off 且仅有 reasoning delta（无正文）的 chunk：状态保持 .thinking 不前进
    /// 防止 reasoning-only chunk 在 thinking off 下错误地切到 .streaming 触发 ProgressStripe 闪烁
    func test_append_thinkingDisabled_reasoningOnly_keepsThinkingState() {
        let vm = ResultViewModel()
        vm.thinkingEnabled = false
        vm.streamingState = .thinking

        vm.append(delta: "", reasoningDelta: "noise")

        XCTAssertEqual(vm.streamingState, .thinking)
        XCTAssertEqual(vm.text, "")
        XCTAssertEqual(vm.accumulatedReasoning, "")
    }

    /// reset() 清空 reasoning + 折叠 disclosure，避免上次 stream 残留串场到下次
    func test_reset_clearsReasoningStateAndCollapsesDisclosure() {
        let vm = ResultViewModel()
        vm.thinkingEnabled = true
        vm.append(delta: "x", reasoningDelta: "r")
        vm.reasoningExpanded = true

        vm.reset(toolName: "t", model: "m")

        XCTAssertEqual(vm.accumulatedReasoning, "")
        XCTAssertFalse(vm.reasoningExpanded)
    }
}

/// `ResultPanel` generation counter 行为测试
///
/// 锁定 race fix：streamTask 在 cancel 后仍可能 append 一个已 buffer 的 chunk。
/// generation stamp 让 ResultPanel 静默丢弃旧 stream 的残留 chunk，
/// 避免污染新一次 open() 的 panel 内容。
@MainActor
final class ResultPanelGenerationTests: XCTestCase {

    /// 初始 generation 必须为 0（任何带 gen=0 的 stale 调用都该被忽略——除非真的有人 open 之前就调，理论上不该发生）
    func test_initialGeneration_isZero() {
        let panel = ResultPanel()
        XCTAssertEqual(panel.currentGeneration(), 0)
    }

    /// open() 单调递增 generation，让旧 streamTask 的 stamp 即时失效
    func test_openIncrementsGenerationMonotonically() {
        let panel = ResultPanel()
        panel.open(toolName: "T", model: "M", anchor: .zero)
        XCTAssertEqual(panel.currentGeneration(), 1)
        panel.open(toolName: "T", model: "M", anchor: .zero)
        XCTAssertEqual(panel.currentGeneration(), 2)
        panel.open(toolName: "T", model: "M", anchor: .zero)
        XCTAssertEqual(panel.currentGeneration(), 3)
    }
}
