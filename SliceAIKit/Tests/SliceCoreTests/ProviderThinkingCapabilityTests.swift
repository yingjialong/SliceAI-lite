import XCTest
@testable import SliceCore

/// 验证 ProviderThinkingCapability 的 Codable round-trip 行为
final class ProviderThinkingCapabilityTests: XCTestCase {

    /// 验证 byModel case 的 Codable round-trip
    func test_byModel_codableRoundTrip() throws {
        let original = ProviderThinkingCapability.byModel
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderThinkingCapability.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    /// 验证 byParameter case 含 enable + nil disable 的 round-trip
    func test_byParameter_nilDisable_codableRoundTrip() throws {
        let original = ProviderThinkingCapability.byParameter(
            enableBodyJSON: #"{"thinking":{"type":"enabled"}}"#,
            disableBodyJSON: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderThinkingCapability.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    /// 验证 byParameter case 含 enable + 显式 disable 的 round-trip
    func test_byParameter_withDisable_codableRoundTrip() throws {
        let original = ProviderThinkingCapability.byParameter(
            enableBodyJSON: #"{"reasoning":{"effort":"medium"}}"#,
            disableBodyJSON: #"{"reasoning":{"effort":"none"}}"#
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderThinkingCapability.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
