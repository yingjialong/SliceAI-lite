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

        // 5. 构造 ChatRequest：按 tool.thinkingEnabled × provider.thinking 决定 model + extraBody
        let baseModelId = tool.modelId ?? provider.defaultModel
        let (resolvedModelId, extraBody) = try Self.resolveThinking(
            thinking: provider.thinking,
            tool: tool,
            providerId: provider.id,
            baseModelId: baseModelId
        )
        let request = ChatRequest(
            model: resolvedModelId,
            messages: messages,
            temperature: tool.temperature,
            maxTokens: nil,
            extraBody: extraBody
        )

        // 6. 通过工厂拿到具体 LLMProvider 实例，启动流式请求
        let llm = try providerFactory.make(for: provider, apiKey: apiKey)
        return try await llm.stream(request: request)
    }

    /// 根据 provider.thinking × tool.thinkingEnabled 决定最终 model id 与 extraBody
    ///
    /// 提取为独立方法，使 execute() 函数体保持在 SwiftLint function_body_length 限制内。
    ///
    /// - Parameters:
    ///   - thinking: Provider 声明的 thinking 切换机制，nil 表示不支持 thinking
    ///   - tool: 工具定义，提供 thinkingEnabled / thinkingModelId / id（仅用于错误信息）
    ///   - providerId: Provider ID，仅用于错误信息（非用户 payload）
    ///   - baseModelId: thinking 未触发时使用的默认 model id
    /// - Returns: `(model, extraBody)` 元组
    /// - Throws: `SliceError.configuration(.invalidJSON)` — byModel 缺少 thinkingModelId，
    ///           或 byParameter 的 JSON 字符串无法解析
    private static func resolveThinking(
        thinking: ProviderThinkingCapability?,
        tool: Tool,
        providerId: String,
        baseModelId: String
    ) throws -> (modelId: String, extraBody: [String: Any]?) {
        guard let thinking else {
            // Provider 不支持 thinking，忽略 thinkingEnabled，直接使用默认 model
            return (baseModelId, nil)
        }

        switch thinking {
        case .byModel:
            // byModel：thinking=on 时必须切换到 thinkingModelId
            if tool.thinkingEnabled {
                guard let alt = tool.thinkingModelId else {
                    let msg = "Tool '\(tool.id)' thinkingEnabled=true but no thinkingModelId"
                        + " for Provider '\(providerId)' (byModel)"
                    throw SliceError.configuration(.invalidJSON(msg))
                }
                // 切换到 thinking 专用 model，不注入 extraBody
                return (alt, nil)
            }
            // thinking=off：使用默认 model
            return (baseModelId, nil)

        case .byParameter(let enableJSON, let disableJSON):
            // byParameter：根据 thinkingEnabled 选择对应 JSON payload
            let payload = tool.thinkingEnabled ? enableJSON : disableJSON
            guard let json = payload else {
                // disableBodyJSON=nil 时不 merge，extraBody 为 nil
                return (baseModelId, nil)
            }
            // 解析 JSON 字符串到 [String: Any]
            let dict = try Self.parseExtraBodyJSON(json)
            return (baseModelId, dict)
        }
    }

    /// 将 JSON 字符串解析为 [String: Any] 字典
    ///
    /// - Parameter json: thinking template 的 JSON 字符串（enableBodyJSON / disableBodyJSON）
    /// - Returns: 解析后的字典，用作 ChatRequest.extraBody
    /// - Throws: `SliceError.configuration(.invalidJSON)` — 非合法 JSON 或顶层不是 object
    private static func parseExtraBodyJSON(_ json: String) throws -> [String: Any] {
        do {
            let data = Data(json.utf8)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SliceError.configuration(
                    .invalidJSON("thinking template payload must be a JSON object")
                )
            }
            return dict
        } catch let error as SliceError {
            throw error
        } catch {
            // JSONSerialization 失败，内容不重要（可能含用户 secret），不透传
            throw SliceError.configuration(
                .invalidJSON("thinking template parse failed (see tool/provider config)")
            )
        }
    }
}
