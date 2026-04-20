import AppKit
import XCTest
@testable import SelectionCapture

/// 假的 NSPasteboard 实现，记录调用次数与返回固定内容，便于注入到 ClipboardSelectionSource
final class FakePasteboard: PasteboardProtocol, @unchecked Sendable {
    /// 由测试直接控制的 changeCount 值
    var changeCountValue = 0
    /// 当前剪贴板保存的字符串
    var storedString: String?
    /// clearContents 被调用次数
    var clearCalls = 0
    /// setString 调用记录，便于验证恢复动作
    var setStringCalls: [(String, NSPasteboard.PasteboardType)] = []
    /// 模拟"系统发 ⌘C"回调：设置这个闭包被调用时修改内部状态
    var onExpectingCopy: (() -> Void)?

    var changeCount: Int { changeCountValue }

    /// 读取指定类型的字符串，这里无论类型一律返回 storedString
    func string(forType type: NSPasteboard.PasteboardType) -> String? { storedString }

    /// 模拟清空剪贴板：清空字符串、递增 changeCount 并统计调用次数
    @discardableResult
    func clearContents() -> Int {
        clearCalls += 1
        storedString = nil
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

    /// 返回 nil，测试场景下无需关心完整的 pasteboardItems
    func pasteboardItems() -> [NSPasteboardItem]? { nil }

    /// 返回 true，测试场景下无需真实写入对象
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool { true }
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

    /// 正常路径：⌘C 后剪贴板被写入新文本，readSelection 应返回该文本
    /// 并在返回前恢复原剪贴板内容
    func test_readSelection_returnsText_andRestoresOriginal() async throws {
        let pb = FakePasteboard()
        pb.storedString = "original"
        pb.changeCountValue = 5

        let source = ClipboardSelectionSource(
            pasteboard: pb,
            copyInvoker: FakeCopyInvoker(pb, simulate: "selected text"),
            focusProvider: {
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
        // 原剪贴板应被恢复
        XCTAssertEqual(pb.storedString, "original")
    }

    /// 超时路径：⌘C 后剪贴板未变化，readSelection 应返回 nil 且不破坏原剪贴板
    func test_readSelection_timeout_returnsNil() async throws {
        let pb = FakePasteboard()
        pb.storedString = "orig"
        pb.changeCountValue = 1

        let source = ClipboardSelectionSource(
            pasteboard: pb,
            copyInvoker: FakeCopyInvoker(pb, simulate: nil),    // 剪贴板不变
            focusProvider: { FocusInfo(bundleID: "x", appName: "x", url: nil, screenPoint: .zero) },
            pollInterval: 0.001,
            timeout: 0.05
        )
        let result = try await source.readSelection()
        XCTAssertNil(result)
        XCTAssertEqual(pb.storedString, "orig")
    }
}
