import XCTest
@testable import SelectionCapture
@testable import SliceCore

/// 测试替身：按构造参数产出固定结果或抛出固定错误
///
/// 通过注入不同组合的 YieldingSource 覆盖 SelectionService 的四类分支：
/// 主路径成功 / 主路径返回 nil / 主路径抛错 / 主备均失败
private struct YieldingSource: SelectionSource {
    let result: SelectionReadResult?
    let throwsError: (any Error)?

    /// 构造一个可受控的 SelectionSource 测试替身
    init(result: SelectionReadResult? = nil, throwsError: (any Error)? = nil) {
        self.result = result
        self.throwsError = throwsError
    }

    /// 若注入了错误则抛出；否则直接返回预设结果
    func readSelection() async throws -> SelectionReadResult? {
        if let e = throwsError { throw e }
        return result
    }
}

final class SelectionServiceTests: XCTestCase {

    /// 测试样本：来源标记为 .accessibility，模拟主路径读取成功的结果
    private let sample = SelectionReadResult(
        text: "hello", appBundleID: "x", appName: "X",
        url: nil, screenPoint: .zero, source: .accessibility
    )

    /// 主路径成功时应直接返回其结果，不触发 fallback
    func test_prefersPrimarySourceWhenSuccess() async throws {
        let service = SelectionService(
            primary: YieldingSource(result: sample),
            fallback: YieldingSource(result: nil)
        )
        let payload = try await service.capture()
        XCTAssertEqual(payload?.text, "hello")
        XCTAssertEqual(payload?.source, .accessibility)
    }

    /// 主路径返回 nil（无选中）时应回退到 fallback
    func test_fallsBackWhenPrimaryReturnsNil() async throws {
        let fallbackResult = SelectionReadResult(
            text: "fb", appBundleID: "x", appName: "X",
            url: nil, screenPoint: .zero, source: .clipboardFallback
        )
        let service = SelectionService(
            primary: YieldingSource(result: nil),
            fallback: YieldingSource(result: fallbackResult)
        )
        let payload = try await service.capture()
        XCTAssertEqual(payload?.text, "fb")
        XCTAssertEqual(payload?.source, .clipboardFallback)
    }

    /// 主备均返回 nil 时整体返回 nil
    func test_returnsNilWhenBothFail() async throws {
        let service = SelectionService(
            primary: YieldingSource(result: nil),
            fallback: YieldingSource(result: nil)
        )
        let payload = try await service.capture()
        XCTAssertNil(payload)
    }

    /// 主路径抛错时应回退到 fallback，而不是把错误冒泡给调用方
    func test_fallsBackWhenPrimaryThrows() async throws {
        struct X: Error {}
        let service = SelectionService(
            primary: YieldingSource(throwsError: X()),
            fallback: YieldingSource(result: sample)
        )
        let payload = try await service.capture()
        XCTAssertEqual(payload?.text, "hello")
    }

    /// captureFromPrimaryOnly 路径：主路径为空时必须返回 nil，**不能**触碰 fallback。
    /// 这是避免被动触发路径（mouseUp）误用 Cmd+C 的关键契约。
    func test_captureFromPrimaryOnly_skipsFallbackWhenPrimaryReturnsNil() async {
        let fallbackResult = SelectionReadResult(
            text: "fallback-should-not-be-used",
            appBundleID: "x", appName: "X",
            url: nil, screenPoint: .zero, source: .clipboardFallback
        )
        let service = SelectionService(
            primary: YieldingSource(result: nil),
            fallback: YieldingSource(result: fallbackResult)
        )
        let payload = await service.captureFromPrimaryOnly()
        XCTAssertNil(payload, "captureFromPrimaryOnly 必须不走 fallback")
    }

    /// captureFromPrimaryOnly 路径：主路径有结果时正常返回
    func test_captureFromPrimaryOnly_returnsPrimaryWhenAvailable() async {
        let service = SelectionService(
            primary: YieldingSource(result: sample),
            fallback: YieldingSource(result: nil)
        )
        let payload = await service.captureFromPrimaryOnly()
        XCTAssertEqual(payload?.text, "hello")
        XCTAssertEqual(payload?.source, .accessibility)
    }
}
