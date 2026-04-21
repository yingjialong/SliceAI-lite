import XCTest
@testable import SliceCore

/// FileConfigurationStore 的行为契约测试
/// 覆盖：
///   - save/load 往返保真（round-trip）
///   - 文件不存在时回退到默认配置
///   - JSON 非法时抛出 .configuration(.invalidJSON)
///   - schemaVersion 高于当前应用支持版本时抛出 .configuration(.schemaVersionTooNew)
final class ConfigurationStoreTests: XCTestCase {

    /// 生成一个隔离的临时文件 URL，用于避免并发测试相互污染
    /// - Returns: 位于系统临时目录、文件名为 UUID 的 .json 路径
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    /// 场景 1：保存默认配置后再加载，结果应与原配置完全一致
    func test_save_thenLoad_roundTrip() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileConfigurationStore(fileURL: url)

        // 写入默认配置，再读回并比对 Equatable
        let original = DefaultConfiguration.initial()
        try await store.save(original)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, original)
    }

    /// 场景 2：目标文件不存在时，load() 应返回默认配置而非抛错
    func test_load_missingFile_returnsDefault() async throws {
        let url = tempFile()
        let store = FileConfigurationStore(fileURL: url)
        let cfg = try await store.load()
        XCTAssertEqual(cfg.schemaVersion, Configuration.currentSchemaVersion)
    }

    /// 场景 3：文件存在但内容非 JSON，应抛出 .configuration(.invalidJSON)
    func test_load_invalidJSON_throws() async throws {
        let url = tempFile()
        try "not json".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileConfigurationStore(fileURL: url)
        do {
            _ = try await store.load()
            XCTFail("expected throw")
        } catch SliceError.configuration(.invalidJSON) {
            // 预期路径：底层解码失败后转译为 invalidJSON
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 场景 5：updateAppearance 持久化后 reload 确认 dark
    func test_updateAppearance_persistsToFile() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileConfigurationStore(fileURL: url)

        // 先写入默认配置（appearance=.auto）
        try await store.save(DefaultConfiguration.initial())

        // 调 updateAppearance(.dark)
        try await store.updateAppearance(.dark)

        // 用一个新 store 实例（无缓存）从磁盘重新读，确认 dark 已写入
        let freshStore = FileConfigurationStore(fileURL: url)
        let loaded = try await freshStore.load()
        XCTAssertEqual(loaded.appearance, .dark, "updateAppearance 应将 dark 持久化到文件")
    }

    /// 场景 4：schemaVersion 高于当前应用支持版本，应抛出 schemaVersionTooNew(99)
    func test_load_schemaVersionTooNew_throws() async throws {
        let url = tempFile()
        let json = """
        { "schemaVersion": 99, "providers": [], "tools": [], "hotkeys": {"toggleCommandPalette":"option+space"},
          "triggers":{"floatingToolbarEnabled":true,"commandPaletteEnabled":true,"minimumSelectionLength":1,"triggerDelayMs":150},
          "telemetry":{"enabled":false}, "appBlocklist":[] }
        """
        try json.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileConfigurationStore(fileURL: url)
        do {
            _ = try await store.load()
            XCTFail("expected throw")
        } catch SliceError.configuration(.schemaVersionTooNew(99)) {
            // 预期路径：解码成功但版本过新
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
