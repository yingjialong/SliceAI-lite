import XCTest
@testable import LLMProviders

final class OpenAIDTOsTests: XCTestCase {
    func test_decodesDeltaChunk() throws {
        let json = """
        {"id":"c","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.delta.content, "Hi")
        XCTAssertNil(chunk.choices.first?.finishReason)
    }

    func test_decodesFinishChunk() throws {
        let json = """
        {"id":"c","choices":[{"delta":{},"finish_reason":"stop"}]}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.finishReason, "stop")
        XCTAssertNil(chunk.choices.first?.delta.content)
    }
}
