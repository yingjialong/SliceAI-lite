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

    /// 验证 OpenAIStreamDelta 解码 OpenRouter 风格的 reasoning 字段
    func test_streamDelta_decodes_reasoningField_fromOpenRouter() throws {
        let json = """
        {"id":"c","choices":[{"delta":{"reasoning":"thinking..."},"finish_reason":null}]}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.delta.reasoning, "thinking...")
        XCTAssertNil(chunk.choices.first?.delta.reasoningContent)
    }

    /// 验证 OpenAIStreamDelta 解码 DeepSeek 风格的 reasoning_content（snake_case → camelCase）
    func test_streamDelta_decodes_reasoningContentField_fromDeepSeek() throws {
        let json = """
        {"id":"c","choices":[{"delta":{"reasoning_content":"analyzing..."},"finish_reason":null}]}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.delta.reasoningContent, "analyzing...")
        XCTAssertNil(chunk.choices.first?.delta.reasoning)
    }
}
