// SliceAIApp/MenuBarController.swift
import AppKit
import DesignSystem
import SliceCore

/// 菜单栏（系统右上角状态栏）控制器。
///
/// 职责：
///   - 在系统状态栏展示一枚 SF Symbol 图标；
///   - 当没有配置任何 Provider 时，在图标右上角叠加一个紫色小红点，提示用户尚未完成设置；
///   - 提供"外观"子菜单（Auto / Light / Dark），驱动 ThemeManager 切换全局主题；
///   - 提供打开设置、退出应用的菜单项；
///   - 菜单动作通过 `AppDelegate` 弱引用回调，避免循环引用。
///
/// 线程模型：`@MainActor` 限定；`NSStatusItem` / `NSMenu` 必须在主线程构造与使用。
/// 生命周期：由 `AppDelegate` 创建一次并持有，直到应用退出。
@MainActor
final class MenuBarController: NSObject {

    /// 宿主 AppDelegate；用弱引用避免与 AppDelegate 之间形成循环
    weak var delegate: AppDelegate?

    /// 主题管理器；切换外观子菜单选项时直接调用 setMode
    private let themeManager: ThemeManager

    /// DI 组合根；用于读取 providers 数量判断是否显示红点
    private weak var container: AppContainer?

    /// 系统状态栏的挂载项；必须强引用，否则图标会消失
    private let statusItem: NSStatusItem

    /// 当前是否处于"未配置 provider"状态；变化时触发图标刷新
    private var isUnconfigured: Bool = false

    /// 构造并向系统状态栏注册菜单项
    /// - Parameters:
    ///   - container: 组合根，用于读取 providers 状态以决定是否显示红点
    ///   - delegate: AppDelegate，用于响应菜单动作
    init(container: AppContainer, delegate: AppDelegate) {
        self.container = container
        self.themeManager = container.themeManager
        self.delegate = delegate

        // squareLength 让图标区保持方形宽度，与系统原生应用一致
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.baseIcon()

        // NSObject 两阶段初始化：存储属性在 super.init 前完成，方法调用在之后
        super.init()

        // buildMenu 调用 self 的方法，必须在 super.init 之后
        let menu = buildMenu()
        // 将 self 设为 NSMenuDelegate，以便在菜单弹出时实时刷新外观勾选
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - 公共方法

    /// 刷新状态栏图标以反映当前 provider 配置状态
    ///
    /// 调用时机：Onboarding 完成、Settings 窗口关闭、添加/删除 Provider 后。
    /// 通过读取 configStore 快照判断 providers 是否为空，为空则叠加紫色小红点。
    func refreshConfigStateIndicator() {
        Task { @MainActor [weak self] in
            guard let self, let container = self.container else { return }
            let cfg = await container.configStore.current()
            let wasUnconfigured = self.isUnconfigured
            self.isUnconfigured = cfg.providers.isEmpty
            // 仅在状态真正变化时重新生成图标，避免闪烁
            if self.isUnconfigured != wasUnconfigured {
                self.statusItem.button?.image = self.isUnconfigured
                    ? Self.badgedIcon()
                    : Self.baseIcon()
            }
        }
    }

    // MARK: - 图标生成

    /// 生成基础图标（自定义合成）
    ///
    /// 视觉：中心 `character.cursor.ibeam`（文字光标）+ 右上角 / 左下角两颗
    /// 大小不一的 `sparkle`，像"魔法棒"风格但把魔法棒本体换成了 I-beam 光标。
    /// 寓意"划词 + 智能润色/重写"——这正是 SliceAI 的核心动作。
    ///
    /// 实现：20×20 bitmap 上分三次 `draw(in:)` 叠加 SF Symbol，最后 `isTemplate=true`
    /// 让菜单栏按系统深浅色自动反色。需要 macOS 13+ 提供 `sparkle` 单数符号，
    /// 项目约束 macOS 14，安全。
    private static func baseIcon() -> NSImage? {
        // 18×18 是 macOS 状态栏约定的图标尺寸
        let size = CGSize(width: 20, height: 20)
        let image = NSImage(size: size)

        image.lockFocus()
        // 1. 中心主体：I-beam 光标——用 .bold 加粗字符"A"和 I-beam 的竖线，
        //    避免在菜单栏小尺寸下笔画过细、视觉发虚
        drawSymbol(name: "character.cursor.ibeam", pointSize: 12,
                   weight: .black, center: CGPoint(x: 10, y: 9))
        // 2. 右上角较大 sparkle——weight .semibold 让星芒稍粗，
        //    与主体视觉重量一致（太细会被主图压没）
        drawSymbol(name: "sparkle", pointSize: 4,
                   weight: .semibold, center: CGPoint(x: 18, y: 6))
        // 3. 左下角较小 sparkle——辅助闪光，平衡构图
        drawSymbol(name: "sparkle", pointSize: 5,
                   weight: .bold, center: CGPoint(x: 2, y: 14))
        image.unlockFocus()

        // 作为 template 让菜单栏自动处理深浅色反色
        image.isTemplate = true
        return image
    }

    /// 在当前 lockFocus context 里按指定中心点渲染一个 SF Symbol
    ///
    /// 使用 `NSImage.SymbolConfiguration(pointSize:weight:)` 控制 symbol 字号；
    /// `withSymbolConfiguration` 返回配置后的 NSImage，其 size 即为视觉像素尺寸。
    /// 绘制时以 `center` 为中心，避免手动对齐误差。
    /// - Parameters:
    ///   - name: SF Symbol 名
    ///   - pointSize: symbol 字号（pt）
    ///   - weight: symbol 粗细
    ///   - center: 绘制中心点（NSImage 坐标系，左下原点）
    private static func drawSymbol(
        name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        center: CGPoint
    ) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let glyphSize = symbol.size
        let rect = CGRect(
            x: center.x - glyphSize.width / 2,
            y: center.y - glyphSize.height / 2,
            width: glyphSize.width,
            height: glyphSize.height
        )
        symbol.draw(in: rect)
    }

