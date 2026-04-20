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
/// // 出错时：panel.fail(with: .provider(.unauthorized))
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

    /// 标记流式输出以错误结束；将错误的 userMessage 显示在结果区
    /// - Parameter error: 统一错误类型，直接读取其 userMessage 做展示
    public func fail(with error: SliceError) {
        viewModel.fail(message: error.userMessage)
    }

    /// 关闭窗口（仅隐藏，保留 NSPanel 实例以便下次快速复用）
    public func close() {
        panel?.orderOut(nil)
    }
}

/// 结果窗的 SwiftUI 状态源
///
/// 作为 `ObservableObject` 在主 actor 驱动 UI；`@Published` 的四个字段由 `ResultPanel`
/// 公开方法改写，SwiftUI 视图通过 `@ObservedObject` 订阅变化。
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
    /// 错误信息；非 nil 时代替正文展示
    @Published var errorMessage: String?

    /// 重置视图状态为“新一次对话开始”
    func reset(toolName: String, model: String) {
        self.toolName = toolName
        self.model = model
        self.text = ""
        self.isStreaming = true
        self.errorMessage = nil
    }

    /// 拼接一段 delta 到现有文本
    func append(_ s: String) {
        text += s
    }

    /// 标记流结束
    func finish() {
        isStreaming = false
    }

    /// 标记流失败；停止闪烁并设置错误文本
    func fail(message: String) {
        isStreaming = false
        errorMessage = message
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
                Text(err)
                    .foregroundColor(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                StreamingMarkdownView(text: viewModel.text, isStreaming: viewModel.isStreaming)
            }
            Divider()
            // 底部操作区：目前只有“复制”按钮；未来可扩展“重新生成 / 反馈”等
            HStack(spacing: 8) {
                Button("复制") {
                    // 注意：clearContents + setString 会覆盖用户剪贴板；
                    // 与 SelectionCapture 的系统级 Cmd+C 在时间上错开（流结束后用户主动点击）
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.text, forType: .string)
                }
                Spacer()
            }
            .padding(10)
        }
        .background(PanelColors.background)
        .foregroundColor(PanelColors.text)
    }
}
