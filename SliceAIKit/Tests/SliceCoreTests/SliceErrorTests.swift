import XCTest
@testable import SliceCore

final class SliceErrorTests: XCTestCase {
    func test_userMessage_forEachCategory() {
        XCTAssertFalse(SliceError.permission(.accessibilityDenied).userMessage.isEmpty)
        XCTAssertFalse(SliceError.selection(.axEmpty).userMessage.isEmpty)
        XCTAssertFalse(SliceError.provider(.unauthorized).userMessage.isEmpty)
        XCTAssertFalse(SliceError.configuration(.fileNotFound).userMessage.isEmpty)
    }

    func test_providerRateLimited_includesRetryAfter() {
        let msg = SliceError.provider(.rateLimited(retryAfter: 30)).userMessage
        XCTAssertTrue(msg.contains("30"))
    }

    func test_developerContext_noSensitive() {
        // developerContext 用于日志，绝不包含 API Key 或选中文字
        let err = SliceError.provider(.unauthorized)
        XCTAssertFalse(err.developerContext.lowercased().contains("sk-"))
    }

    func test_developerContext_redactsPayloads() {
        // 1. invalidResponse 的 payload 必须被 <redacted> 替换
        let respErr = SliceError.provider(.invalidResponse("sk-leaked-api-key-12345"))
        XCTAssertFalse(respErr.developerContext.contains("sk-leaked"))
        XCTAssertFalse(respErr.developerContext.contains("12345"))
        XCTAssertTrue(respErr.developerContext.contains("<redacted>"))

        // 2. sseParseError 同样脱敏
        let sseErr = SliceError.provider(.sseParseError("data: {\"key\":\"secret\"}"))
        XCTAssertFalse(sseErr.developerContext.contains("secret"))
        XCTAssertTrue(sseErr.developerContext.contains("<redacted>"))

        // 3. invalidJSON 同样脱敏
        let jsonErr = SliceError.configuration(.invalidJSON("{\"apiKey\":\"sk-bad\"}"))
        XCTAssertFalse(jsonErr.developerContext.contains("sk-bad"))
        XCTAssertTrue(jsonErr.developerContext.contains("<redacted>"))

        // 4. 安全的数值 payload 保留
        let sizeErr = SliceError.selection(.textTooLong(9999))
        XCTAssertTrue(sizeErr.developerContext.contains("9999"))

        // 5. rateLimited 的数字也保留（向上取整、至少 1s）
        let rlErr = SliceError.provider(.rateLimited(retryAfter: 0.9))
        XCTAssertTrue(rlErr.developerContext.contains("1"))   // ceil(0.9)=1
    }

    func test_rateLimited_userMessage_roundsUp_andClampsFloor() {
        // 0.9 秒应向上取整为 1
        let msg1 = SliceError.provider(.rateLimited(retryAfter: 0.9)).userMessage
        XCTAssertTrue(msg1.contains("1 秒"), "got: \(msg1)")

        // 无效/负值应回落到通用文案
        let msg2 = SliceError.provider(.rateLimited(retryAfter: -5)).userMessage
        XCTAssertFalse(msg2.contains("-"))

        let msg3 = SliceError.provider(.rateLimited(retryAfter: .infinity)).userMessage
        XCTAssertFalse(msg3.contains("inf"))
    }
}
