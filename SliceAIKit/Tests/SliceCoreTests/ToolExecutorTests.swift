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

// MARK: - Thinking mode spy providers

/// 能拦截 ChatRequest 的 spy provider，用于断言 ToolExecutor 的决策结果
/// @unchecked Sendable：var captured 在测试单线程访问，不存在真正的并发竞争
private final class ThinkingCapturingProvider: LLMProvider, @unchecked Sendable {
    /// 记录最近一次 stream() 收到的 ChatRequest，用于断言
    var captured: ChatRequest?

    /// 流式返回空流，仅用于捕获请求
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        captured = request
        return AsyncThrowingStream { $0.finish() }
    }
}

/// 返回 ThinkingCapturingProvider 的工厂，供 thinking 相关测试使用
/// @unchecked Sendable：同上，provider 属性仅在测试主线程访问
private final class ThinkingCapturingFactory: LLMProviderFactory, @unchecked Sendable {
    /// 共享的 spy provider 实例，测试读取 provider.captured 来断言
    let provider = ThinkingCapturingProvider()

    /// 始终返回同一个 spy provider，忽略 apiKey
    func make(for: Provider, apiKey: String) throws -> any LLMProvider {
        return provider
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

    // MARK: - Thinking mode tests

    /// byModel + thinkingEnabled=true 时应使用 thinkingModelId
    func test_execute_byModel_thinkingEnabled_usesThinkingModelId() async throws {
        let provider = Provider(id: "ds", name: "DeepSeek",
                                baseURL: URL(string: "https://api")!, // swiftlint:disable:this force_unwrapping
                                apiKeyRef: "keychain:ds",
                                defaultModel: "deepseek-chat",
                                thinking: .byModel)
        let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                        systemPrompt: nil, userPrompt: "{{selection}}",
                        providerId: "ds", modelId: "deepseek-chat",
                        temperature: nil, displayMode: .window, variables: [:],
                        thinkingModelId: "deepseek-reasoner",
                        thinkingEnabled: true)
        let factory = ThinkingCapturingFactory()
        let executor = makeThinkingExecutor(provider: provider, tool: tool, factory: factory)
        _ = try await executor.execute(tool: tool, payload: makeThinkingPayload())
        // 验证 ToolExecutor 切换到了 thinkingModelId
        XCTAssertEqual(factory.provider.captured?.model, "deepseek-reasoner")
        XCTAssertNil(factory.provider.captured?.extraBody)
    }

