import XCTest
@testable import SliceCore

/// DefaultConfiguration 工厂的单元测试，验证首次启动注入的默认配置是否符合约定
final class DefaultConfigurationTests: XCTestCase {

    /// 默认配置必须恰好包含四个内置工具，且 id 与规范一致
    func test_defaultConfig_hasFourTools() {
        // 调用工厂获得初始配置
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.tools.count, 4)
        // 使用 Set 比较，避免顺序耦合
        let ids = Set(cfg.tools.map(\.id))
        XCTAssertEqual(ids, ["translate", "polish", "summarize", "explain"])
    }

    /// 默认配置必须预置 OpenAI / OpenRouter / DeepSeek V4 三家 Provider
    ///
    /// 用 Set 比较以避免顺序耦合；如未来新增 / 删除 seed Provider，需同步更新此用例。
    func test_defaultConfig_hasThreeProviders() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.providers.count, 3)
        let ids = Set(cfg.providers.map(\.id))
        XCTAssertEqual(ids, ["openai-official", "openrouter", "deepseek-v4"])
    }

    /// 三个 seed Provider 的 thinking 字段必须均预填为 byParameter 模式
    ///
    /// 各家 enable / disable JSON 字面值必须与 `SettingsUI/Thinking/ThinkingTemplate.swift`
    /// 中相应模板（openAIReasoningEffort / openRouterUnified / deepSeekV4）保持字符精确一致，
    /// 否则 ProviderEditorView 打开默认 Provider 时 ThinkingTemplate.match() 将匹配失败、
    /// UI 错显为"自定义"模板，破坏首次启动的开箱即用体验。
    func test_defaultConfig_providersThinkingPrefilled() {
        let cfg = DefaultConfiguration.initial()
        // 用 id → Provider 的字典，按 id 单测，避免数组顺序耦合
        let byId = Dictionary(uniqueKeysWithValues: cfg.providers.map { ($0.id, $0) })

        // OpenAI: reasoning_effort
        XCTAssertEqual(
            byId["openai-official"]?.thinking,
            .byParameter(
                enableBodyJSON: #"{"reasoning_effort":"medium"}"#,
                disableBodyJSON: #"{"reasoning_effort":"minimal"}"#
            )
        )
        // OpenRouter: unified reasoning.effort
        XCTAssertEqual(
            byId["openrouter"]?.thinking,
            .byParameter(
                enableBodyJSON: #"{"reasoning":{"effort":"medium"}}"#,
                disableBodyJSON: #"{"reasoning":{"effort":"none"}}"#
            )
        )
        // DeepSeek V4: thinking.type
        XCTAssertEqual(
            byId["deepseek-v4"]?.thinking,
            .byParameter(
                enableBodyJSON: #"{"thinking":{"type":"enabled"}}"#,
                disableBodyJSON: #"{"thinking":{"type":"disabled"}}"#
            )
        )
    }

    /// 每个工具引用的 providerId 必须指向已注册的 Provider
    func test_defaultConfig_allToolsReferValidProvider() {
        let cfg = DefaultConfiguration.initial()
        let providerIds = Set(cfg.providers.map(\.id))
        for tool in cfg.tools {
            XCTAssertTrue(providerIds.contains(tool.providerId),
                          "Tool \(tool.id) refers missing provider \(tool.providerId)")
        }
    }

    /// 所有工具的 userPrompt 必须包含 {{selection}} 占位符，否则选中文字无法注入
    func test_defaultConfig_promptsContainSelection() {
        for tool in DefaultConfiguration.initial().tools {
            XCTAssertTrue(tool.userPrompt.contains("{{selection}}"),
                          "Tool \(tool.id) missing {{selection}} in userPrompt")
        }
    }
}
