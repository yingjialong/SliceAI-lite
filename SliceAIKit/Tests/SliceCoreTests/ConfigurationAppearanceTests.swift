import XCTest
@testable import SliceCore

/// Configuration.appearance 字段测试（TDD 驱动）
///
/// 验证：
/// 1. 默认值为 `.auto`
/// 2. 不含 appearance 的旧版 JSON 解码后回落到 `.auto`（向后兼容）
/// 3. 含 appearance=dark 的 JSON 解码正确
/// 4. 编码结果包含 appearance 字段
final class ConfigurationAppearanceTests: XCTestCase {

    // MARK: - 辅助：最小合法 JSON（不含 appearance）

    private let legacyJSON = """
    {
      "schemaVersion": 1,
      "providers": [],
      "tools": [],
      "hotkeys": { "toggleCommandPalette": "option+space" },
      "triggers": {
        "floatingToolbarEnabled": true,
        "commandPaletteEnabled": true,
        "minimumSelectionLength": 1,
        "triggerDelayMs": 150
      },
      "telemetry": { "enabled": false },
      "appBlocklist": []
    }
    """.data(using: .utf8)!

    // MARK: - 测试

    /// 通过 memberwise init 构造的 Configuration，appearance 默认值为 .auto
    func test_default_appearance_isAuto() {
        let cfg = Configuration(
            schemaVersion: 1,
            providers: [],
            tools: [],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
            triggers: TriggerSettings(
                floatingToolbarEnabled: true,
                commandPaletteEnabled: true,
                minimumSelectionLength: 1,
                triggerDelayMs: 150
            ),
            telemetry: TelemetrySettings(enabled: false),
            appBlocklist: []
        )
        // 默认 appearance 应为 .auto
        XCTAssertEqual(cfg.appearance, .auto)
    }

    /// 不含 appearance 字段的旧版 JSON 解码后，appearance 回落到 .auto
    func test_decode_legacyJsonWithoutAppearance_defaultsToAuto() throws {
        let cfg = try JSONDecoder().decode(Configuration.self, from: legacyJSON)
        XCTAssertEqual(cfg.appearance, .auto)
    }

    /// 含 appearance=dark 的 JSON 解码正确
    func test_decode_jsonWithAppearance_parsesDark() throws {
        // 在 JSON 末尾 } 前插入 appearance 字段
        let jsonStr = String(data: legacyJSON, encoding: .utf8)!
            .replacingOccurrences(
                of: "\"appBlocklist\": []",
                with: "\"appBlocklist\": [], \"appearance\": \"dark\""
            )
        let json = jsonStr.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(Configuration.self, from: json)
        XCTAssertEqual(cfg.appearance, .dark)
    }

    /// 编码后 JSON 包含 "appearance":"light"（用结构化解析替代字符串 contains，更健壮）
    func test_encode_includesAppearance() throws {
        var cfg = try JSONDecoder().decode(Configuration.self, from: legacyJSON)
        cfg.appearance = .light
        let encoded = try JSONEncoder().encode(cfg)
        // 用 JSONSerialization 解析为字典，避免 contains 误匹配其他 key/value
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any],
            "编码结果应为合法 JSON 对象"
        )
        XCTAssertEqual(dict["appearance"] as? String, "light", "编码结果 appearance 应为 light")
    }
}
