import Foundation
import SliceCore

/// OpenAI 兼容协议的 Provider 实现
/// 使用 URLSession.bytes(for:) 流式读取 SSE
public struct OpenAICompatibleProvider: LLMProvider {

    /// 供应商的基础 URL，通常形如 https://api.openai.com/v1
    private let baseURL: URL
    /// 透传到 Authorization: Bearer <apiKey> 的密钥
    private let apiKey: String
    /// 注入的 URLSession，测试可换成 Mock
    private let session: URLSession

    /// 构造 OpenAI 兼容 Provider
    /// - Parameters:
    ///   - baseURL: 服务端基础 URL，例如 https://api.openai.com/v1
    ///   - apiKey: 用于 Bearer 鉴权的 API Key
    ///   - session: URLSession，默认使用 .shared；测试可注入 MockURLProtocol 的会话
    public init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    /// 发起流式 chat completion 请求并将 SSE 解码为 ChatChunk 流
    /// - Parameter request: 领域层定义的 ChatRequest（含 model / messages / 参数）
    /// - Returns: AsyncThrowingStream<ChatChunk, any Error>；遇 HTTP 错误会在 await 阶段抛出
    /// - Note: 429 会按 spec §7.2 触发一次指数退避重试，第二次仍失败则抛出最终错误
    public func stream(
        request: ChatRequest
    ) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        let httpReq = try buildURLRequest(for: request)

        // 第一次尝试：若 429 则等待后再试一次；其余错误立刻抛出
        let (firstBytes, firstResp) = try await performRequest(httpReq)
        if firstResp.statusCode == 429 {
            try await backoff(for: firstResp)
            let (secondBytes, secondResp) = try await performRequest(httpReq)
            try Self.throwIfErrorStatus(secondResp)
            return Self.makeStream(from: secondBytes)
        }

