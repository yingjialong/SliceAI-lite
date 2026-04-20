import Foundation

/// 一个增量的 Server-Sent Events 解码器
/// 输入可来自 URLSession.AsyncBytes.lines（已按行拆分）或字节流（内部自行拆行）
/// 核心约定：
///   - 每个 SSE 事件以空行分隔（\n\n 或 \r\n\r\n）
///   - `data:` 字段的值在同一事件内可多行，使用 "\n" 连接
///   - `data: [DONE]` 作为特殊的终止标记，映射为 `.done`
///   - 以冒号开头的行属于注释/心跳，忽略
///   - 其它字段（event/id/retry）在 MVP 中忽略
public struct SSEDecoder {
    /// 解码产出的事件类型
    public enum Event: Equatable, Sendable {
        /// 一个完整事件的 data 负载（多行 data 用 "\n" 连接）
        case data(String)
        /// OpenAI 兼容协议中的 [DONE] 终止标记
        case done
    }

    /// 尚未形成完整行的缓冲区（可能因为分片未到 \n 结尾）
    private var buffer = ""
    /// 当前事件累积的 data 行（等待遇到空行时一起发出）
    private var eventDataLines: [String] = []

    /// 构造默认解码器（无状态初始值）
    public init() {}

    /// 追加输入数据并返回本次新产出的完整事件列表
    /// - Parameter chunk: 新到达的字符串片段（可以是任意切片，不要求对齐到行/事件边界）
    /// - Returns: 本次调用形成的完整事件；未形成完整事件的数据会继续缓存
    public mutating func feed(_ chunk: String) -> [Event] {
        // 将新分片并入缓冲区，保留跨次调用未闭合的数据
        buffer += chunk
        var events: [Event] = []
        print("[SSEDecoder] 收到 chunk 长度=\(chunk.count), 当前 buffer 长度=\(buffer.count)")

        // 按 \n 逐行消费缓冲区，直至没有完整行为止
        while let newlineRange = buffer.range(of: "\n") {
            // 提取一行（不含换行符本身），随后将其从缓冲区移除
            let rawLine = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(..<newlineRange.upperBound)

            // 规范化：去除可能存在的行尾 \r，兼容 CRLF 源
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

            if line.isEmpty {
                // 空行表示一个事件边界：若已经积累了 data 行则发出一个事件
                if !eventDataLines.isEmpty {
                    let joined = eventDataLines.joined(separator: "\n")
                    eventDataLines.removeAll(keepingCapacity: true)
                    if joined == "[DONE]" {
                        print("[SSEDecoder] 发出 .done 事件")
                        events.append(.done)
                    } else {
                        print("[SSEDecoder] 发出 .data 事件, payload 长度=\(joined.count)")
                        events.append(.data(joined))
                    }
                }
                continue
            }

            // 以冒号开头的行是注释/心跳（例如 `: keep-alive`），按规范忽略
            if line.hasPrefix(":") { continue }

            // 规范字段行形如 `field: value`，按第一个冒号切分；冒号后有一个可选空格需要吃掉
            if let colonIdx = line.firstIndex(of: ":") {
                let field = String(line[..<colonIdx])
                var value = String(line[line.index(after: colonIdx)...])
                if value.hasPrefix(" ") { value.removeFirst() }
                if field == "data" {
                    eventDataLines.append(value)
                }
                // 其它字段（event/id/retry）在 MVP 中忽略
            }
            // 没有冒号的行按 SSE 规范可视作字段名（value 为空），对接 OpenAI 兼容协议用不到，忽略
        }

        return events
    }
}