    /// 生成带紫色小红点的图标（右上角叠加 6pt 圆点）
    ///
    /// 实现方式：先在离屏 bitmap context 中绘制基础图标（I-beam 光标 + 两颗 sparkle），
    /// 再在右上角叠加一个实心圆（SliceAI 品牌紫色），最后合成为 NSImage。
    /// 注意：由于叠加了彩色圆点，合成图无法作为 template 使用（`isTemplate = false`），
    /// 菜单栏不会自动反色——这是既有行为，新的 baseIcon 不改变它。
    private static func badgedIcon() -> NSImage? {
        // 图标尺寸与系统状态栏约定一致
        let size = CGSize(width: 18, height: 18)
        // 红点直径与位置
        let dotDiameter: CGFloat = 6
        let dotOrigin = CGPoint(x: size.width - dotDiameter, y: size.height - dotDiameter)

        // 生成基础图标
        guard let base = baseIcon() else { return nil }

        // 在 bitmap 中合成图标 + 圆点
        let image = NSImage(size: size)
        image.lockFocus()

        // 先绘制基础图标（缩放以留出右上角红点空间）
        let iconRect = CGRect(x: 0, y: 0, width: size.width - dotDiameter / 2, height: size.height - dotDiameter / 2)
        base.draw(in: iconRect)

        // 叠加紫色圆点（SliceAI 品牌色 #7C5CBF 近似）
        let dotRect = CGRect(origin: dotOrigin, size: CGSize(width: dotDiameter, height: dotDiameter))
        NSColor(red: 0.49, green: 0.36, blue: 0.75, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - 菜单构建

    /// 构造完整菜单：SliceAI 标题 → Settings → 外观子菜单 → 分隔 → Quit
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 展示性标题，点击无动作
        menu.addItem(NSMenuItem(title: "SliceAI", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        // Settings…：Command+,（macOS 约定的设置快捷键）
        menu.addItem(
            NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
                .withTarget(self)
        )

        // 外观子菜单
        let appearanceItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        appearanceItem.submenu = buildAppearanceMenu()
        menu.addItem(appearanceItem)

        menu.addItem(.separator())

        // Quit：Command+Q；action 走 NSApplication.terminate 由系统处理退出
        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        return menu
    }

    /// 构造"外观"子菜单：Auto / Light / Dark 三选项
    ///
    /// 选中状态（.on/.off）在菜单打开时动态刷新，确保与 ThemeManager 当前 mode 一致。
    private func buildAppearanceMenu() -> NSMenu {
        let submenu = NSMenu(title: "外观")

        // Auto（跟随系统）
        let autoItem = NSMenuItem(title: "跟随系统", action: #selector(setAppearance(_:)), keyEquivalent: "")
        autoItem.tag = 0
        autoItem.target = self
        submenu.addItem(autoItem)

        // Light（浅色）
        let lightItem = NSMenuItem(title: "浅色", action: #selector(setAppearance(_:)), keyEquivalent: "")
        lightItem.tag = 1
        lightItem.target = self
        submenu.addItem(lightItem)

        // Dark（深色）
        let darkItem = NSMenuItem(title: "深色", action: #selector(setAppearance(_:)), keyEquivalent: "")
        darkItem.tag = 2
        darkItem.target = self
        submenu.addItem(darkItem)

        return submenu
    }

    // MARK: - 菜单代理 / 动作

    /// 菜单即将弹出时刷新外观子菜单的勾选状态
    ///
    /// 利用 NSMenuDelegate.menuWillOpen 避免每次 buildMenu 时都重新遍历，
    /// 同时保证用户在 Settings 内改变外观后菜单也能同步。
    private func syncAppearanceMenuState() {
        guard let submenu = statusItem.menu?.item(withTitle: "外观")?.submenu else { return }
        let current = themeManager.mode
        // tag: 0=auto, 1=light, 2=dark
        for item in submenu.items {
            switch item.tag {
            case 0: item.state = current == .auto  ? .on : .off
            case 1: item.state = current == .light ? .on : .off
            case 2: item.state = current == .dark  ? .on : .off
            default: break
            }
        }
    }

    /// 切换全局主题；由外观子菜单三个 NSMenuItem 共用此 action，通过 tag 区分
    /// - Parameter sender: 发出动作的 NSMenuItem（tag: 0=auto, 1=light, 2=dark）
    @objc private func setAppearance(_ sender: NSMenuItem) {
        let mode: AppearanceMode
        switch sender.tag {
        case 1:  mode = .light
        case 2:  mode = .dark
        default: mode = .auto
        }
        themeManager.setMode(mode)
        // 同步更新勾选状态，给用户即时反馈
        syncAppearanceMenuState()
    }

    /// 打开设置窗口；委托给 AppDelegate，避免在菜单控制器内直接持有窗口状态
    @objc private func openSettings() {
        delegate?.showSettings()
    }
}

// MARK: - NSMenu 代理：菜单弹出时刷新勾选

/// MenuBarController 实现 NSMenuDelegate 以在菜单弹出时同步外观选中状态
extension MenuBarController: NSMenuDelegate {

    /// 菜单即将显示：刷新外观子菜单的勾选状态以与 ThemeManager 当前 mode 保持同步
    func menuWillOpen(_ menu: NSMenu) {
        syncAppearanceMenuState()
    }
}

// MARK: - NSMenuItem 链式辅助

/// 便捷链式设置 `target` 的辅助扩展；只在本文件内使用
private extension NSMenuItem {

    /// 设置菜单项的 target 并返回自身，方便在 buildMenu 内链式调用
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
