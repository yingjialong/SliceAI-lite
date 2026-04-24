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

        // 4. incompleteThinkingConfig 关联值（含 tool/provider id）同样脱敏
        let thinkingErr = SliceError.configuration(.incompleteThinkingConfig("Tool 'my-tool' secret"))
        XCTAssertFalse(thinkingErr.developerContext.contains("my-tool"))
        XCTAssertTrue(thinkingErr.developerContext.contains("<redacted>"))

        // 6. 安全的数值 payload 保留
        let sizeErr = SliceError.selection(.textTooLong(9999))
        XCTAssertTrue(sizeErr.developerContext.contains("9999"))

        // 7. rateLimited 的数字也保留（向上取整、至少 1s）
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

    /// 覆盖 ProviderError 中剩余分支的 userMessage
    /// 目的：确保每种错误都能给出非空的本地化文案，避免 UI 出现空字符串
    func test_providerError_userMessage_allCases() {
        // serverError：文案需包含 HTTP 状态码，方便用户排查
        let srv = SliceError.provider(.serverError(503)).userMessage
        XCTAssertTrue(srv.contains("503"), "got: \(srv)")
        XCTAssertFalse(srv.isEmpty)

        // networkTimeout：文案需非空
        let net = SliceError.provider(.networkTimeout).userMessage
        XCTAssertFalse(net.isEmpty)

        // invalidResponse：文案需非空，且不能把传入字符串原样拼进去（脱敏）
        let inv = SliceError.provider(.invalidResponse("raw-body-xxx")).userMessage
        XCTAssertFalse(inv.isEmpty)
        XCTAssertFalse(inv.contains("raw-body-xxx"))

        // sseParseError：文案需非空，同样不能回显原始 payload
        let sse = SliceError.provider(.sseParseError("data:...")).userMessage
        XCTAssertFalse(sse.isEmpty)
        XCTAssertFalse(sse.contains("data:"))
    }

    /// 覆盖 ConfigurationError 中剩余分支的 userMessage
    /// 目的：配置错误的引导文案必须清晰，且不泄露配置文件内容
    func test_configurationError_userMessage_allCases() {
        // schemaVersionTooNew：文案需提示升级，且包含版本号
        let tooNew = SliceError.configuration(.schemaVersionTooNew(99)).userMessage
        XCTAssertTrue(tooNew.contains("99"), "got: \(tooNew)")
        XCTAssertFalse(tooNew.isEmpty)

        // invalidJSON：文案需非空，且不可回显非法 JSON 原文（可能含密钥）
        let badJSON = SliceError.configuration(.invalidJSON("{\"k\":\"v\"}")).userMessage
        XCTAssertFalse(badJSON.isEmpty)
        XCTAssertFalse(badJSON.contains("\"k\""))

        // referencedProviderMissing：文案应包含缺失的 providerId 以便用户定位
        let missing = SliceError.configuration(.referencedProviderMissing("openai-xxx")).userMessage
        XCTAssertTrue(missing.contains("openai-xxx"), "got: \(missing)")

        // incompleteThinkingConfig：文案应非空，且引导用户去设置补全 model id
        let incomplete = SliceError.configuration(.incompleteThinkingConfig("t")).userMessage
        XCTAssertFalse(incomplete.isEmpty)
        // 关联值（tool/provider id 等）不应出现在 userMessage 中
        XCTAssertFalse(incomplete.contains("\"t\""))
    }

    /// 覆盖 PermissionError 两种 case 的 userMessage
    /// 目的：权限提示必须清晰告知用户需要开启哪一项
    func test_permissionError_userMessage_allCases() {
        let ax = SliceError.permission(.accessibilityDenied).userMessage
        XCTAssertFalse(ax.isEmpty)

        let im = SliceError.permission(.inputMonitoringDenied).userMessage
        XCTAssertFalse(im.isEmpty)
        // 两种权限文案不应一致，避免误导用户
        XCTAssertNotEqual(ax, im)
    }

    /// 覆盖 PermissionError 的 developerContext
    /// 目的：保证权限错误的日志 tag 可枚举且稳定（便于日志聚合/告警）
    func test_permissionError_developerContext_allCases() {
        XCTAssertEqual(
            SliceError.permission(.accessibilityDenied).developerContext,
            "permission.accessibilityDenied"
        )
        XCTAssertEqual(
            SliceError.permission(.inputMonitoringDenied).developerContext,
            "permission.inputMonitoringDenied"
        )
    }

    /// 覆盖 Selection / Configuration / Provider 中剩余 developerContext 分支
    /// 目的：确保所有 case 的 developerContext 都有确定的字符串格式，可用于日志断言
    func test_developerContext_remainingCases() {
        // selection：除 textTooLong 外的 3 个 case
        XCTAssertEqual(
            SliceError.selection(.axUnavailable).developerContext,
            "selection.axUnavailable"
        )
        XCTAssertEqual(
            SliceError.selection(.axEmpty).developerContext,
            "selection.axEmpty"
        )
        XCTAssertEqual(
            SliceError.selection(.clipboardTimeout).developerContext,
            "selection.clipboardTimeout"
        )

        // provider：covers serverError / networkTimeout
        XCTAssertEqual(
            SliceError.provider(.serverError(500)).developerContext,
            "provider.serverError(500)"
        )
        XCTAssertEqual(
            SliceError.provider(.networkTimeout).developerContext,
            "provider.networkTimeout"
        )

        // rateLimited 的 nil / 非有限值应输出 "nil"
        let nilCtx = SliceError.provider(.rateLimited(retryAfter: nil)).developerContext
        XCTAssertTrue(nilCtx.contains("nil"), "got: \(nilCtx)")

        let infCtx = SliceError.provider(.rateLimited(retryAfter: .infinity)).developerContext
        XCTAssertTrue(infCtx.contains("nil"), "got: \(infCtx)")

        // configuration：除 invalidJSON 外的两个剩余 case
        XCTAssertEqual(
            SliceError.configuration(.fileNotFound).developerContext,
            "configuration.fileNotFound"
        )
        XCTAssertEqual(
            SliceError.configuration(.schemaVersionTooNew(42)).developerContext,
            "configuration.schemaVersionTooNew(42)"
        )
        XCTAssertEqual(
            SliceError.configuration(.referencedProviderMissing("p-id")).developerContext,
            "configuration.referencedProviderMissing(p-id)"
        )
    }
}
