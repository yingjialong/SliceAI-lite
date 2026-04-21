import Foundation
import SliceCore

/// 组合 primary (AX) 与 fallback (Clipboard)，产出 SelectionPayload
///
/// 职责：按"AX 优先 → 剪贴板回退"顺序依次尝试读取选中文字，将任一成功的
/// `SelectionReadResult` 转成对外统一的 `SelectionPayload`（补上 timestamp）。
/// 主路径若抛错或返回 nil，都会自动降级到 fallback；两路均空时返回 nil。
public struct SelectionService: Sendable {

    private let primary: any SelectionSource
    private let fallback: any SelectionSource

    /// 构造 SelectionService
    /// - Parameters:
    ///   - primary: 主读取路径，通常注入 AXSelectionSource
    ///   - fallback: 备用读取路径，通常注入 ClipboardSelectionSource
    public init(primary: any SelectionSource, fallback: any SelectionSource) {
        self.primary = primary
        self.fallback = fallback
    }

    /// 读取当前选区；双路均失败返回 nil
    ///
    /// 实现说明（避免双重 Optional 陷阱）：
    /// `try? await source.readSelection()` 的返回类型是 `SelectionReadResult??`
    /// （外层来自 `try?`，内层来自协议本身的可选返回）。若直接写
    /// `if let r = try? await ...` 则只剥掉一层，留下的仍是 `SelectionReadResult?`，
    /// 此时即便 "成功但为空" 也会让 `if let` 成立，从而错误地跳过 fallback。
    /// 因此抽出 `tryCapture(from:)` 统一用 `do / try / if let` 把两层 Optional 都处理干净。
    public func capture() async throws -> SelectionPayload? {
        if let payload = await tryCapture(from: primary) {
            return payload
        }
        if let payload = await tryCapture(from: fallback) {
            return payload
        }
        return nil
    }

    /// 仅尝试 primary（通常是 AX）捕获，不走 fallback（通常是 Cmd+C）
    ///
    /// 设计用途：鼠标全局监听等"被动触发"路径，避免 Cmd+C 的副作用
    /// （剪贴板抖动 / 错误弹出浮条）。主动路径（命令面板 ⌥Space）仍应使用
    /// `capture()` 以获得更高的可达性（对不支持 AX 的应用也能读到文本）。
    ///
    /// 返回值与 `capture()` 一致；不抛错（primary 的错误已在 tryCapture 里被静默降级为 nil）。
    public func captureFromPrimaryOnly() async -> SelectionPayload? {
        return await tryCapture(from: primary)
    }

    /// 尝试从单个 source 读取并转换为 SelectionPayload；任何失败（抛错 / nil）都返回 nil
    ///
    /// 错误在此处被静默降级：对外层只关心"这条路径能不能拿到结果"，
    /// 而不是具体的失败原因（AX 没权限、CGEvent 失败、超时等均等价于"这条路径没拿到"）。
    private func tryCapture(from source: any SelectionSource) async -> SelectionPayload? {
        do {
            if let result = try await source.readSelection() {
                return SelectionPayload(from: result)
            }
        } catch {
            // 单路失败允许静默降级，交给调用方尝试下一条路径
        }
        return nil
    }
}

private extension SelectionPayload {
    /// 把 SelectionCapture 层的 SelectionReadResult 补齐 timestamp 后转成对外的 SelectionPayload
    init(from r: SelectionReadResult) {
        self.init(
            text: r.text,
            appBundleID: r.appBundleID,
            appName: r.appName,
            url: r.url,
            screenPoint: r.screenPoint,
            source: r.source,
            timestamp: Date()
        )
    }
}
