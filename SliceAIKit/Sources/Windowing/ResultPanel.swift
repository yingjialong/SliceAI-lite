// SliceAIKit/Sources/Windowing/ResultPanel.swift
import AppKit
import SwiftUI
import SliceCore

/// 独立浮窗，Markdown 流式渲染 LLM 回复
///
/// 用法：
/// ```swift
/// let panel = ResultPanel()
/// panel.open(toolName: "翻译", model: "gpt-4o-mini")
/// panel.append("Hello")      // 每收到一段 delta 调一次
/// panel.finish()             // 流结束
/// // 出错时（带恢复动作）：
/// // panel.fail(with: .provider(.unauthorized),
/// //            onRetry: { ... }, onOpenSettings: { ... })
/// ```
/// 线程模型：整个类 `@MainActor`，所有公开 API 必须在主线程调用。
@MainActor
public final class ResultPanel {

    /// 承载内容的 NSPanel；首次 open 时懒创建，close 后复用（仅 orderOut）
    private var panel: NSPanel?
    /// 驱动 SwiftUI 视图的观察对象，open 时 reset、append/finish/fail 时更新
    private let viewModel = ResultViewModel()

    /// 无状态构造器
    public init() {}

    /// 展示结果窗口；若已存在则复用窗口并清空历史内容。
    /// - Parameters:
    ///   - toolName: 当前触发的工具名称（标题栏显示）
    ///   - model: 当前使用的模型（标题栏副文本显示）
    public func open(toolName: String, model: String) {
        if panel == nil {
            // 初始尺寸固定 560×400，用户可后续拖拽调整（styleMask 含 .resizable）
            let size = CGSize(width: 560, height: 400)
            // 默认停靠在主屏右上角内 40pt 处，避开刘海与菜单栏
            let origin: CGPoint
            if let screen = NSScreen.main?.visibleFrame {
                origin = CGPoint(
                    x: screen.maxX - size.width - 40,
                    y: screen.maxY - size.height - 40
                )
            } else {
                origin = CGPoint(x: 100, y: 100)
            }
            let panel = NSPanel(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered, defer: false
            )
            // floating 级别够用——结果窗希望在其他 App 之上，但不抢 statusBar
            panel.level = .floating
            panel.title = "SliceAI"
            // 关闭按钮走 orderOut，不释放引用，下次 open 继续复用
            panel.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: ResultContent(viewModel: viewModel))
            hosting.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hosting
            self.panel = panel
        }
        // 每次 open 都把 ViewModel 清空，避免上一次结果残留
        viewModel.reset(toolName: toolName, model: model)
        panel?.makeKeyAndOrderFront(nil)
    }

    /// 追加一段流式 delta 到结果区
    /// - Parameter delta: 本次 SSE 片段的纯文本内容
    public func append(_ delta: String) {
        viewModel.append(delta)
    }

    /// 标记流式输出正常结束（关闭闪烁光标）
    public func finish() {
        viewModel.finish()
    }

    /// 标记流式输出以错误结束；将错误的 userMessage 显示在结果区，并挂载可选恢复动作
    /// - Parameters:
    ///   - error: 统一错误类型；`userMessage` 展示给用户、`developerContext` 填入折叠详情
    ///   - onRetry: 可选的"重试"回调，nil 时不显示重试按钮
    ///   - onOpenSettings: 可选的"打开设置"回调，nil 时不显示该按钮
    ///
    /// 注：`developerContext` 已在 SliceError.swift 层做脱敏（不会携带 API Key/响应原文），
    /// 直接展示在 UI 上是安全的。
    public func fail(
        with error: SliceError,
        onRetry: (@MainActor () -> Void)? = nil,
        onOpenSettings: (@MainActor () -> Void)? = nil
    ) {
        viewModel.fail(
            message: error.userMessage,
            detail: error.developerContext,
            onRetry: onRetry,
            onOpenSettings: onOpenSettings
        )
    }

    /// 关闭窗口（仅隐藏，保留 NSPanel 实例以便下次快速复用）
    public func close() {
        panel?.orderOut(nil)
    }
}

/// 结果窗的 SwiftUI 状态源
///
/// 作为 `ObservableObject` 在主 actor 驱动 UI；`@Published` 字段由 `ResultPanel`
/// 公开方法改写，SwiftUI 视图通过 `@ObservedObject` 订阅变化。
///
/// `onRetry` / `onOpenSettings` 为恢复动作回调，**不**标注 `@Published`——它们不应
/// 触发 SwiftUI diff，只需要在主线程可读可写即可（类已 `@MainActor` 限定）。
@MainActor
final class ResultViewModel: ObservableObject {
    /// 当前工具名（标题栏主标题）
    @Published var toolName: String = ""
    /// 当前模型名（标题栏副文本）
    @Published var model: String = ""
    /// 已累积的 Markdown 文本；每次 append 都对现有字符串拼接
    @Published var text: String = ""
    /// 是否仍在流式接收中；控制闪烁光标与状态展示
    @Published var isStreaming: Bool = false
    /// 用户可见的错误信息；非 nil 时代替正文展示错误态
    @Published var errorMessage: String?
    /// 错误详情（开发者上下文）；供折叠区展示，已在 SliceError 层脱敏
    @Published var errorDetail: String?
    /// 错误详情折叠区是否展开；绑定到 DisclosureGroup
    @Published var showDetail: Bool = false

