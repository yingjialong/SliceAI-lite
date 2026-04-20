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

    /// 默认配置仅附带一个 OpenAI 官方 Provider
    func test_defaultConfig_hasOneProvider() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.providers.count, 1)
        XCTAssertEqual(cfg.providers.first?.id, "openai-official")
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