        try Self.throwIfErrorStatus(firstResp)
        return Self.makeStream(from: firstBytes)
    }

    /// 构造发起 chat completion 请求的 URLRequest
    /// - Parameter request: 领域层 ChatRequest，需追加 stream: true
    /// - Returns: 已设置 headers / body / timeout 的 URLRequest
    /// - Throws: JSONEncoder / JSONSerialization 的编码错误
    private func buildURLRequest(for request: ChatRequest) throws -> URLRequest {
        // 组装 URL：baseURL 通常形如 https://api.openai.com/v1
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var httpReq = URLRequest(url: endpoint)
        httpReq.httpMethod = "POST"
        httpReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        httpReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpReq.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        httpReq.timeoutInterval = 30

        // 追加 stream: true，保持其它字段由 ChatRequest 编码产出
        var body = try JSONEncoder().encode(request)
        if var dict = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            dict["stream"] = true
            body = try JSONSerialization.data(withJSONObject: dict)
        }
        httpReq.httpBody = body
        return httpReq
    }

    /// 发起一次 HTTP 请求并校验响应是 HTTPURLResponse
    /// - Parameter httpReq: 已构造好的 URLRequest
    /// - Returns: 可异步读取的字节流与 HTTP 响应
    /// - Throws: SliceError.provider(.invalidResponse) 当响应不是 HTTPURLResponse
    private func performRequest(
        _ httpReq: URLRequest
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: httpReq)
        guard let http = response as? HTTPURLResponse else {
            throw SliceError.provider(.invalidResponse("non-http response"))
        }
        return (bytes, http)
    }

    /// 根据 429 响应计算退避时长并等待
    /// - Parameter response: 首次请求返回的 429 响应
    /// - Note: 退避时长 = min(Retry-After, 5s)；header 缺失时退 1 秒（spec §7.2）
    private func backoff(for response: HTTPURLResponse) async throws {
        let hint = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        // 1s 默认；上限 5s，避免 MVP 卡顿过久
        let backoff = min(hint ?? 1.0, 5.0)
        try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
    }

    /// 把 HTTP 状态码映射为领域层错误，2xx 直接通过
    /// - Parameter http: 待判定的 HTTP 响应
    /// - Throws: SliceError.provider 对应错误
    private static func throwIfErrorStatus(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw SliceError.provider(.unauthorized)
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw SliceError.provider(.rateLimited(retryAfter: retry))
        case 500..<600:
            throw SliceError.provider(.serverError(http.statusCode))
        default:
            throw SliceError.provider(.invalidResponse("HTTP \(http.statusCode)"))
        }
    }

    /// 将 URLSession.AsyncBytes 封装为 ChatChunk 流
    /// 注：独立成静态方法以隔离非 Sendable 的 bytes 捕获路径
    /// 实现要点：bytes.lines 会吞掉空行，而 SSE 事件边界依赖空行；因此我们按字节累积，
    ///          遇到 "\n" 边界后把整行（含换行）交给 SSEDecoder，空行也能正确触发事件
    private static func makeStream(
        from bytes: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<ChatChunk, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = SSEDecoder()
                var buffer: [UInt8] = []
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == UInt8(ascii: "\n") {
                            // 以 UTF-8 解码当前缓冲的一整行（含换行），交给 SSEDecoder
                            if let line = String(bytes: buffer, encoding: .utf8) {
                                let events = decoder.feed(line)
                                if try emitAndCheckDone(events, continuation: continuation) {
                                    return
                                }
                            }
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    // 流结束：把尾部残留 + 两个换行喂入，保证事件边界被触发
                    var tail = ""
                    if !buffer.isEmpty, let s = String(bytes: buffer, encoding: .utf8) {
                        tail = s
                    }
                    let rest = decoder.feed(tail + "\n\n")
                    _ = try emitAndCheckDone(rest, continuation: continuation)
                    continuation.finish()
                } catch {
                    // URLSession 超时映射为领域层 networkTimeout，其余原样抛出
                    if (error as? URLError)?.code == .timedOut {
                        continuation.finish(throwing: SliceError.provider(.networkTimeout))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 把解码得到的 SSE 事件转换成 ChatChunk 并投递给 continuation
    /// - Returns: 是否遇到 [DONE]；true 时调用方应立即退出循环
    /// - Throws: 当 data 行 JSON 解析失败时抛出 SliceError.provider(.sseParseError)
    private static func emitAndCheckDone(
        _ events: [SSEDecoder.Event],
        continuation: AsyncThrowingStream<ChatChunk, any Error>.Continuation
    ) throws -> Bool {
        for event in events {
            switch event {
            case .data(let json):
                // decodeChunk 返回 nil = 合法 skip（role-only / finish-only frame），不 yield
                if let chunk = try decodeChunk(json: json) {
                    continuation.yield(chunk)
                }
            case .done:
                continuation.finish()
                return true
            }
        }
        return false
    }

    /// 解码一条 SSE `data:` JSON 行
    /// - Parameter json: SSE data 字段的原始 JSON 字符串
    /// - Returns: `nil` 表示这是合法但无增量的 chunk（如 role-only 首帧），应静默跳过
    /// - Throws: `SliceError.provider(.sseParseError)` 当 JSON 无法解析或结构不符
    private static func decodeChunk(json: String) throws -> ChatChunk? {
        guard let data = json.data(using: .utf8) else {
            throw SliceError.provider(.sseParseError("non-utf8 data line"))
        }
        let parsed: OpenAIStreamChunk
        do {
            parsed = try JSONDecoder().decode(OpenAIStreamChunk.self, from: data)
        } catch let error as DecodingError {
            // 脱敏：只取 DecodingError 的 case 名称，不回传原文
            throw SliceError.provider(.sseParseError(summarize(decodingError: error)))
        } catch {
            throw SliceError.provider(.sseParseError("decode failed"))
        }
        let delta = parsed.choices.first?.delta.content ?? ""
        let reason = parsed.choices.first?.finishReason.flatMap(FinishReason.init(rawValue:))
        // 空 delta 且无 finishReason 的 chunk 无意义，过滤
        if delta.isEmpty && reason == nil { return nil }
        return ChatChunk(delta: delta, finishReason: reason)
    }

    /// 将 DecodingError 概括为一个简短字符串，避免把响应体 / 用户数据带进错误里
    /// - Parameter error: JSONDecoder 抛出的 DecodingError
    /// - Returns: 便于日志与排障的简短摘要（不含原始 payload）
    private static func summarize(decodingError error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "keyNotFound(\(key.stringValue))"
        case .valueNotFound(let type, _): return "valueNotFound(\(type))"
        case .typeMismatch(let type, _): return "typeMismatch(\(type))"
        case .dataCorrupted: return "dataCorrupted"
        @unknown default: return "unknown"
        }
    }
}
