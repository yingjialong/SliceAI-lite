import XCTest
@testable import LLMProviders
@testable import SliceCore

/// OpenAICompatibleProvider 的集成测试
/// 通过 MockURLProtocol 拦截 URLSession 请求，覆盖 happy path 与常见错误分支
final class OpenAICompatibleProviderTests: XCTestCase {

    /// 每个用例结束后清空类级 handler，避免测试间互相污染
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    /// Happy path：SSE 正常返回两个 delta + finish + [DONE]，应拼出完整文本
    func test_stream_happyPath_returnsConcatenatedChunks() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" World"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
            return (resp, sse)
        }

        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-test",
            session: URLSession.mocked()
        )

        let req = ChatRequest(
            model: "gpt-5",
            messages: [ChatMessage(role: .user, content: "hi")]
        )
        var collected = ""
        for try await chunk in try await provider.stream(request: req) {
            collected += chunk.delta
        }
        XCTAssertEqual(collected, "Hello World")
    }

    /// 401：Provider 必须映射成 SliceError.provider(.unauthorized)
    func test_stream_unauthorized401_throws() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("unauthorized".utf8))
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "bad", session: URLSession.mocked()
        )
        let req = ChatRequest(model: "x", messages: [])

        do {
            let s = try await provider.stream(request: req)
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.unauthorized) {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 5xx：应映射成 SliceError.provider(.serverError(code)) 并透传 code
    func test_stream_serverError500_throws() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.serverError(let code)) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 429 → 自动退避重试一次（spec §7.2）；若第二次仍 429，则抛出最终的 rateLimited
    /// 并携带第二次响应的 Retry-After（而非第一次）
    func test_stream_rateLimited429_retriesOnce_thenFailsIfStillRateLimited() async throws {
        // 第一次 429（Retry-After: 0 以让测试秒级跑完），第二次仍 429 → 最终抛 rateLimited
        // swiftlint:disable force_unwrapping
        let url = URL(string: "https://api.example.com/v1")!
        let resp429 = HTTPURLResponse(url: url, statusCode: 429,
                                      httpVersion: nil,
                                      headerFields: ["Retry-After": "0"])!
        let resp429b = HTTPURLResponse(url: url, statusCode: 429,
                                       httpVersion: nil,
                                       headerFields: ["Retry-After": "7"])!
        // swiftlint:enable force_unwrapping
        MockURLProtocol.setSequencedResponses([(resp429, Data()), (resp429b, Data())])

        let provider = OpenAICompatibleProvider(
            baseURL: url, apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.rateLimited(let after)) {
            XCTAssertEqual(after, 7)   // 来自第二次（最终）响应
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 429 → 自动退避重试一次 → 第二次 200 + SSE 流：应正常完成不抛错
    func test_stream_rateLimited429_retriesOnce_thenSucceeds() async throws {
        // 第一次 429 → 自动退避 → 第二次 200 + SSE 流
        // swiftlint:disable force_unwrapping
        let url = URL(string: "https://api.example.com/v1")!
        let resp429 = HTTPURLResponse(url: url, statusCode: 429,
                                      httpVersion: nil,
                                      headerFields: ["Retry-After": "0"])!
        let resp200 = HTTPURLResponse(url: url, statusCode: 200,
                                      httpVersion: nil,
                                      headerFields: ["Content-Type": "text/event-stream"])!
        // swiftlint:enable force_unwrapping
        let sse = Data("""
        data: {"choices":[{"delta":{"content":"OK"}}]}

        data: [DONE]


        """.utf8)
        MockURLProtocol.setSequencedResponses([(resp429, Data()), (resp200, sse)])

        let provider = OpenAICompatibleProvider(
            baseURL: url, apiKey: "k", session: URLSession.mocked()
        )
        var collected = ""
        for try await chunk in try await provider.stream(request: ChatRequest(model: "x", messages: [])) {
            collected += chunk.delta
        }
        XCTAssertEqual(collected, "OK")
    }

    /// SSE data 行里返回非法 JSON：必须抛 sseParseError（而非静默吞掉）
    func test_stream_malformedJSONInData_throwsSSEParseError() async throws {
        // 服务端以 200 + 正常 SSE 外壳返回，但 data: 内 JSON 不合法
        // swiftlint:disable force_unwrapping
        let url = URL(string: "https://api.example.com/v1")!
        let resp200 = HTTPURLResponse(url: url, statusCode: 200,
                                      httpVersion: nil,
                                      headerFields: ["Content-Type": "text/event-stream"])!
        // swiftlint:enable force_unwrapping
        let sse = Data("""
        data: {"this is not valid json

        data: [DONE]


        """.utf8)
        MockURLProtocol.requestHandler = { _ in (resp200, sse) }

        let provider = OpenAICompatibleProvider(
            baseURL: url, apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.sseParseError) {
            // OK — 静默吞掉是已修复的 bug
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 部分 OpenAI 兼容服务会在流里塞 error payload；缺 choices 字段应被视为 parse error
    func test_stream_serverErrorPayloadInData_throwsSSEParseError() async throws {
        // 有的 OpenAI 兼容服务会在流里塞 error payload；这种 JSON 缺少 choices 字段应被视为 parse error
        // swiftlint:disable force_unwrapping
        let url = URL(string: "https://api.example.com/v1")!
        let resp200 = HTTPURLResponse(url: url, statusCode: 200,
                                      httpVersion: nil,
                                      headerFields: ["Content-Type": "text/event-stream"])!
        // swiftlint:enable force_unwrapping
        let sse = Data("""
        data: {"error":{"message":"quota exceeded","code":"insufficient_quota"}}

        data: [DONE]


        """.utf8)
        MockURLProtocol.requestHandler = { _ in (resp200, sse) }

        let provider = OpenAICompatibleProvider(
            baseURL: url, apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.sseParseError) {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// Authorization header 必须以 Bearer <apiKey> 的形式发送
    func test_stream_sendsAuthorizationHeader() async throws {
        final class Capture: @unchecked Sendable { var auth: String? }
        let cap = Capture()
        MockURLProtocol.requestHandler = { req in
            cap.auth = req.value(forHTTPHeaderField: "Authorization")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
            return (resp, Data("data: [DONE]\n\n".utf8))
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-123", session: URLSession.mocked()
        )
        for try await _ in try await provider.stream(request: ChatRequest(model: "x", messages: [])) {}
        XCTAssertEqual(cap.auth, "Bearer sk-123")
    }
}
