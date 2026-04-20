import Foundation

/// 首次启动时注入的默认配置，包含 1 个 Provider 和 4 个内置工具
/// 说明：
///   - 使用 `enum` 作为命名空间，无法被实例化，强制调用方通过静态方法 / 属性访问；
///   - `initial()` 用于 App 首次启动时写入 config.json；
///   - 各个静态工具/Provider 属性公开暴露，便于测试与单元调试。
public enum DefaultConfiguration {

    /// 生成 App 首次启动时写入磁盘的完整配置
    /// - Returns: 包含 1 个 OpenAI Provider 与 4 个内置工具的 Configuration
    public static func initial() -> Configuration {
        // 组装默认聚合配置（触发、快捷键、遥测均使用保守默认值）
        Configuration(
            schemaVersion: Configuration.currentSchemaVersion,
            providers: [openAIDefault],
            tools: [translate, polish, summarize, explain],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
            triggers: TriggerSettings(
                floatingToolbarEnabled: true,
                commandPaletteEnabled: true,
                minimumSelectionLength: 1,
                triggerDelayMs: 150
            ),
            telemetry: TelemetrySettings(enabled: false),
            appBlocklist: [
                // 常见密码 / 密钥管理类 App，默认屏蔽以降低泄露风险
                "com.apple.keychainaccess",
                "com.1password.1password",
                "com.1password.1password7",
                "com.bitwarden.desktop"
            ]
        )
    }

    // MARK: - Provider

    /// OpenAI 官方 API Provider，作为首次启动时唯一预置的 Provider
    public static let openAIDefault = Provider(
        id: "openai-official",
        name: "OpenAI",
        // 硬编码的常量字符串，强制解包安全
        baseURL: URL(string: "https://api.openai.com/v1")!, // swiftlint:disable:this force_unwrapping
        apiKeyRef: "keychain:openai-official",
        defaultModel: "gpt-5"
    )

    // MARK: - Tools

    /// 翻译工具：将选中文字翻译为 variables["language"] 指定的语言
    public static let translate = Tool(
        id: "translate", name: "Translate", icon: "🌐",
        description: "将选中文字翻译为指定语言",
        systemPrompt: "You are a professional translator. Translate faithfully and naturally. "
                    + "Output only the translation without explanations.",
        userPrompt: "Translate the following to {{language}}:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.3,
        displayMode: .window,
        variables: ["language": "Simplified Chinese"]
    )

    /// 润色工具：在保持原意的前提下润色选中文字
    public static let polish = Tool(
        id: "polish", name: "Polish", icon: "📝",
        description: "在保持原意的前提下润色文字",
        systemPrompt: "You are an expert editor. Polish the text while preserving the author's "
                    + "voice and meaning. Output only the polished version.",
        userPrompt: "Polish the following text:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.4,
        displayMode: .window,
        variables: [:]
    )

    /// 摘要工具：用 Markdown 列表总结选中文字
    public static let summarize = Tool(
        id: "summarize", name: "Summarize", icon: "✨",
        description: "总结关键要点",
        systemPrompt: "You are an expert summarizer. Produce concise, structured summaries.",
        userPrompt: "Summarize the key points of the following text. Use Markdown bullet points:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.3,
        displayMode: .window,
        variables: [:]
    )

    /// 解释工具：用浅显语言解释选中的术语或句子
    public static let explain = Tool(
        id: "explain", name: "Explain", icon: "💡",
        description: "解释专业术语或生词",
        systemPrompt: "You are a patient teacher. Explain concepts clearly, assuming an "
                    + "educated but non-expert audience.",
        userPrompt: "Explain the following in simple terms. If it's a technical term or acronym, "
                  + "expand and contextualize:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.4,
        displayMode: .window,
        variables: [:]
    )
}
