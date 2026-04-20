import AppKit
import XCTest
@testable import SelectionCapture

/// 假的 NSPasteboard 实现，记录调用次数与返回固定内容，便于注入到 ClipboardSelectionSource
final class FakePasteboard: PasteboardProtocol, @unchecked Sendable {
    /// 由测试直接控制的 changeCount 值
    var changeCountValue = 0
    /// 当前剪贴板保存的字符串
    var storedString: String?
    /// 当前剪贴板保存的 items 快照（模拟富内容）
    var storedItems: [NSPasteboardItem]?
    /// clearContents 被调用次数
    var clearCalls = 0
    /// setString 调用记录，便于验证恢复动作
    var setStringCalls: [(String, NSPasteboard.PasteboardType)] = []
    /// writeObjects 调用记录，每次调用保存一次完整入参
    var writeObjectsCalls: [[any NSPasteboardWriting]] = []
    /// 模拟"系统发 ⌘C"回调：设置这个闭包被调用时修改内部状态
    var onExpectingCopy: (() -> Void)?

    var changeCount: Int { changeCountValue }

    /// 读取指定类型的字符串，这里无论类型一律返回 storedString
    func string(forType type: NSPasteboard.PasteboardType) -> String? { storedString }

    /// 模拟清空剪贴板：清空字符串与 items、递增 changeCount 并统计调用次数
    @discardableResult
    func clearContents() -> Int {
        clearCalls += 1
        storedString = nil
        storedItems = nil
        changeCountValue += 1
        return changeCountValue
    }

    /// 模拟写入剪贴板：记录参数、更新 storedString 与 changeCount
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        setStringCalls.append((string, type))
        storedString = string
        changeCountValue += 1
        return true
    }

    /// 返回测试 seed 的 items 快照；默认为 nil，模拟空剪贴板
    func pasteboardItems() -> [NSPasteboardItem]? { storedItems }

    /// 记录 writeObjects 的入参；同时递增 changeCount，模拟真实 pasteboard 的行为
    @discardableResult
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        writeObjectsCalls.append(objects)
        changeCountValue += 1
        return true
    }
}

/// 测试替身：直接给 source 注入"⌘C 后剪贴板里是什么"
final class FakeCopyInvoker: CopyKeystrokeInvoking, @unchecked Sendable {
    let pasteboard: FakePasteboard
    let simulatedText: String?

    /// 注入假剪贴板以及期望"模拟 ⌘C"后落到剪贴板上的文本（nil 表示不发生变化）
    init(_ pasteboard: FakePasteboard, simulate: String?) {
        self.pasteboard = pasteboard
        self.simulatedText = simulate
    }

    /// 模拟系统把选中文字写到剪贴板：如 simulatedText 为 nil，不变
    func sendCopy() async throws {
        if let text = simulatedText {
            pasteboard.storedString = text
            pasteboard.changeCountValue += 1
        }
    }
}

final class ClipboardSelectionSourceTests: XCTestCase {

    /// 正常路径：⌘C 后剪贴板被写入新文本，readSelection 应返回该文本，
    /// 并在返回前通过 writeObjects 恢复原 items 快照
    func test_readSelection_returnsText_andRestoresOriginal() async throws {
        let pb = FakePasteboard()
        // 种入一个字符串类型的 item，模拟用户原本剪贴板里的内容
        let originalItem = NSPasteboardItem()
        originalItem.setString("original", forType: .string)
        pb.storedItems = [originalItem]
        pb.storedString = "original"
        pb.changeCountValue = 5

        let source = ClipboardSelectionSource(
            pasteboard: pb,
            copyInvoker: FakeCopyInvoker(pb, simulate: "selected text"),
            focusProvider: { @MainActor @Sendable in
                FocusInfo(
                    bundleID: "com.apple.Safari",
                    appName: "Safari",
                    url: URL(string: "https://example.com"),
                    screenPoint: CGPoint(x: 10, y: 20)
                )
            },
            pollInterval: 0.001,
            timeout: 0.2
        )
        let result = try await source.readSelection()
        XCTAssertEqual(result?.text, "selected text")
        XCTAssertEqual(result?.source, .clipboardFallback)
        XCTAssertEqual(result?.appName, "Safari")
        // 应通过 writeObjects 恢复原 items，而不是 setString
        XCTAssertEqual(pb.writeObjectsCalls.count, 1)
        XCTAssertEqual(pb.writeObjectsCalls.last?.count, 1)
        XCTAssertTrue(pb.setStringCalls.isEmpty)
    }

    /// 超时路径：⌘C 后剪贴板未变化，readSelection 应返回 nil 且不破坏原剪贴板
    func test_readSelection_timeout_returnsNil() async throws {
        let pb = FakePasteboard()
        pb.storedString = "orig"
        pb.changeCountValue = 1

        let source = ClipboardSelectionSource(
            pasteboard: pb,
            copyInvoker: FakeCopyInvoker(pb, simulate: nil),    // 剪贴板不变
            focusProvider: { @MainActor @Sendable in
                FocusInfo(bundleID: "x", appName: "x", url: nil, screenPoint: .zero)
            },
            pollInterval: 0.001,
            timeout: 0.05
        )
        let result = try await source.readSelection()
        XCTAssertNil(result)
        XCTAssertEqual(pb.storedString, "orig")
        // 未变化时不应触发任何恢复动作
        XCTAssertTrue(pb.writeObjectsCalls.isEmpty)
        XCTAssertEqual(pb.clearCalls, 0)
    }

    /// 富内容恢复：原剪贴板含多类型 item（string + html），读取后应通过
    /// writeObjects 原样恢复，验证不再只保留 .string 导致的富内容丢失
    func test_readSelection_restoresFullPasteboardItems() async throws {
        let pb = FakePasteboard()
        // Seed with 2 items (simulating rich content: 纯文本 + HTML)
        let itemA = NSPasteboardItem()
        itemA.setString("rich content A", forType: .string)
        let itemB = NSPasteboardItem()
        itemB.setString("<html>rich</html>", forType: .html)
        pb.storedItems = [itemA, itemB]
        pb.storedString = "rich content A"
        pb.changeCountValue = 10

        let source = ClipboardSelectionSource(
            pasteboard: pb,
            copyInvoker: FakeCopyInvoker(pb, simulate: "selected"),
            focusProvider: { @MainActor @Sendable in
                FocusInfo(bundleID: "x", appName: "X", url: nil, screenPoint: .zero)
            },
            pollInterval: 0.001,
            timeout: 0.2
        )
        let result = try await source.readSelection()
        XCTAssertEqual(result?.text, "selected")
        // writeObjects 应至少被调用一次来恢复
        XCTAssertGreaterThanOrEqual(pb.writeObjectsCalls.count, 1)
        // 恢复的 items 应含 2 条
        XCTAssertEqual(pb.writeObjectsCalls.last?.count, 2)
        // 富内容不应被 setString 破坏性覆盖
        XCTAssertTrue(pb.setStringCalls.isEmpty)
    }
}