    /// byModel + thinkingEnabled=true 但 thinkingModelId=nil 时应抛配置错误
    func test_execute_byModel_thinkingEnabled_noThinkingModelId_throws() async throws {
        let provider = Provider(id: "ds", name: "DeepSeek",
                                baseURL: URL(string: "https://api")!, // swiftlint:disable:this force_unwrapping
                                apiKeyRef: "keychain:ds",
                                defaultModel: "deepseek-chat",
                                thinking: .byModel)
        let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                        systemPrompt: nil, userPrompt: "{{selection}}",
                        providerId: "ds", modelId: "deepseek-chat",
                        temperature: nil, displayMode: .window, variables: [:],
                        thinkingModelId: nil,
                        thinkingEnabled: true)
        let executor = makeThinkingExecutor(provider: provider, tool: tool,
                                            factory: ThinkingCapturingFactory())
        do {
            _ = try await executor.execute(tool: tool, payload: makeThinkingPayload())
            XCTFail("expected throw")
        } catch SliceError.configuration {
            // OK：byModel + thinkingEnabled=true + thinkingModelId=nil 必须抛配置错误
        }
    }

    /// byParameter + thinkingEnabled=true 时 extraBody 应为 enableBodyJSON 解析结果
    func test_execute_byParameter_thinkingEnabled_setsExtraBody() async throws {
        let provider = Provider(id: "or", name: "OpenRouter",
                                baseURL: URL(string: "https://api")!, // swiftlint:disable:this force_unwrapping
                                apiKeyRef: "keychain:or",
                                defaultModel: "claude",
                                thinking: .byParameter(
                                    enableBodyJSON: #"{"reasoning":{"effort":"medium"}}"#,
                                    disableBodyJSON: #"{"reasoning":{"effort":"none"}}"#
                                ))
        let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                        systemPrompt: nil, userPrompt: "{{selection}}",
                        providerId: "or", modelId: "claude",
                        temperature: nil, displayMode: .window, variables: [:],
                        thinkingEnabled: true)
        let factory = ThinkingCapturingFactory()
        let executor = makeThinkingExecutor(provider: provider, tool: tool, factory: factory)
        _ = try await executor.execute(tool: tool, payload: makeThinkingPayload())
        // 验证 extraBody 包含 "reasoning" 字段
        let extra = factory.provider.captured?.extraBody as? [String: Any]
        XCTAssertNotNil(extra?["reasoning"])
    }

    /// byParameter + thinkingEnabled=false + 有 disableBodyJSON 时也应 merge extraBody
    func test_execute_byParameter_thinkingDisabled_withDisableBody_setsExtraBody() async throws {
        let provider = Provider(id: "or", name: "OpenRouter",
                                baseURL: URL(string: "https://api")!, // swiftlint:disable:this force_unwrapping
                                apiKeyRef: "keychain:or",
                                defaultModel: "claude",
                                thinking: .byParameter(
                                    enableBodyJSON: #"{"reasoning":{"effort":"medium"}}"#,
                                    disableBodyJSON: #"{"reasoning":{"effort":"none"}}"#
                                ))
        let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                        systemPrompt: nil, userPrompt: "{{selection}}",
                        providerId: "or", modelId: "claude",
                        temperature: nil, displayMode: .window, variables: [:],
                        thinkingEnabled: false)
        let factory = ThinkingCapturingFactory()
        let executor = makeThinkingExecutor(provider: provider, tool: tool, factory: factory)
        _ = try await executor.execute(tool: tool, payload: makeThinkingPayload())
        // 有 disableBodyJSON 时，即使 thinkingEnabled=false 也应设置 extraBody
        let extra = factory.provider.captured?.extraBody as? [String: Any]
        XCTAssertNotNil(extra?["reasoning"])
    }

    /// byParameter + thinkingEnabled=false + 无 disableBodyJSON 时 extraBody 应为 nil
    func test_execute_byParameter_thinkingDisabled_noDisableBody_extraBodyNil() async throws {
        let provider = Provider(id: "an", name: "Anthropic",
                                baseURL: URL(string: "https://api")!, // swiftlint:disable:this force_unwrapping
                                apiKeyRef: "keychain:an",
                                defaultModel: "claude-4.6",
                                thinking: .byParameter(
                                    enableBodyJSON: #"{"thinking":{"type":"adaptive"}}"#,
                                    disableBodyJSON: nil
                                ))
        let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                        systemPrompt: nil, userPrompt: "{{selection}}",
                        providerId: "an", modelId: "claude-4.6",
                        temperature: nil, displayMode: .window, variables: [:],
                        thinkingEnabled: false)
        let factory = ThinkingCapturingFactory()
        let executor = makeThinkingExecutor(provider: provider, tool: tool, factory: factory)
        _ = try await executor.execute(tool: tool, payload: makeThinkingPayload())
        // disableBodyJSON=nil 时，不 merge extraBody，应为 nil
        XCTAssertNil(factory.provider.captured?.extraBody)
    }

    /// byParameter 的 enableBodyJSON 不是合法 JSON 时应抛配置错误
    func test_execute_byParameter_invalidEnableJSON_throws() async throws {
        let provider = Provider(id: "x", name: "X",
                                baseURL: URL(string: "https://api")!, // swiftlint:disable:this force_unwrapping
                                apiKeyRef: "keychain:x",
                                defaultModel: "m",
                                thinking: .byParameter(
                                    enableBodyJSON: "not valid json !!!",
                                    disableBodyJSON: nil
                                ))
        let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                        systemPrompt: nil, userPrompt: "{{selection}}",
                        providerId: "x", modelId: "m",
                        temperature: nil, displayMode: .window, variables: [:],
                        thinkingEnabled: true)
        let executor = makeThinkingExecutor(provider: provider, tool: tool,
                                            factory: ThinkingCapturingFactory())
        do {
            _ = try await executor.execute(tool: tool, payload: makeThinkingPayload())
            XCTFail("expected throw")
        } catch SliceError.configuration {
            // OK：无效 JSON 应抛配置错误
        }
    }

    /// Provider.thinking == nil 时应忽略 thinkingEnabled，使用默认 modelId 且无 extraBody
    func test_execute_providerThinkingNil_ignoresThinkingEnabled() async throws {
        let provider = Provider(id: "old", name: "Old",
                                baseURL: URL(string: "https://api")!, // swiftlint:disable:this force_unwrapping
                                apiKeyRef: "keychain:old",
                                defaultModel: "gpt-3.5",
                                thinking: nil)
        let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                        systemPrompt: nil, userPrompt: "{{selection}}",
                        providerId: "old", modelId: "gpt-3.5",
                        temperature: nil, displayMode: .window, variables: [:],
                        thinkingModelId: "gpt-4",
                        thinkingEnabled: true)
        let factory = ThinkingCapturingFactory()
        let executor = makeThinkingExecutor(provider: provider, tool: tool, factory: factory)
        _ = try await executor.execute(tool: tool, payload: makeThinkingPayload())
        // provider.thinking=nil 时，忽略 thinkingEnabled，不切换 model 也不 merge extraBody
        XCTAssertEqual(factory.provider.captured?.model, "gpt-3.5")
        XCTAssertNil(factory.provider.captured?.extraBody)
    }
}

