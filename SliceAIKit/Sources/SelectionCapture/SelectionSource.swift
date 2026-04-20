import CoreGraphics
import Foundation
import SliceCore

/// 读取一次选中文字的抽象来源
public protocol SelectionSource: Sendable {
    /// 读取当前选中文字；拿不到返回 nil
    func readSelection() async throws -> SelectionReadResult?
}

/// 读取结果，包含 text 与来源的应用信息
public struct SelectionReadResult: Sendable, Equatable {
    public let text: String
    public let appBundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint
    public let source: SelectionPayload.Source

    public init(
        text: String,
        appBundleID: String,
        appName: String,
        url: URL?,
        screenPoint: CGPoint,
        source: SelectionPayload.Source
    ) {
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.url = url
        self.screenPoint = screenPoint
        self.source = source
    }
}
