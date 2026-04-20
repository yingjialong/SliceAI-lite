import AppKit
import Carbon
import Foundation

/// 一组快捷键定义，可从字符串解析
public struct Hotkey: Sendable, Equatable, CustomStringConvertible {
    public let keyCode: UInt32
    public let modifiers: Modifiers

    /// 修饰键集合，基于 Carbon `cmdKey`/`optionKey` 等原始位掩码
    public struct Modifiers: OptionSet, Sendable, Equatable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: UInt32(cmdKey))
        public static let option  = Modifiers(rawValue: UInt32(optionKey))
        public static let shift   = Modifiers(rawValue: UInt32(shiftKey))
        public static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    /// 解析错误类型
    public enum ParseError: Error { case empty, unknownToken(String) }

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 从形如 "option+space" / "cmd+shift+k" 的字符串解析出 Hotkey
    /// - Parameter string: 用户配置字符串，大小写不敏感，用 `+` 连接各片段
    /// - Throws: 空字符串抛 `.empty`；未知 token 抛 `.unknownToken`
    public static func parse(_ string: String) throws -> Hotkey {
        // 统一转小写并按 + 拆分，顺便修剪空格，兼容用户输入中的多余空白
        let tokens = string.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { throw ParseError.empty }

        var mods: Modifiers = []
        var key: UInt32?

        // 逐 token 判断是否为修饰键或主键；主键命中 keyCodeMap 即写入 key
        for token in tokens {
            switch token {
            case "cmd", "command": mods.insert(.command)
            case "opt", "option", "alt": mods.insert(.option)
            case "shift": mods.insert(.shift)
            case "ctrl", "control": mods.insert(.control)
            default:
                if let mapped = Self.keyCodeMap[token] {
                    key = mapped
                } else {
                    throw ParseError.unknownToken(token)
                }
            }
        }
        // 只有修饰键、没有主键同样视为无效（空）
        guard let key else { throw ParseError.empty }
        return Hotkey(keyCode: key, modifiers: mods)
    }

    /// 标准化回字符串表示，便于显示和调试；顺序固定为 cmd/ctrl/option/shift/key
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option)  { parts.append("option") }
        if modifiers.contains(.shift)   { parts.append("shift") }
        parts.append(Self.nameForKeyCode[keyCode] ?? "key\(keyCode)")
        return parts.joined(separator: "+")
    }

    // MARK: - 常用键 映射（MVP 覆盖：space/return/tab/esc + A-Z + 0-9 + F1-F12 + 方向键）
    private static let keyCodeMap: [String: UInt32] = [
        "space": 49, "return": 36, "tab": 48, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
        "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
        "w": 13, "x": 7, "y": 16, "z": 6,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25, "0": 29,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]
    // keyCodeMap 中存在别名（如 escape/esc 同为 53），反向映射按名字字典序取最短/最先者，
    // 保证反向唯一且结果确定；`uniquingKeysWith` 在冲突时保留字典序较小的名字
    private static let nameForKeyCode: [UInt32: String] = Dictionary(
        keyCodeMap.map { ($0.value, $0.key) },
        uniquingKeysWith: { lhs, rhs in lhs < rhs ? lhs : rhs }
    )
}
