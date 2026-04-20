import XCTest
@testable import SliceCore

final class ToolTests: XCTestCase {
    func test_toolCodable_roundTrip() throws {
        let tool = Tool(
            id: "translate", name: "Translate", icon: "🌐", description: nil,
            systemPrompt: "sys", userPrompt: "u {{selection}}",
            providerId: "openai", modelId: nil, temperature: 0.3,
            displayMode: .window, variables: ["language": "English"]
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
}
