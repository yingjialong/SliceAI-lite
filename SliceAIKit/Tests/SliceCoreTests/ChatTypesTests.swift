import XCTest
@testable import SliceCore

final class ChatTypesTests: XCTestCase {
    func test_chatMessageEncoding_systemRole() throws {
        let msg = ChatMessage(role: .system, content: "You are helpful.")
        let data = try JSONEncoder().encode(msg)
        let s = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(s.contains("\"role\":\"system\""))
        XCTAssertTrue(s.contains("\"content\":\"You are helpful.\""))
    }

    func test_chatRequest_nilFieldsOmitted() throws {
        // temperature/maxTokens 为 nil 时必须不出现在 JSON 中，保持服务端默认
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: nil, maxTokens: nil)
        let data = try JSONEncoder().encode(req)
        let s = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(s.contains("temperature"))
        XCTAssertFalse(s.contains("max_tokens"))
        XCTAssertTrue(s.contains("\"model\":\"gpt-5\""))
    }

    func test_chatRequest_nonNilFieldsPresent() throws {
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: 0.5, maxTokens: 100)
        let data = try JSONEncoder().encode(req)
        let s = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(s.contains("\"temperature\":0.5"))
        XCTAssertTrue(s.contains("\"max_tokens\":100"))
    }

    func test_finishReason_rawValuesStable() {
        // rawValue 是线上协议兼容的基础，snake_case 映射必须稳定
        XCTAssertEqual(FinishReason.stop.rawValue, "stop")
        XCTAssertEqual(FinishReason.length.rawValue, "length")
        XCTAssertEqual(FinishReason.contentFilter.rawValue, "content_filter")
        XCTAssertEqual(FinishReason.toolCalls.rawValue, "tool_calls")
    }

    /// extraBody 内容相同时两个 ChatRequest 应相等（NSDictionary 桥接比较）
    func test_chatRequest_extraBodyEqual_whenContentsMatch() {
        let a = ChatRequest(model: "m", messages: [],
                            extraBody: ["thinking": ["type": "enabled"]])
        let b = ChatRequest(model: "m", messages: [],
                            extraBody: ["thinking": ["type": "enabled"]])
        XCTAssertEqual(a, b)
    }

    /// extraBody 内容不同时两个 ChatRequest 应不相等
    func test_chatRequest_extraBodyDiffer_notEqual() {
        let a = ChatRequest(model: "m", messages: [],
                            extraBody: ["thinking": ["type": "enabled"]])
        let b = ChatRequest(model: "m", messages: [],
                            extraBody: ["thinking": ["type": "disabled"]])
        XCTAssertNotEqual(a, b)
    }

    /// 一边 nil 一边有内容的 extraBody 应不相等
    func test_chatRequest_extraBodyOneNil_notEqual() {
        let a = ChatRequest(model: "m", messages: [], extraBody: nil)
        let b = ChatRequest(model: "m", messages: [], extraBody: ["foo": 1])
        XCTAssertNotEqual(a, b)
    }

    /// extraBody 不参与 Codable：encode 后的 JSON 不含 extraBody 字段
    func test_chatRequest_extraBody_notInJSONOutput() throws {
        let req = ChatRequest(model: "m", messages: [],
                              extraBody: ["thinking": ["type": "enabled"]])
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNil(json?["extraBody"])
        XCTAssertNil(json?["thinking"])  // 也不会泄漏到 root
    }

    /// ChatChunk 的 reasoningDelta 字段在构造时正确赋值
    func test_chatChunk_reasoningDelta_init() {
        let chunk = ChatChunk(delta: "answer", reasoningDelta: "thinking", finishReason: nil)
        XCTAssertEqual(chunk.delta, "answer")
        XCTAssertEqual(chunk.reasoningDelta, "thinking")
    }

    /// 默认参数下 reasoningDelta 为 nil（兼容非 thinking 模型）
    func test_chatChunk_reasoningDelta_defaultsNil() {
        let chunk = ChatChunk(delta: "answer")
        XCTAssertNil(chunk.reasoningDelta)
    }
}
