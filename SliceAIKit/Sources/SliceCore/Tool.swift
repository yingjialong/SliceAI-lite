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
    public init(
        id: String, name: String, icon: String, description: String?,
        systemPrompt: String?, userPrompt: String,
        providerId: String, modelId: String?, temperature: Double?,
        displayMode: DisplayMode, variables: [String: String]
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
    }
}

/// 结果展示模式（MVP v0.1 只实现 .window，另外两种预留给 v0.2+）
public enum DisplayMode: String, Sendable, Codable, CaseIterable {
    case window    // A - 独立浮窗
    case bubble    // B - v0.2
    case replace   // C - v0.2
}