// MARK: - Thinking test helpers

/// 为 thinking 相关测试构造 ToolExecutor
/// 使用 struct-based 轻量 fake，避免与现有 FakeConfig / FakeKeychain (actor) 混用
private func makeThinkingExecutor(provider: Provider, tool: Tool,
                                  factory: any LLMProviderFactory) -> ToolExecutor {
    let cfg = Configuration(
        schemaVersion: Configuration.currentSchemaVersion,
        providers: [provider],
        tools: [tool],
        hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
        triggers: TriggerSettings(
            floatingToolbarEnabled: true,
            commandPaletteEnabled: true,
            minimumSelectionLength: 1,
            triggerDelayMs: 100
        ),
        telemetry: TelemetrySettings(enabled: false),
        appBlocklist: []
    )
    return ToolExecutor(
        configurationProvider: ImmediateConfigProvider(cfg: cfg),
        providerFactory: factory,
        keychain: AlwaysOKKeychain()
    )
}

/// 立即返回固定 Configuration 的同步假实现（struct 无 actor 开销）
private struct ImmediateConfigProvider: ConfigurationProviding {
    let cfg: Configuration

    /// 返回固定配置
    func current() async -> Configuration { cfg }

    /// 忽略更新请求
    func update(_ configuration: Configuration) async throws {}
}

/// 始终返回固定 "test-key" 的假 Keychain 实现
private struct AlwaysOKKeychain: KeychainAccessing {
    /// 无论 providerId 是什么，返回固定的测试 key
    func readAPIKey(providerId: String) async throws -> String? { "test-key" }

    /// 忽略写入请求
    func writeAPIKey(_ value: String, providerId: String) async throws {}

    /// 忽略删除请求
    func deleteAPIKey(providerId: String) async throws {}
}

/// 构造供 thinking 测试使用的最简 SelectionPayload
private func makeThinkingPayload() -> SelectionPayload {
    SelectionPayload(
        text: "hi",
        appBundleID: "test.app",
        appName: "TestApp",
        url: nil,
        screenPoint: .zero,
        source: .accessibility,
        timestamp: Date()
    )
}