    /// "重试"动作回调；nil 表示当前错误不支持重试
    var onRetry: (@MainActor () -> Void)?
    /// "打开设置"动作回调；nil 表示当前错误不需要跳设置
    var onOpenSettings: (@MainActor () -> Void)?

    /// 重置视图状态为"新一次对话开始"
    func reset(toolName: String, model: String) {
        // 基本字段：标题 + 模型 + 清空上次文本、进入流式态
        self.toolName = toolName
        self.model = model
        self.text = ""
        self.isStreaming = true
        // 错误相关字段全部清空，避免上次错误残留
        self.errorMessage = nil
        self.errorDetail = nil
        self.showDetail = false
        // 恢复动作也要清掉，防止误触发上一次的 closure
        self.onRetry = nil
        self.onOpenSettings = nil
    }

    /// 拼接一段 delta 到现有文本
    func append(_ s: String) {
        text += s
    }

    /// 标记流结束
    func finish() {
        isStreaming = false
    }

    /// 标记流失败；停止闪烁并写入错误信息与恢复动作
    /// - Parameters:
    ///   - message: 面向用户的错误摘要（红色 banner 正文）
    ///   - detail: 开发者上下文（折叠详情），调用方需保证已脱敏
    ///   - onRetry: 可选重试回调
    ///   - onOpenSettings: 可选打开设置回调
    func fail(
        message: String,
        detail: String,
        onRetry: (@MainActor () -> Void)?,
        onOpenSettings: (@MainActor () -> Void)?
    ) {
        self.isStreaming = false
        self.errorMessage = message
        self.errorDetail = detail
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }
}

/// 结果窗内部视图：标题栏 + 正文（Markdown 或错误）+ 底部操作区
private struct ResultContent: View {
    @ObservedObject var viewModel: ResultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏：工具名 + 模型名，左对齐
            HStack {
                Text(viewModel.toolName)
                    .font(.system(size: 13, weight: .semibold))
                Text("· \(viewModel.model)")
                    .font(.system(size: 11))
                    .foregroundColor(PanelColors.textSecondary)
                Spacer()
            }
            .foregroundColor(PanelColors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            // 正文区域：错误优先、否则渲染流式 Markdown
            if let err = viewModel.errorMessage {
                errorStateView(message: err)
            } else {
                StreamingMarkdownView(text: viewModel.text, isStreaming: viewModel.isStreaming)
            }
            Divider()
            // 底部操作区：错误态展示 [复制错误详情]/[打开设置]/[重试]；正常态仅"复制"
            bottomBar()
                .padding(10)
        }
        .background(PanelColors.background)
        .foregroundColor(PanelColors.text)
    }

    /// 错误状态主视图：红色 banner + 折叠详情区
    /// - Parameter message: 用户可见的错误摘要（来自 `SliceError.userMessage`）
    @ViewBuilder
    private func errorStateView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 红色 banner：告警图标 + 简短错误描述
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .padding(.top, 2)
                Text(message)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // 详情折叠区（默认收起）：只在 errorDetail 非空时出现
            if let detail = viewModel.errorDetail, !detail.isEmpty {
                DisclosureGroup(
                    isExpanded: $viewModel.showDetail,
                    content: {
                        ScrollView {
                            // 等宽字体 + 可选中；便于用户复制诊断
                            Text(detail)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 120)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    },
                    label: { Text("错误详情").font(.caption) }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 底部操作栏：错误态 vs. 正常态两套按钮
    @ViewBuilder
    private func bottomBar() -> some View {
        HStack(spacing: 8) {
            if viewModel.errorMessage != nil {
                // 错误态：复制错误详情（拼 message + detail）
                Button("复制错误详情") {
                    let text = [viewModel.errorMessage, viewModel.errorDetail]
                        .compactMap { $0 }
                        .joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                // 可选：打开设置
                if let open = viewModel.onOpenSettings {
                    Button("打开设置") { open() }
                }
                Spacer()
                // 可选：重试（绑定为默认动作，Return 键触发）
                if let retry = viewModel.onRetry {
                    Button("重试") { retry() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                // 正常态：仅"复制"当前文本
                Button("复制") {
                    // 注意：clearContents + setString 会覆盖用户剪贴板；
                    // 与 SelectionCapture 的系统级 Cmd+C 在时间上错开（流结束后用户主动点击）
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.text, forType: .string)
                }
                Spacer()
            }
        }
    }
}
