import XCTest
@testable import SliceCore

// MARK: - Fakes

/// 假 Configuration 提供者，用 actor 保证线程安全
private actor FakeConfig: ConfigurationProviding {
    var cfg: Configuration
    init(_ cfg: Configuration) { self.cfg = cfg }
    func current() async -> Configuration { cfg }
    func update(_ configuration: Configuration) async throws { self.cfg = configuration }
}

/// 假 Keychain 存储，支持预置初始 key-value
private actor FakeKeychain: KeychainAccessing {
    var store: [String: String]
    init(_ store: [String: String] = [:]) { self.store = store }
    func readAPIKey(providerId: String) async throws -> String? { store[providerId] }
    func writeAPIKey(_ value: String, providerId: String) async throws { store[providerId] = value }
    func deleteAPIKey(providerId: String) async throws { store.removeValue(forKey: providerId) }
}

/// 假 LLM Provider，按预置 chunks 依次 yield
private struct FakeProvider: LLMProvider {
    let chunks: [String]
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { cont in
            Task {
                for c in chunks { cont.yield(ChatChunk(delta: c)) }
                cont.finish()
            }
        }
    }
}

/// 简单假工厂：返回一个固定 chunks 的 FakeProvider
private struct FakeFactory: LLMProviderFactory {
    let chunks: [String]
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        FakeProvider(chunks: chunks)
    }
}

/// 捕获型工厂：将传入的 apiKey 保存到 Box，用于断言 ToolExecutor 正确传递密钥
private struct CapturingFactory: LLMProviderFactory {
    final class Box: @unchecked Sendable { var capturedKey: String? }
    let box = Box()
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        box.capturedKey = apiKey
        return FakeProvider(chunks: ["ok"])
    }
}

/// 抛错工厂：make() 同步抛出一个 provider 错误
/// 用于验证 ToolExecutor 不会吞掉工厂层抛出的错误
private struct ThrowingFactory: LLMProviderFactory {
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        throw SliceError.provider(.serverError(500))
    }
}

/// 抛错型 Provider：stream() 在返回 AsyncThrowingStream 之前就抛错
/// 用于验证调用方能收到与底层一致的 SliceError
private struct ThrowingStreamProvider: LLMProvider {
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        throw SliceError.provider(.networkTimeout)
    }
}

/// 工厂：返回上面那个会直接抛错的 Provider
private struct ThrowingStreamFactory: LLMProviderFactory {
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        ThrowingStreamProvider()
    }
}

final class ToolExecutorTests: XCTestCase {

    /// 验证 execute 正常渲染 prompt 并正确转发流式 chunk
    func test_execute_renderPromptAndStream() async throws {
        let cfg = DefaultConfiguration.initial()
        let keychain = FakeKeychain(["openai-official": "sk-test"])
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: FakeFactory(chunks: ["Hello ", "World"]),
            keychain: keychain
        )
        let payload = SelectionPayload(
            text: "hola", appBundleID: "x", appName: "X", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        let stream = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
        var collected = ""
        for try await chunk in stream { collected += chunk.delta }
        XCTAssertEqual(collected, "Hello World")
    }

    /// 验证当 Keychain 读不到 API Key 时，抛出 .provider(.unauthorized)
    func test_execute_missingAPIKey_throwsUnauthorized() async {
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: FakeFactory(chunks: []),
            keychain: FakeKeychain()   // 空
        )
        let payload = SelectionPayload(
            text: "x", appBundleID: "", appName: "", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        do {
            _ = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
            XCTFail("should have thrown")
        } catch SliceError.provider(.unauthorized) {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// 验证 ToolExecutor 把 Keychain 中的 API Key 原样传给工厂
    func test_execute_passesAPIKeyToFactory() async throws {
        let factory = CapturingFactory()
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: factory,
            keychain: FakeKeychain(["openai-official": "sk-captured"])
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        let stream = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
        for try await _ in stream {}
        XCTAssertEqual(factory.box.capturedKey, "sk-captured")
    }

    /// 验证 LLMProviderFactory.make 抛错时，ToolExecutor 原样向上传播
    /// 覆盖 Task 14 review 指出的未测路径：工厂构造失败
    func test_execute_factoryThrows_propagatesError() async {
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: ThrowingFactory(),
            keychain: FakeKeychain(["openai-official": "sk-anything"])
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        do {
            _ = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
            XCTFail("should have thrown factory error")
        } catch SliceError.provider(.serverError(let code)) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// 验证 LLMProvider.stream 同步抛错时，ToolExecutor 原样向上传播
    /// 覆盖 Task 14 review 指出的未测路径：底层流在启动阶段抛错
    func test_execute_streamThrows_propagatesError() async {
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: ThrowingStreamFactory(),
            keychain: FakeKeychain(["openai-official": "sk-anything"])
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        do {
            _ = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
            XCTFail("should have thrown stream error")
        } catch SliceError.provider(.networkTimeout) {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_execute_usesApiKeyRefAccount_notProviderId() async throws {
        // provider.id 与 apiKeyRef 指向的 account 不同时，应按 apiKeyRef 读取
        var cfg = DefaultConfiguration.initial()
        cfg.providers[0] = Provider(
            id: "renamed-provider",        // 新 id
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,  // swiftlint:disable:this force_unwrapping
            apiKeyRef: "keychain:legacy-account",   // 仍指向旧 account
            defaultModel: "gpt-5"
        )
        cfg.tools[0].providerId = "renamed-provider"

        let keychain = FakeKeychain([
            "legacy-account": "sk-found",     // 只在旧 account 存在
            "renamed-provider": ""             // 新 id 下故意为空
        ])

        let factory = CapturingFactory()
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: factory,
            keychain: keychain
        )
        let payload = SelectionPayload(
            text: "x", appBundleID: "", appName: "", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        let stream = try await exec.execute(tool: cfg.tools[0], payload: payload)
        for try await _ in stream {}
        XCTAssertEqual(factory.box.capturedKey, "sk-found")
    }

    func test_execute_unsupportedApiKeyRefScheme_throwsUnauthorized() async {
        var cfg = DefaultConfiguration.initial()
        cfg.providers[0] = Provider(
            id: "openai-official",
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,  // swiftlint:disable:this force_unwrapping
            apiKeyRef: "env:OPENAI_API_KEY",   // 当前不支持的 scheme
            defaultModel: "gpt-5"
        )
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: FakeFactory(chunks: []),
            keychain: FakeKeychain(["openai-official": "sk-anything"])
        )
        let payload = SelectionPayload(
            text: "x", appBundleID: "", appName: "", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        do {
            _ = try await exec.execute(tool: cfg.tools[0], payload: payload)
            XCTFail("should have thrown")
        } catch SliceError.provider(.unauthorized) {
            // OK: 非 keychain: 前缀按未授权处理
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 验证当 Tool.providerId 在 Configuration.providers 中找不到时抛配置错误
    func test_execute_unknownProvider_throws() async {
        var cfg = DefaultConfiguration.initial()
        cfg.tools[0].providerId = "ghost"     // 引用不存在的 provider
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: FakeFactory(chunks: []),
            keychain: FakeKeychain()
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        do {
            _ = try await exec.execute(tool: cfg.tools[0], payload: payload)
            XCTFail("should have thrown")
        } catch SliceError.configuration(.referencedProviderMissing(let id)) {
            XCTAssertEqual(id, "ghost")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
