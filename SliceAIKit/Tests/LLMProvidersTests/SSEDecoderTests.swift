import XCTest
@testable import LLMProviders

final class SSEDecoderTests: XCTestCase {
    func test_decodesSingleDataEvent() {
        var decoder = SSEDecoder()
        let events = decoder.feed("data: hello\n\n")
        XCTAssertEqual(events, [.data("hello")])
    }

    func test_decodesMultipleEventsAcrossChunks() {
        var decoder = SSEDecoder()
        var events = decoder.feed("data: a\n\n")
        events += decoder.feed("data: b\n\ndata: c")   // c incomplete
        events += decoder.feed("\n\n")
        XCTAssertEqual(events, [.data("a"), .data("b"), .data("c")])
    }

    func test_doneMarker() {
        var decoder = SSEDecoder()
        let events = decoder.feed("data: [DONE]\n\n")
        XCTAssertEqual(events, [.done])
    }

    func test_ignoresCommentsAndUnknownFields() {
        var decoder = SSEDecoder()
        let events = decoder.feed(": heartbeat\n\nevent: update\ndata: x\n\n")
        XCTAssertEqual(events, [.data("x")])
    }

    func test_handlesHappyFixture() throws {
        let url = Bundle.module.url(forResource: "openai_chat_happy", withExtension: "sse",
                                    subdirectory: "Fixtures")
        let data = try Data(contentsOf: XCTUnwrap(url))
        let text = String(data: data, encoding: .utf8)!
        var decoder = SSEDecoder()
        let events = decoder.feed(text)
        let count = events.filter { if case .data = $0 { return true }; return false }.count
        XCTAssertEqual(count, 3)
        XCTAssertEqual(events.last, .done)
    }
}
