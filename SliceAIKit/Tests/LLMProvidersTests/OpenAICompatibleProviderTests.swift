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

    // MARK: - extraBody merge

    /// extraBody 字典在 buildURLRequest 时正确 merge 到 root body
    func test_extraBody_mergedToRootBody() async throws {
        let extra: [String: Any] = ["thinking": ["type": "enabled"]]
        let request = ChatRequest(
            model: "test-model",
            messages: [ChatMessage(role: .user, content: "hi")],
            extraBody: extra
        )
        final class BodyCapture: @unchecked Sendable { var data: Data? }
        let capture = BodyCapture()
        MockURLProtocol.requestHandler = { req in
            // URLSession 内部会把 httpBody 转成 httpBodyStream 传给 URLProtocol，需从 stream 读取
            capture.data = Self.readBodyData(from: req)
            // swiftlint:disable:next force_unwrapping
            let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, "data: [DONE]\n\n".data(using: .utf8)!)
        }
        let provider = makeProvider()
        let stream = try await provider.stream(request: request)
        for try await _ in stream { }  // 耗尽流

        let capturedBody = try XCTUnwrap(capture.data, "应有请求 body 被捕获")
        let bodyDict = try JSONSerialization.jsonObject(with: capturedBody) as? [String: Any]
        let thinking = bodyDict?["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled",
                       "extraBody 中的 thinking 字段应 merge 进 root body")
        // 校验 stream 字段仍然存在
        XCTAssertEqual(bodyDict?["stream"] as? Bool, true, "stream 字段必须为 true")
    }

    /// extraBody 不应覆盖 ChatRequest 的现有字段（防御性 merge）
    func test_extraBody_doesNotOverrideExistingFields() async throws {
        let request = ChatRequest(
            model: "real-model",
            messages: [ChatMessage(role: .user, content: "hi")],
            extraBody: ["model": "evil-model"]  // 尝试覆盖 model 字段
        )
        final class BodyCapture: @unchecked Sendable { var data: Data? }
        let capture = BodyCapture()
        MockURLProtocol.requestHandler = { req in
            // URLSession 内部会把 httpBody 转成 httpBodyStream 传给 URLProtocol，需从 stream 读取
            capture.data = Self.readBodyData(from: req)
            // swiftlint:disable:next force_unwrapping
            let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, "data: [DONE]\n\n".data(using: .utf8)!)
        }
        let provider = makeProvider()
        let stream = try await provider.stream(request: request)
        for try await _ in stream { }

        let capturedBody = try XCTUnwrap(capture.data, "应有请求 body 被捕获")
        let bodyDict = try JSONSerialization.jsonObject(with: capturedBody) as? [String: Any]
        XCTAssertEqual(bodyDict?["model"] as? String, "real-model",
                       "extraBody 中的 model 字段不应覆盖 ChatRequest 原有的 model")
    }

    // MARK: - Reasoning extraction（fallback chain）

    /// OpenRouter 风格的 SSE chunk: chunk.reasoningDelta 应来自 delta.reasoning
    func test_chunk_reasoning_extractsFromOpenRouterField() async throws {
        let fixture = try loadFixture("sse-openrouter-reasoning.txt")
        MockURLProtocol.requestHandler = { req in
            // swiftlint:disable:next force_unwrapping
            let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, fixture)
        }
        let provider = makeProvider()
        let stream = try await provider.stream(request: makeRequest())
        var reasonings: [String] = []
        var deltas: [String] = []
        for try await chunk in stream {
            if let reasoning = chunk.reasoningDelta { reasonings.append(reasoning) }
            if !chunk.delta.isEmpty { deltas.append(chunk.delta) }
        }
        XCTAssertEqual(reasonings, ["Let me think...", " the answer is 42"],
                       "OpenRouter delta.reasoning 字段应被提取为 reasoningDelta")
        XCTAssertEqual(deltas, ["42"], "普通 delta content 应正常透传")
    }

    /// DeepSeek 风格的 SSE chunk: chunk.reasoningDelta 应来自 delta.reasoning_content
    func test_chunk_reasoning_extractsFromDeepSeekField() async throws {
        let fixture = try loadFixture("sse-deepseek-reasoning-content.txt")
        MockURLProtocol.requestHandler = { req in
            // swiftlint:disable:next force_unwrapping
            let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, fixture)
        }
        let provider = makeProvider()
        let stream = try await provider.stream(request: makeRequest())
        var reasonings: [String] = []
        var deltas: [String] = []
        for try await chunk in stream {
            if let reasoning = chunk.reasoningDelta { reasonings.append(reasoning) }
            if !chunk.delta.isEmpty { deltas.append(chunk.delta) }
        }
        XCTAssertEqual(reasonings, ["Analyzing the input...", " computing result."],
                       "DeepSeek delta.reasoning_content 字段应被提取为 reasoningDelta")
        XCTAssertEqual(deltas, ["Result: 42"], "普通 delta content 应正常透传")
    }

    // MARK: - Helpers

    /// 从 Bundle.module/Fixtures 目录加载测试 fixture 文件
    /// - Parameter name: 文件名（含扩展名）
    /// - Returns: 文件内容 Data
    private func loadFixture(_ name: String) throws -> Data {
        // swiftlint:disable:next force_unwrapping
        let url = Bundle.module.url(forResource: name, withExtension: nil,
                                    subdirectory: "Fixtures")!  // fixture 文件必须存在，否则是测试配置错误
        return try Data(contentsOf: url)
    }

    /// 从 URLRequest 中读取 body 数据
    /// URLSession 内部会把 httpBody 转成 httpBodyStream 传给 URLProtocol；
    /// 因此必须同时检查 httpBody 与 httpBodyStream 两个属性
    /// - Parameter req: URLProtocol 收到的 URLRequest
    /// - Returns: body 的 Data，若两者均为 nil 则返回 nil
    private static func readBodyData(from req: URLRequest) -> Data? {
        // 优先检查 httpBody（测试环境下通常为 nil，body 被转为 stream）
        if let body = req.httpBody { return body }
        // 从 httpBodyStream 读取（URLSession 传给 URLProtocol 的实际路径）
        guard let stream = req.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(contentsOf: buffer[..<read])
        }
        return data
    }

    /// 构造使用 MockURLProtocol 的 Provider 实例
    private func makeProvider() -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.test.local/v1")!,  // swiftlint:disable:this force_unwrapping
            apiKey: "test-key",
            session: URLSession.mocked()
        )
    }

    /// 构造最小 ChatRequest 用于测试
    private func makeRequest() -> ChatRequest {
        ChatRequest(model: "m", messages: [ChatMessage(role: .user, content: "hi")])
    }
}
