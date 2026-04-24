import Foundation

/// 应用级统一错误，每类都有 userMessage（给用户看）与 developerContext（日志）
public enum SliceError: Error, Sendable, Equatable {
    case selection(SelectionError)
    case provider(ProviderError)
    case configuration(ConfigurationError)
    case permission(PermissionError)

    /// 面向最终用户的友好错误文案
    public var userMessage: String {
        switch self {
        case .selection(let e): return e.userMessage
        case .provider(let e): return e.userMessage
        case .configuration(let e): return e.userMessage
        case .permission(let e): return e.userMessage
        }
    }

    /// 用于日志打印的开发者上下文
    /// 对携带任意字符串 payload 的 case 做脱敏，防止 API Key / 响应体 / JSON 原文流入日志
    public var developerContext: String {
        switch self {
        case .selection(let e):
            switch e {
            case .axUnavailable: return "selection.axUnavailable"
            case .axEmpty: return "selection.axEmpty"
            case .clipboardTimeout: return "selection.clipboardTimeout"
            case .textTooLong(let n): return "selection.textTooLong(\(n))"
            }
        case .provider(let e):
            switch e {
            case .unauthorized: return "provider.unauthorized"
            case .rateLimited(let t):
                let s = t.flatMap { $0.isFinite ? String(Int(max(0, $0.rounded(.up)))) : nil } ?? "nil"
                return "provider.rateLimited(\(s))"
            case .serverError(let code): return "provider.serverError(\(code))"
            case .networkTimeout: return "provider.networkTimeout"
            case .invalidResponse: return "provider.invalidResponse(<redacted>)"
            case .sseParseError: return "provider.sseParseError(<redacted>)"
            }
        case .configuration(let e):
            switch e {
            case .fileNotFound: return "configuration.fileNotFound"
            case .schemaVersionTooNew(let v): return "configuration.schemaVersionTooNew(\(v))"
            case .invalidJSON: return "configuration.invalidJSON(<redacted>)"
            case .referencedProviderMissing(let id): return "configuration.referencedProviderMissing(\(id))"
            // String payload 含 tool/provider id，符合脱敏约定，不透传原始值到日志
            case .incompleteThinkingConfig: return "configuration.incompleteThinkingConfig(<redacted>)"
            }
        case .permission(let e):
            switch e {
            case .accessibilityDenied: return "permission.accessibilityDenied"
            case .inputMonitoringDenied: return "permission.inputMonitoringDenied"
            }
        }
    }
}

/// 选中文字捕获环节的错误
public enum SelectionError: Error, Sendable, Equatable {
    case axUnavailable
    case axEmpty
    case clipboardTimeout
    case textTooLong(Int)

    public var userMessage: String {
        switch self {
        case .axUnavailable: return "SliceAI 需要辅助功能权限才能读取你选中的文字。"
        case .axEmpty: return "无法读取当前选中的文字，请确认已选中文本。"
        case .clipboardTimeout: return "读取选中文字超时，请再试一次。"
        case .textTooLong(let n): return "选中的文字过长（\(n) 字符），请缩短选区。"
        }
    }
}

/// LLM 供应商调用环节的错误
public enum ProviderError: Error, Sendable, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case networkTimeout
    case invalidResponse(String)
    case sseParseError(String)

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "API Key 无效或未设置，请在设置中检查。"
        case .rateLimited(let t):
            if let t, t.isFinite, t > 0 {
                let secs = max(1, Int(t.rounded(.up)))
                return "请求过于频繁，请 \(secs) 秒后重试。"
            }
            return "请求过于频繁，请稍后重试。"
        case .serverError(let code):
            return "服务端返回错误（HTTP \(code)），请稍后重试或切换模型。"
        case .networkTimeout:
            return "网络请求超时，请检查连接。"
        case .invalidResponse:
            return "服务端响应异常，无法解析。"
        case .sseParseError:
            return "接收到的流式数据格式无法识别。"
        }
    }
}

/// 配置加载/校验环节的错误
public enum ConfigurationError: Error, Sendable, Equatable {
    case fileNotFound
    case schemaVersionTooNew(Int)
    case invalidJSON(String)
    case referencedProviderMissing(String)
    /// 工具配置不完整：byModel provider 选了 thinkingEnabled=true 但没填 thinkingModelId
    /// 关联值是脱敏的描述（包含 tool id / provider id，不含 secret）
    case incompleteThinkingConfig(String)

    public var userMessage: String {
        switch self {
        case .fileNotFound:
            return "找不到配置文件，将使用默认配置。"
        case .schemaVersionTooNew(let v):
            return "配置文件的 schemaVersion=\(v) 高于当前应用支持版本，请升级 SliceAI。"
        case .invalidJSON:
            return "配置文件 JSON 格式不正确，请参考 config.schema.json 校验。"
        case .referencedProviderMissing(let id):
            return "工具引用的供应商 \"\(id)\" 不存在。"
        case .incompleteThinkingConfig:
            return "工具未配置思考模式所需的 model id，请到设置中补全。"
        }
    }
}

/// 系统权限相关错误
public enum PermissionError: Error, Sendable, Equatable {
    case accessibilityDenied
    case inputMonitoringDenied

    public var userMessage: String {
        switch self {
        case .accessibilityDenied:
            return "辅助功能权限未授予，SliceAI 无法读取划词。"
        case .inputMonitoringDenied:
            return "输入监控权限未授予，快捷键可能无法工作。"
        }
    }
}
