import XCTest
@testable import SliceCore

final class SelectionPayloadTests: XCTestCase {
    func test_equatableByAllFields() {
        // 两个 payload 所有字段相等时应当 ==
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SelectionPayload(
            text: "hi", appBundleID: "com.apple.Safari", appName: "Safari",
            url: URL(string: "https://example.com"), screenPoint: CGPoint(x: 10, y: 20),
            source: .accessibility, timestamp: date
        )
        let b = SelectionPayload(
            text: "hi", appBundleID: "com.apple.Safari", appName: "Safari",
            url: URL(string: "https://example.com"), screenPoint: CGPoint(x: 10, y: 20),
            source: .accessibility, timestamp: date
        )
        XCTAssertEqual(a, b)
    }

    func test_sourceRawValuesStable() {
        // rawValue 是 Codable 持久化基础，必须稳定
        XCTAssertEqual(SelectionPayload.Source.accessibility.rawValue, "accessibility")
        XCTAssertEqual(SelectionPayload.Source.clipboardFallback.rawValue, "clipboardFallback")
    }
}
