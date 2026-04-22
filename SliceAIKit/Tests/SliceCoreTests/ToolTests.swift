import XCTest
@testable import SliceCore

final class ToolTests: XCTestCase {
    func test_toolCodable_roundTrip() throws {
        // 显式传 labelStyle 验证非默认值也能正确 round-trip
        let tool = Tool(
            id: "translate", name: "Translate", icon: "🌐", description: nil,
            systemPrompt: "sys", userPrompt: "u {{selection}}",
            providerId: "openai", modelId: nil, temperature: 0.3,
            displayMode: .window, variables: ["language": "English"],
            labelStyle: .iconAndName
        )
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(Tool.self, from: data)
        XCTAssertEqual(decoded, tool)
    }

    func test_displayMode_rawValues() {
        XCTAssertEqual(DisplayMode.window.rawValue, "window")
        XCTAssertEqual(DisplayMode.bubble.rawValue, "bubble")
        XCTAssertEqual(DisplayMode.replace.rawValue, "replace")
    }

    func test_providerCodable_roundTrip() throws {
        let p = Provider(id: "openai", name: "OpenAI",
                         baseURL: URL(string: "https://api.openai.com/v1")!,
                         apiKeyRef: "keychain:openai", defaultModel: "gpt-5")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Provider.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    /// labelStyle 的 rawValue 必须保持稳定——写入 config.json 的字符串是长期契约
    func test_toolLabelStyle_rawValues() {
        XCTAssertEqual(ToolLabelStyle.icon.rawValue, "icon")
        XCTAssertEqual(ToolLabelStyle.name.rawValue, "name")
        XCTAssertEqual(ToolLabelStyle.iconAndName.rawValue, "iconAndName")
        XCTAssertEqual(ToolLabelStyle.allCases.count, 3)
    }

    /// 老版本 config.json 里没有 labelStyle 字段时，decode 应回退到 `.icon`，
    /// 避免升级后老配置打不开——Tool 的自定义 `init(from:)` 承担此兼容。
    func test_toolDecode_legacyJSONWithoutLabelStyle_defaultsToIcon() throws {
        let legacyJSON = """
        {
            "id": "old-tool",
            "name": "Old Tool",
            "icon": "🌐",
            "userPrompt": "{{selection}}",
            "providerId": "openai",
            "displayMode": "window",
            "variables": {}
        }
        """.data(using: .utf8)!  // swiftlint:disable:this force_unwrapping

        let decoded = try JSONDecoder().decode(Tool.self, from: legacyJSON)
        XCTAssertEqual(decoded.labelStyle, .icon)
        XCTAssertEqual(decoded.id, "old-tool")
        XCTAssertEqual(decoded.name, "Old Tool")
    }
}
