import Foundation
import OSLog

/// FileConfigurationStore 的日志器，便于调试 load/save 路径与错误转译
private let configLog = Logger(subsystem: "com.sliceai.core", category: "ConfigurationStore")

/// 以 JSON 文件为后端的 `Configuration` 读写 actor
///
/// 设计要点：
///   - 作为 `actor` 保证所有读写被串行化，避免并发写入导致文件损坏；
///   - `current()` 作为热路径（调用者可能非常频繁）在内存里缓存一份配置，失败时回退到默认值；
///   - `load()` 会把底层 JSON / IO 错误统一转译为 `SliceError.configuration(.invalidJSON)`，
///     以便上层只处理 `SliceError` 族；
///   - `save()` 使用原子写入（`.atomic`）+ 自动创建父目录，杜绝半写文件；
///   - `standardFileURL()` 给出 App 部署时的约定路径 `~/Library/Application Support/SliceAI/config.json`，
///     但 actor 本身并不依赖这条路径，便于测试注入临时文件。
public actor FileConfigurationStore: ConfigurationProviding {

    /// 目标 JSON 文件的绝对路径
    private let fileURL: URL
    /// 上次成功读/写的配置缓存，避免重复 IO
    private var cached: Configuration?

    /// 构造 FileConfigurationStore
    /// - Parameter fileURL: 目标 JSON 文件路径（不要求已存在）
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 获取当前配置：优先命中缓存，其次尝试从磁盘加载，失败回退到默认配置
    /// - Returns: 始终返回一个可用的 Configuration（不会抛错）
    public func current() async -> Configuration {
        // 1. 命中内存缓存直接返回
        if let cached {
            return cached
        }
        // 2. 尝试从磁盘加载（文件缺失 / 损坏时走 catch）
        if let loaded = try? await load() {
            cached = loaded
            // swiftlint:disable:next line_length
            configLog.debug("current() loaded config from disk, schemaVersion=\(loaded.schemaVersion, privacy: .public)")
            return loaded
        }
        // 3. 最终保险：返回内置默认配置并缓存
        let fallback = DefaultConfiguration.initial()
        cached = fallback
        configLog.debug("current() falling back to DefaultConfiguration.initial()")
        return fallback
    }

    /// 更新配置并持久化；写入成功后刷新缓存
    /// - Parameter configuration: 新的配置快照
    public func update(_ configuration: Configuration) async throws {
        try await save(configuration)
        cached = configuration
    }

    /// 从磁盘加载配置
    /// - Returns: 解码出的 Configuration；当文件不存在时返回默认配置
    /// - Throws: `SliceError.configuration(.invalidJSON)` 或 `.schemaVersionTooNew`
    public func load() async throws -> Configuration {
        // 文件不存在属于合法状态（首次启动），返回默认值以便上层继续流程
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            configLog.debug("load() file not found, returning DefaultConfiguration.initial()")
            return DefaultConfiguration.initial()
        }

        // 读取文件内容，读失败（权限 / 磁盘）一律视为 invalidJSON
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            configLog.error("load() read failed: \(error.localizedDescription, privacy: .public)")
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }

        // 解码 JSON；结构不符或非 JSON 都会落到 catch
        let decoder = JSONDecoder()
        let cfg: Configuration
        do {
            cfg = try decoder.decode(Configuration.self, from: data)
        } catch {
            configLog.error("load() decode failed: \(error.localizedDescription, privacy: .public)")
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }

        // schemaVersion 高于当前支持版本意味着用户使用了更新的 App 写入的配置
        if cfg.schemaVersion > Configuration.currentSchemaVersion {
            configLog.error("load() schema too new: \(cfg.schemaVersion, privacy: .public)")
            throw SliceError.configuration(.schemaVersionTooNew(cfg.schemaVersion))
        }
        return cfg
    }

    /// 将配置写入磁盘（pretty-printed，便于人工审阅 diff）
    /// - Parameter configuration: 要写入的配置快照
    public func save(_ configuration: Configuration) async throws {
        // 编码为稳定排序的可读 JSON，保证同一配置产出相同字节，利于 diff/版本控制
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        // 父目录可能尚未创建（例如 ~/Library/Application Support/SliceAI）
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 原子写入：失败不会留下半写文件
        try data.write(to: fileURL, options: .atomic)
        configLog.debug("save() wrote config, bytes=\(data.count, privacy: .public)")
    }

    /// 仅更新 appearance 字段并持久化，避免外部传整个 Configuration 覆盖其他字段
    ///
    /// 典型调用方：`ThemeManager.onModeChange` 回调，用户切换主题时持久化新模式。
    /// 实现上先取当前缓存（或磁盘）快照，改 appearance 后走 update() 写回。
    /// - Parameter mode: 新的主题模式
    /// - Throws: 磁盘写入失败时向上透传 IO 错误
    public func updateAppearance(_ mode: AppearanceMode) async throws {
        // 读取当前配置快照（命中缓存则不产生磁盘 IO）
        var cfg = await current()
        // 仅修改 appearance，其余字段保持不变
        cfg.appearance = mode
        // 写回磁盘并刷新缓存
        try await update(cfg)
        configLog.info("updateAppearance: persisted mode=\(mode.rawValue, privacy: .public)")
    }

    /// App 部署时 config.json 的约定路径
    /// - Returns: `~/Library/Application Support/SliceAI/config.json`
    public static func standardFileURL() -> URL {
        let fm = FileManager.default
        // `.first!` 安全：userDomainMask 下的 ApplicationSupport 在 macOS 上永远存在
        // swiftlint:disable:next force_unwrapping
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("config.json")
    }
}
