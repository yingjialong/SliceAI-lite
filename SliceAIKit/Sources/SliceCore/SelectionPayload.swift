import CoreGraphics
import Foundation

/// 划词事件的载荷，在 SelectionCapture 与 Windowing / ToolExecutor 之间传递
public struct SelectionPayload: Sendable, Equatable, Codable {
    public let text: String
    public let appBundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint
    public let source: Source
    public let timestamp: Date

    public init(
        text: String, appBundleID: String, appName: String,
        url: URL?, screenPoint: CGPoint, source: Source, timestamp: Date
    ) {
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.url = url
        self.screenPoint = screenPoint
        self.source = source
        self.timestamp = timestamp
    }

    /// 选中文字的来源，用于日志与诊断
    public enum Source: String, Sendable, Codable {
        case accessibility       // 通过 AX API 直接读取
        case clipboardFallback   // 通过模拟 Cmd+C + 剪贴板备份恢复获取
    }
}
