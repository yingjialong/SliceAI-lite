import Foundation

/// 工具定义，一个 Tool 代表菜单栏上的一个按钮 + 一套 prompt
public struct Tool: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var icon: String              // emoji 或 SF Symbol 名
    public var description: String?
    public var systemPrompt: String?
    public var userPrompt: String
    public var providerId: String        // 指向 Configuration.providers 中的 Provider.id
    public var modelId: String?          // nil 则使用 Provider.defaultModel
    public var temperature: Double?
    public var displayMode: DisplayMode
    public var variables: [String: String]
    /// 浮条上的显示样式（图标 / 名称 / 图标+名称）；默认 `.icon`
    public var labelStyle: ToolLabelStyle

    /// 构造工具定义
    /// - Parameters:
    ///   - id: 工具唯一标识，用于持久化与路由
    ///   - name: 工具显示名称
    ///   - icon: emoji 或 SF Symbol 名称
    ///   - description: 工具用途的可选描述
    ///   - systemPrompt: 可选的系统提示词
    ///   - userPrompt: 用户提示词模板（含 `{{selection}}` 等占位符）
    ///   - providerId: 关联的 Provider.id
    ///   - modelId: 指定模型，nil 时使用 Provider.defaultModel
    ///   - temperature: 采样温度，nil 时沿用服务端默认
    ///   - displayMode: 结果展示模式
    ///   - variables: 用户自定义变量，渲染 prompt 时注入
    ///   - labelStyle: 浮条显示样式，默认 `.icon`
    public init(
        id: String, name: String, icon: String, description: String?,
        systemPrompt: String?, userPrompt: String,
        providerId: String, modelId: String?, temperature: Double?,
        displayMode: DisplayMode, variables: [String: String],
        labelStyle: ToolLabelStyle = .icon
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.providerId = providerId
        self.modelId = modelId
        self.temperature = temperature
        self.displayMode = displayMode
        self.variables = variables
        self.labelStyle = labelStyle
    }

    // MARK: - Codable（自定义 decode 以兼容老版本 config.json）

    /// 与合成版保持一致，显式声明以便下面的 `init(from:)` 使用
    private enum CodingKeys: String, CodingKey {
        case id, name, icon, description, systemPrompt, userPrompt
        case providerId, modelId, temperature, displayMode, variables, labelStyle
    }

    /// 自定义 decode：`labelStyle` 旧配置里不存在时回退到 `.icon`
    ///
    /// 其余字段仍按合成 Codable 的语义处理（non-optional 字段缺失依然会抛错——
    /// 这与项目现有约定一致：schemaVersion 升级时才引入破坏性变更）。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decode(String.self, forKey: .icon)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        self.userPrompt = try container.decode(String.self, forKey: .userPrompt)
        self.providerId = try container.decode(String.self, forKey: .providerId)
        self.modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        self.displayMode = try container.decode(DisplayMode.self, forKey: .displayMode)
        self.variables = try container.decode([String: String].self, forKey: .variables)
        // 缺失或非法值时回退到 .icon，保持向后兼容
        self.labelStyle = try container.decodeIfPresent(ToolLabelStyle.self, forKey: .labelStyle) ?? .icon
    }
}

/// 结果展示模式（MVP v0.1 只实现 .window，另外两种预留给 v0.2+）
public enum DisplayMode: String, Sendable, Codable, CaseIterable {
    case window    // A - 独立浮窗
    case bubble    // B - v0.2
    case replace   // C - v0.2
}

/// 浮条（FloatingToolbar）上单个工具的显示样式
///
/// UI 层在渲染工具按钮时读取此字段决定绘制图标、名称或二者组合。
/// 仅影响浮条外观，不影响命令面板（命令面板本就是图标 + 名称列表）或执行逻辑。
public enum ToolLabelStyle: String, Sendable, Codable, CaseIterable {
    /// 只显示图标（emoji / SF Symbol）——MVP 默认风格，最紧凑
    case icon
    /// 只显示工具名称的短缩写（最多 4 个中文字或首个英文单词）
    case name
    /// 图标 + 短缩写并排显示
    case iconAndName
}
