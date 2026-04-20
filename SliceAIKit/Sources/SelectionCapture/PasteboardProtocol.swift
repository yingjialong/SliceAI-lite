import AppKit

/// NSPasteboard 的抽象接口，便于测试注入假实现
public protocol PasteboardProtocol: Sendable {
    /// 当前剪贴板变更计数，用于检测写入是否被其他应用覆盖
    var changeCount: Int { get }

    /// 读取指定类型的字符串；不存在返回 nil
    func string(forType type: NSPasteboard.PasteboardType) -> String?

    /// 清空剪贴板内容；返回新的 changeCount
    @discardableResult
    func clearContents() -> Int

    /// 写入字符串；返回是否成功
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool

    /// 读取全部 pasteboard item，用于完整备份恢复
    func pasteboardItems() -> [NSPasteboardItem]?

    /// 批量写入 pasteboard object，用于恢复备份
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

/// 系统 NSPasteboard 的默认适配
///
/// `NSPasteboard` 本身未声明 `Sendable`，但 `NSPasteboard.general` 是进程级单例，
/// 实际调用均为主线程安全的读写，故以 `@unchecked Sendable` 标注，遵循封装 Apple 单例时的常见做法
public struct SystemPasteboard: @unchecked Sendable, PasteboardProtocol {
    private let pb: NSPasteboard

    public init(_ pb: NSPasteboard = .general) {
        self.pb = pb
    }

    public var changeCount: Int { pb.changeCount }

    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        pb.string(forType: type)
    }

    @discardableResult
    public func clearContents() -> Int {
        pb.clearContents()
    }

    @discardableResult
    public func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        pb.setString(string, forType: type)
    }

    public func pasteboardItems() -> [NSPasteboardItem]? {
        pb.pasteboardItems
    }

    public func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        pb.writeObjects(objects)
    }
}
