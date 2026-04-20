import Foundation

/// 测试专用的 URLProtocol 拦截器
/// 用法：测试内给 `requestHandler` 赋值，发起请求时 URLSession 会命中此协议并回放指定响应
/// 注意：`requestHandler` 使用类级存储，tearDown 时务必置 nil，避免测试间污染
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// 用类级字典存 request handler，测试设置后复位
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// 声明本协议可处理所有请求；实际拦截由 URLSession 的 configuration.protocolClasses 决定
    override class func canInit(with request: URLRequest) -> Bool { true }

    /// URLProtocol 要求返回规范化后的请求；无需改写，原样返回
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// 开始加载：执行 requestHandler，把响应/数据/结束事件依次回放给 client
    override func startLoading() {
        guard let handler = Self.requestHandler else {
            // 未设置 handler 视为异常，模拟坏响应
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    /// 取消加载：MVP 内无需特殊清理，保持空实现
    override func stopLoading() {}
}

extension URLSession {
    /// 构造使用 MockURLProtocol 的短生命周期 URLSession，供测试调用
    static func mocked() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

extension MockURLProtocol {
    /// 按顺序返回多组响应；顺序由数组决定，最后一个会被重复使用
    /// 用途：测试重试/退避逻辑，让同一个 URLSession 在不同 attempt 里拿到不同状态
    /// - Parameter responses: 按次序使用的响应列表；索引超过数组长度时会一直复用最后一项
    static func setSequencedResponses(_ responses: [(HTTPURLResponse, Data)]) {
        let box = ResponseBox(responses: responses)
        requestHandler = { _ in box.next() }
    }

    /// 线程安全的响应盒子，缓存按序推进的响应列表
    /// 注：MockURLProtocol 在 URLSession 的工作队列上被调用，因此必须加锁才能安全 mutate index
    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private let responses: [(HTTPURLResponse, Data)]
        private var index = 0

        init(responses: [(HTTPURLResponse, Data)]) {
            self.responses = responses
        }

        /// 返回下一组响应；超出数组长度时复用最后一项，避免崩溃
        func next() -> (HTTPURLResponse, Data) {
            lock.lock()
            defer { lock.unlock() }
            let clamped = min(index, responses.count - 1)
            let value = responses[clamped]
            index += 1
            return value
        }
    }
}
