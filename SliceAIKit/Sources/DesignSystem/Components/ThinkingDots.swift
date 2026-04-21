import SwiftUI

/// 三个脉动小点 + 文案，指示 LLM 推理中状态
///
/// 动画：每个点 1.4s 循环脉动，相邻点依次延迟 0.47s，合成"波浪"视觉效果。
/// 实现：使用 `Task { @MainActor in ... }` + `Task.sleep` 驱动动画帧，
/// 避免 Timer 在 Swift 6 严格并发下的隔离违规。Task 在 `onDisappear` 时取消，不泄漏。
///
/// 使用方式：
/// ```swift
/// if viewModel.isThinking {
///     ThinkingDots()
/// }
/// ```
public struct ThinkingDots: View {
    /// 提示文案，默认"正在思考…"
    let label: String

    /// 当前激活点的索引（0/1/2），驱动三点的 opacity 和 scale
    @State private var phase: Int = 0

    /// 动画 Task 引用，用于 onDisappear 时取消，避免资源泄漏
    @State private var animationTask: Task<Void, Never>?

    /// 初始化思考指示器
    /// - Parameter label: 提示文案，默认"正在思考…"
    public init(label: String = "正在思考…") {
        self.label = label
    }

    public var body: some View {
        HStack(spacing: SliceSpacing.base) {
            // MARK: 三点脉动动画区域
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(SliceColor.accent)
                        .frame(width: 5, height: 5)
                        .opacity(opacity(for: i))
                        .scaleEffect(scale(for: i))
                        // 每个点的 opacity/scale 变化都带独立的 easeInOut 过渡
                        .animation(.easeInOut(duration: 0.35), value: phase)
                }
            }

            // MARK: 文案
            Text(label)
                .font(SliceFont.body)
                .foregroundColor(SliceColor.textSecondary)
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            // 视图消失时取消 Task，防止在后台继续触发状态更新
            animationTask?.cancel()
            animationTask = nil
        }
    }

    // MARK: - 私有计算属性

    /// 返回第 index 个点的不透明度
    /// - active 点：1.0，其余点：0.3
    private func opacity(for index: Int) -> Double {
        phase == index ? 1.0 : 0.3
    }

    /// 返回第 index 个点的缩放比例
    /// - active 点：1.1（微微放大），其余点：0.8
    private func scale(for index: Int) -> Double {
        phase == index ? 1.1 : 0.8
    }

    // MARK: - 动画驱动

    /// 启动脉动动画循环
    ///
    /// 使用 `Task { @MainActor in ... }` + `Task.sleep(nanoseconds:)` 在主 actor 上
    /// 驱动 phase 切换，规避 Swift 6 严格并发下 `Timer` 回调的隔离问题（Timer 闭包
    /// 非隔离，`withAnimation` 需主线程，若直接用 Timer 会产生并发警告）。
    /// 每 470ms 切一次，3 点 × 470ms ≈ 1.4s 完成一个完整脉动循环。
    private func startAnimation() {
        // 避免重复启动（onAppear 在某些场景可能多次触发）
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            // 循环直到 Task 被取消
            while !Task.isCancelled {
                // 等待 470ms（纳秒精度）
                try? await Task.sleep(nanoseconds: 470_000_000)
                // Task 被取消后 sleep 可能提前返回，此处再次检查
                guard !Task.isCancelled else { break }
                // Circle 上已有 .animation(.easeInOut(duration: 0.35), value: phase) 修饰符
                // 声明式 modifier 会自动处理动画，无需命令式 withAnimation 包裹
                phase = (phase + 1) % 3
            }
        }
    }
}
