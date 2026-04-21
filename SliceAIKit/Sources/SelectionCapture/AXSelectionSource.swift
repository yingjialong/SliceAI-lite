import AppKit
import ApplicationServices
import SliceCore

/// 基于 Accessibility API 读取当前 focused element 的选中文字
///
/// 通过系统级 `AXUIElementCreateSystemWide()` 定位当前焦点元素，再读取其
/// `kAXSelectedTextAttribute`。该路径不依赖剪贴板、不会触发 ⌘C，是优先使用的主读取路径；
/// 但需要 App 获得 Accessibility 权限，且只对提供 AX 的 App（绝大多数原生控件）有效。
public struct AXSelectionSource: SelectionSource {

    /// 默认构造器；本类型无存储属性，创建成本可以忽略
    public init() {}

    /// 读取当前选中文字；拿不到返回 nil
    ///
    /// 系统级 AX 调用必须在主线程，因此通过 `await MainActor.run` 跳转到主 actor 后执行。
    public func readSelection() async throws -> SelectionReadResult? {
        // 系统级 AX 调用必须在主线程
        await MainActor.run { self.readOnMain() }
    }

    /// 在主线程上同步执行 AX 读取；拆出来以隔离非 Sendable 的 CF 类型
    @MainActor
    private func readOnMain() -> SelectionReadResult? {
        let systemWide = AXUIElementCreateSystemWide()

        // 拿到 focused UI element
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        )
        guard err == .success, let focused = focused else { return nil }
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement

        // 读取 focused element 的选中文本
        var selected: CFTypeRef?
        let selErr = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected
        )
        // 去除首尾空白后判空：防止部分应用在 focused 输入框为空时仍返回单个空格 / 制表符 /
        // 换行，导致被误判为"有选中文字"并触发浮条。
        guard selErr == .success, let text = selected as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // 当前前台 app；缺失时仍返回可用结果，避免丢弃成功的读取
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return SelectionReadResult(
                text: text,
                appBundleID: "",
                appName: "",
                url: nil,
                screenPoint: NSEvent.mouseLocation,
                source: .accessibility
            )
        }
        // 尝试读取浏览器 URL（用 AX 只对部分浏览器有效；Safari / Chromium 家族支持）
        let url = readURLIfBrowser(appBundleID: frontApp.bundleIdentifier ?? "")

        return SelectionReadResult(
            text: text,
            appBundleID: frontApp.bundleIdentifier ?? "",
            appName: frontApp.localizedName ?? "",
            url: url,
            screenPoint: NSEvent.mouseLocation,     // 屏幕坐标（左下原点）
            source: .accessibility
        )
    }

    /// 对浏览器尝试读取当前 tab URL。失败返回 nil
    ///
    /// MVP 阶段仅覆盖 Safari 与 Chromium 家族（Chrome / Edge / Brave / Arc），
    /// 通过读取 focused window 的 `AXDocument` 字段间接拿到当前 URL。
    @MainActor
    private func readURLIfBrowser(appBundleID: String) -> URL? {
        // 最简版本：只支持 Safari & Chromium 家族。MVP 阶段不激进
        guard appBundleID == "com.apple.Safari"
           || appBundleID.hasPrefix("com.google.Chrome")
           || appBundleID.hasPrefix("com.microsoft.Edge")
           || appBundleID.hasPrefix("com.brave.Browser")
           || appBundleID.hasPrefix("company.thebrowser.Browser") else { return nil }

        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let app = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &focusedWindow
        ) == .success, let focusedWindow else { return nil }
        // swiftlint:disable:next force_cast
        let window = focusedWindow as! AXUIElement
        var urlValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXDocument" as CFString, &urlValue) == .success,
           let s = urlValue as? String {
            return URL(string: s)
        }
        return nil
    }
}
