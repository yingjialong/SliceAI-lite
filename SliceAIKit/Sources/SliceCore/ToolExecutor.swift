import Foundation

/// 工具执行的中枢：渲染 prompt → 取 Provider + API Key → 转发到 LLMProvider 流
///
/// 设计要点：
///   - `actor` 保证多次并发触发划词时，内部查询 Configuration / Keychain 无竞争；
///   - 依赖全部通过协议注入（DI），便于在单元测试中传入 Fake 实现；
///   - 不直接持有 API Key 等敏感数据，流程上由 Keychain 临时读出并即时传给工厂。
public actor ToolExecutor {

    /// 全局 Configuration 提供者，决定了 Tool → Provider 的路由
    private let configurationProvider: any ConfigurationProviding
    /// LLM Provider 工厂，根据 Provider + API Key 构造真正的调用实例
    private let providerFactory: any LLMProviderFactory
    /// Keychain 访问协议，用于按 providerId 读取 API Key
    private let keychain: any KeychainAccessing

    /// 构造 ToolExecutor
    /// - Parameters:
    ///   - configurationProvider: 读取当前 Configuration 的协议实现
    ///   - providerFactory: 创建 LLMProvider 的工厂实现
    ///   - keychain: Keychain 访问实现（生产用真实 Keychain，测试用 Fake）
    public init(
        configurationProvider: any ConfigurationProviding,
        providerFactory: any LLMProviderFactory,
        keychain: any KeychainAccessing
    ) {
        self.configurationProvider = configurationProvider
        self.providerFactory = providerFactory
        self.keychain = keychain
    }

    /// 执行一次工具调用
    /// - Parameters:
    ///   - tool: 要执行的工具（包含 prompt 模板、providerId、模型等）
    ///   - payload: 选中文字及上下文信息（应用名、URL 等），用于变量替换
    /// - Returns: 流式 chunk，由 UI 层消费并渲染
    /// - Throws:
    ///   - `SliceError.configuration(.referencedProviderMissing(_))`：Tool.providerId 找不到
    ///   - `SliceError.provider(.unauthorized)`：Keychain 中没有 API Key 或 API Key 为空
    ///   - 其他底层错误由 LLMProvider 抛出
    public func execute(
        tool: Tool,
        payload: SelectionPayload
    ) async throws -> AsyncThrowingStream<ChatChunk, any Error> {

        // 1. 取当前配置，并按 tool.providerId 定位目标 Provider
        let cfg = await configurationProvider.current()
        guard let provider = cfg.providers.first(where: { $0.id == tool.providerId }) else {
            // 工具引用的 provider 不存在，直接抛配置错误
            throw SliceError.configuration(.referencedProviderMissing(tool.providerId))
        }

        // 2. 优先按 Provider.apiKeyRef（形如 "keychain:<account>"）解析 Keychain 账户
        //    非 keychain: 前缀（未来可能支持 env: 等）或空值一律按未授权处理
        guard let account = provider.keychainAccount else {
            throw SliceError.provider(.unauthorized)
        }
        guard let apiKey = try await keychain.readAPIKey(providerId: account),
              !apiKey.isEmpty else {
            throw SliceError.provider(.unauthorized)
        }

        // 3. 渲染变量：工具预置变量作为基底，再注入内置系统变量
        //    约定：内置变量总是覆盖同名的工具变量，避免用户意外定义 {{selection}} 污染
        var variables: [String: String] = tool.variables
        variables["selection"] = payload.text
        variables["app"] = payload.appName
        variables["url"] = payload.url?.absoluteString ?? ""
        // 无 language 时默认空字符串，避免 {{language}} 保留原样出现在 prompt 中
        if variables["language"] == nil { variables["language"] = "" }

        // 4. 渲染 userPrompt，必要时渲染 systemPrompt，组装 ChatMessage 数组
        let userText = PromptTemplate.render(tool.userPrompt, variables: variables)
        var messages: [ChatMessage] = []
        if let sys = tool.systemPrompt, !sys.isEmpty {
            let systemText = PromptTemplate.render(sys, variables: variables)
            messages.append(ChatMessage(role: .system, content: systemText))
        }
        messages.append(ChatMessage(role: .user, content: userText))

        // 5. 构造 ChatRequest：model 优先使用 tool.modelId，其次用 provider.defaultModel
        let request = ChatRequest(
            model: tool.modelId ?? provider.defaultModel,
            messages: messages,
            temperature: tool.temperature,
            maxTokens: nil
        )

        // 6. 通过工厂拿到具体 LLMProvider 实例，启动流式请求
        let llm = try providerFactory.make(for: provider, apiKey: apiKey)
        return try await llm.stream(request: request)
    }
}
