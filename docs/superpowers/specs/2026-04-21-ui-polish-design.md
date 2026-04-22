# SliceAI UI 彻底美化方案

- **日期**：2026-04-21
- **作者**：通过 brainstorming 与 Claude 共同产出
- **状态**：Design Freeze · 待用户 review 后进入 writing-plans
- **范围**：SliceAI 所有 UI 层（悬浮 HUD / 设置窗口 / Onboarding / 菜单栏）的视觉美化与结构重构
- **前置**：不改动领域层（SliceCore）、不改动数据流、不新增业务能力；只替换视觉实现与引入明暗双主题

---

## 1. 概述

### 1.1 动机

目前 UI 在功能上可用但视觉上不统一：

- 设置界面走 SwiftUI 默认 Form，明显的"默认 SwiftUI 味"，与悬浮 HUD 的深色暗调割裂
- 悬浮工具栏 / 结果面板已有 `PanelStyle.swift` 做了基础设计（圆角 10 / 深灰背景 / hover），但无 Material 毛玻璃、硬编码颜色、缺乏中心化 design tokens
- 没有主题切换能力，无法适配用户系统偏好
- 错误态、加载态、Markdown 渲染都偏朴素
- Onboarding 缺进度指示、Hero 图标，文案层级平

### 1.2 目标

1. 建立统一的设计语言（Apple 原生 + 品牌紫强调色），产品识别性和 macOS 原生感并存
2. 支持 Light / Dark / Auto 三种主题，亮色贴 Apple 原生审美、暗色接近 Raycast/Linear 的专业 HUD 风
3. 引入 `DesignSystem` 模块，集中 colors / typography / spacing / radius / shadow / animation / 通用 components
4. 所有 UI 模块（Windowing / SettingsUI / Permissions）迁移到 DesignSystem 的 token + component
5. 不破坏现有架构（Composition Root 不变、protocol 不变、SliceCore 零 UI 依赖不变）
6. 不破坏现有测试、不降低覆盖率

### 1.3 Non-goals（明确不做）

- ❌ Markdown 代码块**语法高亮**（需引入 Splash / Highlightr，超出 UI polish 范畴）
- ❌ 多语言（i18n）扩展（保留现有中英文硬编码，不在此轮重构）
- ❌ 自定义背景图 / 壁纸 / 主题色（仅品牌紫，用户不可改）
- ❌ 动画库引入（全部用 SwiftUI 原生 `withAnimation` + 自定义 transition）
- ❌ 图标素材重绘（仍用 SF Symbols + emoji）
- ❌ 浅色/深色以外的对比度模式（高对比度、色盲模式等辅助功能延后）
- ❌ 响应式缩放（各窗口尺寸固定、字号不随系统缩放调整；保留系统辅助功能 Dynamic Type 的默认兼容即可）
- ❌ 拖动位置持久化（工具栏拖动仅本次生效，下次划词重新按选区定位）

### 1.4 成功标准

1. 所有 UI 模块编译通过，`swift test` 全绿，`swiftlint lint --strict` 零警告
2. 主题切换 Light / Dark / Auto 可正常工作；System 切换 Dark Mode 时 Auto 模式 100ms 内跟进
3. DesignSystem 的 token 在所有 UI 模块生效，旧的硬编码颜色 / 间距 / 圆角全部清除
4. 视觉验收清单（见 §12）全部手动通过
5. 性能：悬浮工具栏出现 ≤ 150ms（与当前持平）；结果面板首字到达前的加载动画流畅（60fps）
6. SliceCore 零 UI 依赖不变；Package.swift 只新增 DesignSystem，不改动其他依赖图

---

## 2. 设计原则

### 2.1 语言基调

| 维度 | 取向 |
|---|---|
| 主风格 | Apple 原生 + 品牌紫强调色（方案 B + 方案 2 的组合） |
| 色温 | 中性（暗色偏深冷灰 `#1C1C20`；亮色偏暖白 `#FAFAFC`） |
| 形 | 小圆角、硬边、精工。外框 8pt、按钮 5pt、卡片 8pt 为主要档位 |
| 材质 | 毛玻璃为主（NSVisualEffectView.hudWindow / sidebar / underWindowBackground）|
| 强调色 | 品牌紫：亮色 `#7C3AED`（深紫沉稳），暗色 `#A78BFA`（柔和发光） |
| 字体 | SF Pro Text 默认；代码用 SF Mono；禁止引入外部字体 |
| 字距 | 标题 -0.01em、正文 -0.005em、小字 0（原生风格收紧） |
| 图标 | SF Symbols 优先，emoji 作为 fallback |
| 动画 | 克制。0.15-0.25s ease-out 为主，禁用弹簧夸张动画 |
| 阴影 | 双层（大阴影 24pt blur / 接触阴影 2-4pt blur），avoid 贴纸感 |

### 2.2 视觉原则（决策依据）

- **简单优先**：每个屏幕只有一个主操作，次级操作降级到 hover 或菜单
- **精致在细节**：0.5pt 细线、低饱和阴影、微位移 hover、2-3% 的 opacity 差异
- **克制的强调**：紫色仅用于"主操作 / 选中态 / 品牌标记"，不泛滥为装饰
- **跟手的反馈**：hover 0.15s、按压 scale(0.94)、出现/消失 0.18s，物理感而非动画秀
- **信息密度适中**：侧栏 180pt 宽、正文 13.5pt、行高 1.62，平衡紧凑与舒适

---

## 3. Design Tokens

所有 token 集中在 `DesignSystem` 模块，以 SwiftUI 扩展 + enum 形式暴露。

### 3.1 Color（颜色）

采用 **Asset Catalog 的 "Any / Dark" 变体**，让 SwiftUI `Color("asset")` 自动根据当前 `colorScheme` 切换。所有 Color 不硬编码 RGB。

**语义色（Semantic Colors）**：

```
// 背景层（3 层堆叠）
SliceColor.background          // 窗口底色   L: #FAFAFC  D: #0F0F12
SliceColor.surface             // 卡片/面板   L: #FFFFFF  D: #1C1C20
SliceColor.surfaceElevated     // 浮层/HUD   L: rgba(250,250,252,0.86)  D: rgba(28,28,32,0.86)

// 分隔 / 边框
SliceColor.divider             // 0.5pt 细线  L: rgba(0,0,0,0.08)  D: rgba(255,255,255,0.08)
SliceColor.border              // 外框描边   L: rgba(0,0,0,0.10)  D: rgba(255,255,255,0.09)

// 文本层级（4 级）
SliceColor.textPrimary         // 主文本     L: #1D1D1F  D: rgba(255,255,255,0.92)
SliceColor.textSecondary       // 次文本     L: rgba(0,0,0,0.60)  D: rgba(255,255,255,0.60)
SliceColor.textTertiary        // 辅助文本   L: rgba(0,0,0,0.45)  D: rgba(255,255,255,0.45)
SliceColor.textDisabled        // 禁用      L: rgba(0,0,0,0.30)  D: rgba(255,255,255,0.30)

// 强调（品牌紫）
SliceColor.accent              // 主强调色   L: #7C3AED  D: #A78BFA
SliceColor.accentFillLight     // 浅填充    L: rgba(124,58,237,0.12)  D: rgba(167,139,250,0.18)
SliceColor.accentFillStrong    // 深填充    L: rgba(124,58,237,0.22)  D: rgba(167,139,250,0.28)
SliceColor.accentText          // 紫色文本   L: #6D28D9  D: #C4B5FD

// 状态色
SliceColor.error               // 错误     L: #DC2626  D: #F87171
SliceColor.errorFill           //           L: rgba(220,38,38,0.06)  D: rgba(248,113,113,0.10)
SliceColor.errorBorder         //           L: rgba(220,38,38,0.20)  D: rgba(248,113,113,0.28)
SliceColor.success             // 成功     L: #0D7D2E  D: #4ADE80
SliceColor.warning             // 警告     L: #8A5C00  D: #FBBF24

// 交互反馈
SliceColor.hoverFill           // 通用 hover 浅色 L: rgba(0,0,0,0.05) D: rgba(255,255,255,0.07)
SliceColor.pressedFill         // 通用按压深色    L: rgba(0,0,0,0.10) D: rgba(255,255,255,0.12)
```

### 3.2 Typography（字体）

```
enum SliceFont {
    static let displayLarge    = Font.system(size: 22, weight: .bold, design: .default)    // Onboarding 主标题
    static let title           = Font.system(size: 17, weight: .bold, design: .default)    // 设置页标题
    static let headline        = Font.system(size: 15, weight: .semibold, design: .default)// 命令面板搜索框
    static let body            = Font.system(size: 13.5, weight: .regular, design: .default) // 正文
    static let bodyEmphasis    = Font.system(size: 13.5, weight: .semibold, design: .default)
    static let subheadline     = Font.system(size: 13, weight: .regular, design: .default) // 设置项 label
    static let callout         = Font.system(size: 12.5, weight: .regular, design: .default) // 描述、详情
    static let caption         = Font.system(size: 11.5, weight: .regular, design: .default) // 辅助
    static let captionEmphasis = Font.system(size: 11, weight: .semibold, design: .default)  // 小 section 标题
    static let overline        = Font.system(size: 10.5, weight: .semibold, design: .default) // uppercase section label
    static let micro           = Font.system(size: 10, weight: .regular, design: .default)    // 键盘提示
    static let mono            = Font.system(size: 12, design: .monospaced)                  // 代码、详情
    static let monoSmall       = Font.system(size: 11.5, design: .monospaced)                // error 详情
}
```

kerning：`displayLarge -0.02em`、`title -0.01em`、`body/bodyEmphasis -0.005em`、其余 0。
行高：正文 `lineSpacing = 5.5`（对应约 1.62 行高）、其余 SwiftUI 默认。

### 3.3 Spacing（间距）

```
enum SliceSpacing {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let base: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 16
    static let section: CGFloat = 20
    static let group: CGFloat = 24
    static let page: CGFloat = 32
}
```

### 3.4 Radius（圆角）

```
enum SliceRadius {
    static let tight: CGFloat = 4     // kbd / chip
    static let button: CGFloat = 5    // 图标按钮、pill 按钮
    static let control: CGFloat = 6   // 输入框、选择器、代码块
    static let card: CGFloat = 8      // 面板、卡片、工具栏外框
    static let sheet: CGFloat = 10    // 命令面板、设置窗口
    static let hero: CGFloat = 22     // Onboarding Hero 图标
}
```

### 3.5 Shadow（阴影）

```
enum SliceShadow {
    static let subtle   = (color: black.opacity(0.08), radius: 2,  x: 0, y: 1)   // 按钮按压态
    static let panel    = (color: black.opacity(0.22), radius: 24, x: 0, y: 20)  // 结果面板主阴影
    static let panelContact = (color: black.opacity(0.10), radius: 4, x: 0, y: 2) // 接触阴影
    static let hud      = (color: black.opacity(0.18), radius: 24, x: 0, y: 8)   // 悬浮工具栏
    static let hudContact = (color: black.opacity(0.08), radius: 2, x: 0, y: 2)
    static let hero     = (color: accent.opacity(0.35), radius: 32, x: 0, y: 12) // Onboarding Hero 图标
}
```

每个阴影叠加主阴影 + 接触阴影两层。

### 3.6 Animation（动画）

```
enum SliceAnimation {
    static let quick      = Animation.easeOut(duration: 0.12)    // hover
    static let standard   = Animation.easeOut(duration: 0.18)    // 出现 / 消失
    static let deliberate = Animation.easeInOut(duration: 0.25)  // 主题切换
    static let press      = Animation.easeOut(duration: 0.08)    // 按压
    static let progress   = Animation.linear(duration: 1.4).repeatForever(autoreverses: false)
}

enum SliceTransition {
    // 面板/窗口 出现：opacity 0→1 + scale 0.96→1
    static var scaleFadeIn: AnyTransition {
        .scale(scale: 0.96).combined(with: .opacity).animation(SliceAnimation.standard)
    }
    // 工具栏 出现：从选区方向 4pt 位移 + opacity
    static func slideFadeIn(from edge: Edge) -> AnyTransition {
        .move(edge: edge).combined(with: .opacity).animation(SliceAnimation.standard)
    }
}
```

### 3.7 Material（毛玻璃）

```
enum SliceMaterial {
    // macOS 原生 NSVisualEffectView.Material 对应
    static let hud      = NSVisualEffectView.Material.hudWindow         // 悬浮工具栏 / 结果面板
    static let sidebar  = NSVisualEffectView.Material.sidebar           // 设置侧栏
    static let popover  = NSVisualEffectView.Material.popover           // 命令面板
    static let window   = NSVisualEffectView.Material.windowBackground  // 设置窗口主区
}
```

通过自定义 `NSViewRepresentable` 包装 `NSVisualEffectView`，供 SwiftUI 用 `.background(SliceMaterial.hud)` 调用。

---

## 4. 主题系统（Light / Dark / Auto）

### 4.1 数据模型

```
enum AppearanceMode: String, Codable, CaseIterable {
    case auto    // 跟随系统
    case light
    case dark
}
```

存储：`Configuration.appearance` 字段（`config.json` 新增），默认 `.auto`。

### 4.2 实现方式

- 新建 `@Observable class ThemeManager`（Swift 5.9 Observation）
- `AppContainer` 初始化 ThemeManager 并通过 `.environment(themeManager)` 注入根视图
- `ThemeManager` 监听 `Configuration.appearance` 变化 + `NSApp.effectiveAppearance`（当 auto 时）
- 为每个需要主题的 NSWindow/NSPanel 设置 `appearance = NSAppearance(named: .aqua / .darkAqua)`
- SwiftUI 视图通过 `@Environment(\.colorScheme)` 响应；Color Asset 自动切换

### 4.3 切换入口

| 入口 | 位置 | 行为 |
|---|---|---|
| 设置侧栏 "外观" 页 | NavigationSplitView 第 1 项 | 三选一 Picker：Auto / Light / Dark |
| 菜单栏下拉 | 状态栏图标点开 | 子菜单 "外观 → Auto / Light / Dark" |

切换动画：整个窗口 `.transition(.opacity.animation(SliceAnimation.deliberate))`，NSWindow 间 crossfade 约 0.25s。

### 4.4 向后兼容

- 现有 `config.json` 无 `appearance` 字段 → 默认 `.auto`
- `config.schema.json` 需同步新增 `appearance` 字段（string enum）

---

## 5. 模块详细设计

### 5.1 悬浮工具栏（FloatingToolbarPanel）

**形态**：

- 外框圆角 8pt / 按钮圆角 5pt / 按钮尺寸 30×30pt
- 内边距 4pt，按钮间 2pt
- 背景：`SliceMaterial.hud`，0.5pt 描边 `SliceColor.border`
- 阴影：`SliceShadow.hud` + `SliceShadow.hudContact` 双层

**拖拽把手**：

- 最左侧 14×28pt 把手区 + 1pt 分隔竖线（16pt 高）
- 把手视觉：2×3 共 6 个小圆点（自绘 Canvas，直径 1.8pt，间距 4pt）
  - 亮色：点色 `rgba(0,0,0,0.42)`
  - 暗色：点色 `rgba(255,255,255,0.55)`
- 静置：无底色 / 默认游标
- Hover：底色 `SliceColor.hoverFill` + `NSCursor.openHand`（通过 `.onHover { hovering in ... }` + `NSCursor.push/pop`）
- 拖拽中：底色 `SliceColor.accentFillLight` + 点变 `SliceColor.accent` + `NSCursor.closedHand`
- 拖拽触发 `NSWindow.performDrag(with:)`（NSPanel 支持），整个面板平移
- 拖拽期间暂停 `autoHideTimer`（5s 消失计时器），释放后重启

**按钮交互**：

- 静置：图标 `SliceColor.textPrimary`，背景透明
- Hover：背景 `SliceColor.accentFillLight`、图标色 `SliceColor.accentText`、`translateY(-1)`
- Pressed：`scaleEffect(0.94)`，0.08s ease-out
- 点击后：toolbar 立即 dismiss（动画 `SliceAnimation.standard` 反向），触发工具执行

**出现/消失动画**：

- 出现：从选区方向 4pt 位移 + opacity 0→1，`SliceAnimation.standard`
- ESC / 外部点击：逆向

**位置持久化**：不做。每次划词重新按选区定位。

### 5.2 结果面板（ResultPanel）

**整体**：

- 480×auto（高度自适应，最大 520pt，超出内部滚动）
- 圆角 8pt / 毛玻璃 `SliceMaterial.hud` / 0.5pt 描边 / 阴影 `SliceShadow.panel + panelContact`

**头部（Header）**：

- 10pt 顶 / 12pt 左右 / 8pt 底
- 左：
  - Pin 状态下多一个 5pt 紫色小圆点
  - 工具名（`SliceFont.bodyEmphasis`，`SliceColor.textPrimary`）
  - 模型 chip（`SliceFont.micro`，2pt 上下 / 7pt 左右 padding，`SliceColor.surface` 变体底 + `SliceColor.textSecondary` 字；保持中性色不抢紫色重点）
- 右：4 个图标按钮（复制 / 重新生成 / pin / 关闭），22×22pt，间距 4pt
  - Hover 底色 `SliceColor.hoverFill`
  - Pin 激活态：图标色 `SliceColor.accent`
  - Close 激活态：Hover 时背景 `SliceColor.errorFill`（视觉警示）
- 整条 Header 可拖动（SwiftUI `.gesture(DragGesture())` + `NSWindow.performDrag`）

**进度条**：

- 头部下方 1.5pt 高，流式期间持续显示
- 渐变紫色条左右滑动：`linear-gradient(90deg, transparent, accent, transparent)` + 1.4s 无限循环
- `finish()` 后 `opacity 1→0`，0.18s ease-out，随后从视图层移除

**正文（Body）**：

- 12pt 上 / 16pt 左右 / 14pt 底
- `SliceFont.body`，行距 5.5，字距 -0.005em
- Markdown 渲染（用 SwiftUI `AttributedString(markdown:)` 增强版）：
  - `**bold**` / `*italic*`：加粗 / 斜体
  - `` `code` ``：inline code，padding 1.5×5pt，`accentFillLight` 底、`accentText` 色、`SliceFont.mono`
  - ``` ```code block``` ```：代码块，`hoverFill` 底、6pt 圆角、10×12pt padding、`SliceFont.mono`、横向滚动
  - `# heading`：h1-h4，14-16pt bold，上 14pt / 下 6pt
  - `- list`：20pt 缩进，2pt 行距
  - `> blockquote`：2pt 紫色左边线、10pt 左 padding、轻斜体、opacity 0.85
  - `[link](url)`：`accentText` 色 + 点状下划线（hover 变实）
- 流式光标：6×13pt `accent` 色方块，1Hz 闪烁；接收 delta 时停顿 100ms 再闪；`finish()` 后立即移除

**加载态（首字未到）**：

- Body 区单行：三个脉动紫点（`think-dots`，每个 5pt）+ "正在思考…" 文字
- 首字到达：`withAnimation(SliceAnimation.standard) { replace }`

**错误态**：

- Body 区用 "Error Block" 替代正文
- Error Block：
  - `errorFill` 底 + `errorBorder` 0.5pt 描边 + 6pt 圆角 + 12×14pt padding
  - 左上：16pt 圆形 `error` 底 + 白色 `!`
  - 右：
    - 错误标题（`SliceFont.bodyEmphasis`，色 `error` 深一级）
    - 描述（`SliceFont.callout`，色 `textSecondary`）
    - "查看详情" 可点切换（`SliceFont.caption`，`textTertiary`）
    - 展开后：`hoverFill` 底 + 等宽字体 + HTTP 状态 / provider / model（按 `SliceError.developerContext` 脱敏）
  - 底部按钮组：
    - 主按钮 "重试"：`error` 底 + 白字 + 5pt 圆角
    - 次按钮 "打开设置"：`hoverFill` 底 + `textPrimary` 字（仅在 `invalidResponse` / `authError` 等场景显示）

**底部**：

- 无底部操作栏（所有操作上移到 Header）

**Pin 状态**：

- Pin 图标激活后：图标色 `accent`，头部左侧出现 5pt 紫色小圆点
- NSPanel `level = .statusBar`（原有行为不变）
- 移除 outside-click monitor（原有行为不变）

**定位**：

- 默认选区下方，屏幕边缘自动翻转（使用 `ScreenAwarePositioner`，不改算法）
- 出现动画：opacity 0→1 + scale 0.98→1，0.18s ease-out

### 5.3 命令面板（CommandPalettePanel）

**整体**：

- 560×auto，最大高度 520pt
- 圆角 10pt / 毛玻璃 `SliceMaterial.popover` / 阴影 `SliceShadow.panel` 加强版

**位置**：屏幕中央偏上（垂直居中 +30% 位移），出现时 `scale 0.96→1 + opacity 0→1`，0.18s

**顶部选中文本预览**（当有选中文本时）：

- 8pt 上 / 6pt 下 / 16pt 左右
- 0.5pt 底分隔线
- "选中文本" label（`SliceFont.overline`，色 `textTertiary`）+ 空格 + 选中文本单行截断（`SliceFont.caption`，色 `textSecondary`，斜体）
- 无选中文本时此区不显示

**搜索框**：

- 10pt 上下 / 16pt 左右
- 左：🔍 图标 `SliceFont.headline` 色 `textTertiary` 0.5 opacity
- 右：TextField，`SliceFont.headline`，无边框
- placeholder：固定 "输入工具名、或按 ↑↓ 选择 · ↵ 执行 · ESC 关闭"
- 0.5pt 底分隔线

**列表**：

- 6pt 上下 / 6pt 左右 padding
- Item：8pt 上下 / 12pt 左右 / 6pt 圆角 / 12pt 内部 gap
  - 左图标：28×28pt 圆角 6pt，`hoverFill` 底 + 工具 emoji/SF Symbol
  - 中：标题 `SliceFont.body` + 描述 `SliceFont.caption`（色 `textTertiary`）
  - 右：快捷键 kbd 样式（2pt 上下 / 6pt 左右 padding，`hoverFill` 底，`SliceFont.mono` 10.5pt）
- 选中态（键盘高亮）：
  - Item 背景 `accentFillLight`、图标底 `accentFillStrong`、图标色 `accent`、标题色 `accentText`
- 分组（可选）：
  - 组 label：6-10pt padding，`SliceFont.overline`，色 `textTertiary`
- MVP：不做分组，全部平铺

**底部 footer**：

- 8pt 上下 / 14pt 左右
- 0.5pt 顶分隔线
- 左：`↵` kbd + "执行"；`ESC` kbd + "关闭"
- 右：`{命中数}` 或 `{命中数} / {总数}`

**空状态**：搜索无命中时，列表区中央 "没有匹配的工具"（`SliceFont.callout`，色 `textTertiary`）

### 5.4 设置窗口（SettingsScene）

**结构**：`NavigationSplitView`（sidebar + detail）

- 窗口尺寸：720×540pt 最小，用户可拖拽放大
- 窗口背景：`SliceMaterial.window`
- Title Bar：标题栏合并工具栏（`.toolbarBackground(.hidden)`）

**Sidebar（左 180pt）**：

- 背景：`SliceMaterial.sidebar`
- 内边距：8pt 上 / 10pt 左右
- Section label：`SliceFont.overline`，10pt 上 / 4pt 下，色 `textTertiary`
- Item：7×10pt padding / 6pt 圆角 / 10pt 内部 gap
  - 左图标：22×22pt 圆角 5pt，底色 `hoverFill` + 图标色 `textSecondary`
  - 右：`SliceFont.subheadline`，色 `textPrimary`
- 选中态：整行底 `accentFillLight` + 图标底 `accentFillStrong` + 图标色 `accent` + 文字色 `accentText` + weight `.medium`
- Hover：整行底 `hoverFill`（非选中）

**Sidebar 内容（7 项）**：

1. 通用
   - 🎨 外观（主题切换）
   - ⌨️ 快捷键
   - 🎯 触发行为
2. 模型
   - 🔌 Providers
   - ✨ 工具（Tools）
3. 其他
   - 🛡️ 权限
   - ℹ️ 关于

**Detail（右侧）**：

- 背景：`SliceColor.surface`（纯白 / 纯深灰）
- 内边距：20pt 上 / 28pt 左右 / 20pt 下
- 顶部：
  - Page Title（`SliceFont.title`）
  - Page Subtitle（`SliceFont.callout`，色 `textSecondary`）
  - 18pt 下间距
- 内容：圆角白卡（Section Block）
  - Section：`SliceColor.surface` 底 + 0.5pt `border` + 8pt 圆角 + 12×14pt padding + 14pt 下间距
  - Section 标题：`SliceFont.captionEmphasis`，色 `textSecondary`，下间距 8pt，字距 0.08em uppercase
  - Row：8pt 上下 / 0.5pt 底分隔线（最后一行无）
    - Label 左 + Control 右（右对齐）
    - 多行 label：主文本 `SliceFont.subheadline` + 副文本 `SliceFont.caption`（色 `textSecondary`）
  - Control（输入框 / 选择器 / Toggle / 按钮）：
    - 输入框：4×8pt padding，0.5pt border，5pt 圆角，focus 时 `accent` border + 3pt `accentFillLight` 光晕
    - 选择器：原生 Picker 样式（menu style）
    - Toggle：macOS 原生 SwiftUI Toggle，tint color `accent`
    - 按钮：pill 样式，主按钮 `accent` 底 + 白字，次按钮 `hoverFill` 底

**7 个页面内容**：

| 页面 | 核心 Section |
|---|---|
| 外观 | 主题选择（Radio：Auto/Light/Dark） |
| 快捷键 | 命令面板快捷键（⌥Space 默认）、工具绑定快捷键（⌘1-9）|
| 触发行为 | 划词 debounce 延迟、minSelectionLength、blacklist app 列表 |
| Providers | 已配置列表 + 编辑区（Base URL / API Key / 默认模型）|
| 工具 | 工具列表（icon 图 + 名称 + prompt template 编辑）|
| 权限 | 辅助功能权限状态 + "打开系统设置" 按钮 |
| 关于 | 版本号、GitHub 链接、License、更新日志 |

**底部保存栏**：

- 原有 "saveBar" 替换为：只在有未保存更改时从底部滑入，0.5pt 顶分隔线 + `SliceMaterial.window` 底
- 内容：左侧灰字 "有未保存的更改"，右侧 "放弃 / 保存" 双按钮

### 5.5 Onboarding（OnboardingFlow）

**窗口**：

- 560×520pt 固定，不可缩放
- 屏幕居中
- 背景：`SliceColor.surface`
- 无 titlebar 区（合并到内容区），只保留 traffic lights

**步骤指示器**：

- 14pt 上 padding，居中
- 3 个步骤节点 + 2 条连接线
- 节点：20pt 圆 + `captionEmphasis` 数字
  - pending：`hoverFill` 底 / `textTertiary` 字
  - active：`accent` 底 / 白字 + 4pt `accentFillLight` 外光晕
  - done：`accentFillLight` 底 / `accentText` 字 / ✓ 图标
- 连线：38×1.5pt，pending `divider` 色，done `accent` 0.4 opacity
- label（"欢迎 / 权限 / 接入模型"）：`SliceFont.overline`，节点右侧 6pt 处

**Body**：

- 28pt 上 / 48pt 左右 / 22pt 下
- 居中对齐
- 结构（每步通用）：
  1. Hero Icon（88×88pt 圆角 22pt，紫色系渐变底 + 内高光 + 外阴影）
  2. Hero Title（`SliceFont.displayLarge`，8pt 下间距）
  3. Hero Subtitle（`SliceFont.body`，色 `textSecondary`，居中，max-width 380pt，20pt 下间距）
  4. 动态内容区

**三步详细**：

| Step | Hero Icon | Title | Subtitle | 内容区 |
|---|---|---|---|---|
| 1 欢迎 | ✨ 紫色渐变 `#A78BFA→#7C3AED` | 欢迎使用 SliceAI | 选中任意应用里的文字，立刻用 AI 翻译、改写、总结。接下来 3 步配好就能用。 | 两条 info-row：①授权辅助功能 ②填入 API Key |
| 2 权限 | 🛡️ 蓝紫渐变 `#818CF8→#6366F1` | 授权辅助功能 | SliceAI 需要"辅助功能"权限读取你选中的文本。我们只读选区，不读其他内容。 | 状态条（等待/成功）+ 两个按钮：打开系统设置 / 我已授权检测 |
| 3 接入模型 | 🔌 紫粉渐变 `#F472B6→#DB2777` | 接入你的模型 | 任何 OpenAI 兼容服务都能用。API Key 存储在系统 Keychain。 | 表单：服务商选择 + API Key 输入框 + 提示文字 |

**info-row** 样式：12×14pt padding / `hoverFill` 底 / 7pt 圆角 / 12pt gap / 380pt max-width / 10pt 下间距

**权限状态条**：

- pending：`warning` 色系，"等待授权 · 系统设置 → 隐私与安全性 → 辅助功能"
- success：`success` 色系，"已授权"

**Footer**：

- 14×20pt padding / 0.5pt 顶分隔线 / `surface` 半透明底
- 左：纯文字按钮"稍后再说 / ← 返回"
- 右：主按钮"开始设置 → / 下一步 → / 完成"

**跳过/返回行为**：

- Step 1 "稍后再说" → 关闭 Onboarding 窗口，菜单栏图标显示未配置提示（小红点）
- Step 2/3 "← 返回" → 上一步
- Step 3 "完成" → 窗口 scale 0.96 + opacity 0，0.25s 动画后关闭，保存 `onboardingCompleted = true`

### 5.6 菜单栏（MenuBarController）

- 图标：保留 SF Symbol `scissors`
- 未配置状态：图标右上小红点（6pt 紫色圆，`accent` 底）
- 下拉菜单：
  - 打开设置…
  - 外观 → Auto / Light / Dark（submenu）
  - 分隔线
  - 关于 SliceAI
  - 退出
- 菜单样式：使用原生 NSMenu（不自定义），保持系统一致性

---

## 6. 代码组织

### 6.1 新增 DesignSystem target

在 `SliceAIKit/Package.swift` 新增第 8 个 library target：

```
.library(name: "DesignSystem", targets: ["DesignSystem"]),
...
.target(
    name: "DesignSystem",
    dependencies: [],
    path: "Sources/DesignSystem",
    resources: [
        .process("Resources/Assets.xcassets"),  // 颜色资产
    ],
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .enableUpcomingFeature("ExistentialAny"),
    ]
),
.testTarget(
    name: "DesignSystemTests",
    dependencies: ["DesignSystem"],
    path: "Tests/DesignSystemTests"
)
```

**DesignSystem 文件结构**：

```
SliceAIKit/Sources/DesignSystem/
├── Colors/
│   ├── SliceColor.swift              // 语义色 Color 扩展
│   └── Resources/Assets.xcassets/    // Any/Dark 颜色资产
├── Typography/
│   └── SliceFont.swift
├── Layout/
│   ├── SliceSpacing.swift
│   ├── SliceRadius.swift
│   └── SliceShadow.swift
├── Animation/
│   └── SliceAnimation.swift
├── Materials/
│   ├── SliceMaterial.swift           // enum 包装 NSVisualEffectView.Material
│   └── VisualEffectView.swift        // NSViewRepresentable 封装
├── Theme/
│   ├── AppearanceMode.swift          // Light/Dark/Auto enum
│   └── ThemeManager.swift            // @Observable
├── Components/
│   ├── IconButton.swift              // 22×22 / 30×30 图标按钮
│   ├── PillButton.swift              // 主按钮 / 次按钮
│   ├── SectionCard.swift             // 圆角白卡 Section
│   ├── Chip.swift                    // 小标签
│   ├── KbdKey.swift                  // 键盘按键样式
│   ├── DragHandle.swift              // 6 点拖拽把手
│   ├── ProgressStripe.swift          // 流式进度条
│   ├── ThinkingDots.swift            // 加载态三点
│   ├── StepIndicator.swift           // Onboarding 步骤指示器
│   ├── HeroIcon.swift                // Onboarding Hero 图标
│   └── ErrorBlock.swift              // 错误 block
└── Modifiers/
    ├── GlassBackground.swift         // .glassBackground(.hud)
    ├── HoverHighlight.swift          // .hoverHighlight()
    ├── PressScale.swift              // .pressScale()
    └── ThemeAware.swift              // 应用主题
```

### 6.2 依赖图更新

```
Before:
  SliceCore
  LLMProviders          → SliceCore
  SelectionCapture      → SliceCore
  HotkeyManager         → SliceCore
  Windowing             → SliceCore
  Permissions           → SliceCore
  SettingsUI            → SliceCore

After:
  SliceCore
  DesignSystem          (新增，零业务依赖，仅 SwiftUI)
  LLMProviders          → SliceCore
  SelectionCapture      → SliceCore
  HotkeyManager         → SliceCore
  Windowing             → SliceCore, DesignSystem
  Permissions           → SliceCore, DesignSystem
  SettingsUI            → SliceCore, DesignSystem
```

SliceCore 依然零 UI 依赖；DesignSystem 不依赖任何业务 target（纯 presentation layer）。

### 6.3 删除旧的中心化样式

- 删除 `Windowing/PanelStyle.swift`（所有 token 迁移到 DesignSystem）
- 删除 `PanelColors` enum
- 删除 `WindowSizes`、`WindowSpacing` 等散落的常量

### 6.4 迁移约定

- 硬编码 Color 全部替换为 `SliceColor.xxx`
- 硬编码 font size 全部替换为 `SliceFont.xxx`
- 硬编码 padding 全部替换为 `SliceSpacing.xxx`
- 硬编码圆角全部替换为 `SliceRadius.xxx`
- 通用交互逻辑（hover / press / glass background）替换为 modifier
- 重复 UI 结构（按钮 / chip / section）替换为 Component

---

## 7. 关键 API 草案

### 7.1 ThemeManager

```swift
@Observable
public final class ThemeManager {
    public var mode: AppearanceMode = .auto  // 触发 @Observable
    public var resolvedColorScheme: ColorScheme { ... }  // 根据 mode + 系统状态解析
    public var nsAppearance: NSAppearance { ... }
    public init(initialMode: AppearanceMode)
    public func setMode(_ mode: AppearanceMode)  // 持久化 + 触发 UI 更新
}
```

### 7.2 VisualEffectView

```swift
public struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    )
    public func makeNSView(context: Context) -> NSVisualEffectView
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context)
}

public extension View {
    func glassBackground(_ material: SliceMaterial) -> some View {
        background(VisualEffectView(material: material.nsMaterial))
    }
}
```

### 7.3 Configuration 扩展

```swift
public struct Configuration: Codable {
    // 现有字段 ...
    public var appearance: AppearanceMode = .auto  // NEW
    // 迁移：JSON 解码时缺失字段回落为 .auto
}
```

`config.schema.json` 同步更新：

```json
{
  "appearance": {
    "type": "string",
    "enum": ["auto", "light", "dark"],
    "default": "auto"
  }
}
```

### 7.4 AppContainer 改动

```swift
@MainActor
final class AppContainer {
    // 现有依赖 ...
    let themeManager: ThemeManager  // NEW

    init(...) {
        let appearance = configStore.configuration.appearance
        self.themeManager = ThemeManager(initialMode: appearance)
        // 订阅 ThemeManager 变化 → 写回 ConfigurationStore
    }
}

// 根视图注入
ContentView()
    .environment(container.themeManager)
```

---

## 8. 实现约束

### 8.1 必须遵守

- SliceCore 保持零 UI 依赖
- `StrictConcurrency=complete` + `ExistentialAny` 全 target 启用
- UI 类 `@MainActor` 标注；ThemeManager 必须 `@MainActor`（涉及 NSAppearance）
- 所有 public API 带 `///` 文档注释
- `swiftlint lint --strict` 零警告
- 不新增外部依赖包

### 8.2 文件拆分

- 按 `.swiftlint.yml` 要求：file length warning 500 / error 700
- DesignSystem 每个 Component 独立文件（避免超限）
- SettingsScene 如超过 500 行要拆分到子视图文件

### 8.3 测试保持

- 现有测试（`SliceCoreTests` / `LLMProvidersTests` / `SelectionCaptureTests` / `HotkeyManagerTests` / `WindowingTests`）全部保持通过
- 覆盖率不降低
- ThemeManager 新增单元测试（见 §9）

---

## 9. 测试策略

### 9.1 DesignSystemTests（新增）

- `ThemeManager.resolvedColorScheme` 正确性：`.auto + system=dark → .dark` / `.light → .light` / `.dark → .dark`
- `AppearanceMode` JSON 编码 / 解码
- `ThemeManager.setMode` 持久化副作用（通过 spy）

### 9.2 现有 SettingsViewModel 测试

- 新增 `appearance` 字段的序列化测试
- 迁移测试：加载旧 config（无 appearance 字段）回落到 `.auto`

### 9.3 手动验收清单

- [ ] 三种主题切换正常（Light/Dark/Auto），无闪烁
- [ ] 系统切换 Dark Mode 时 Auto 100ms 内跟进
- [ ] 悬浮工具栏把手拖拽流畅，游标正确变化（open/closed hand）
- [ ] 拖拽期间 5s 自动消失计时器暂停
- [ ] 结果面板 Markdown 各元素正确渲染（标题/列表/引用/代码块/行内代码/链接/加粗）
- [ ] 结果面板 Header 可拖动整个窗口
- [ ] 流式进度条滑动流畅无卡顿
- [ ] 加载态"三点"脉动，首字到达平滑切换
- [ ] 错误态 Error Block 可展开详情、按钮正确触发
- [ ] 命令面板键盘导航（↑↓↵ESC）正常
- [ ] 设置窗口 NavigationSplitView 切换流畅，侧栏高亮正确
- [ ] 输入框 focus 紫色光晕 + border 色变化
- [ ] Onboarding 三步流程走完，进度指示器正确
- [ ] Onboarding 权限实时检测（授权后状态条变绿，下一步按钮启用）
- [ ] 菜单栏图标未配置时有小红点
- [ ] 视觉对比度：亮色正文 WCAG AA 通过（4.5:1），暗色同步通过
- [ ] 所有毛玻璃在真实桌面背景下观感自然，不泛白

---

## 10. 范围外 / 后续展望（Roadmap）

**v0.2 可能加的**：

- Markdown 代码块语法高亮（Splash 或 Highlightr）
- Onboarding 欢迎步骤加入一个小的 demo 动画（录屏截取"划词 → 工具栏 → 结果面板"）
- 高对比度 / 色盲友好模式（新增 AppearanceMode.highContrast）
- i18n（英文界面）
- 用户自定义强调色（不止紫色）
- 菜单栏图标动态：使用时旋转脉动
- 通知中心通知（长时间流式、错误时 Banner）
- 工具栏布局选项（水平/垂直/网格）

---

## 11. 风险与开放问题

### 11.1 已识别风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| NSVisualEffectView 在毛玻璃叠加时出现"双层模糊"异常 | 视觉瑕疵 | 逐窗口测试；必要时切换到 `.underWindowBackground` |
| `@Observable ThemeManager` 跨 NSWindow 同步延迟 | 切主题时窗口间闪烁 | 显式在 `NSWindow.appearance` 上设置；用 `NotificationCenter` 主动推送 |
| 拖拽工具栏时主线程 `NSWindow.performDrag` 阻塞 SwiftUI 渲染 | 卡顿 | 用 `.gesture(DragGesture())` 非阻塞；性能差时降级到 `NSPanel.isMovableByWindowBackground` |
| SF Mono 不支持中文 fallback 显示异常 | 代码块中英混排丑 | 代码块仅等宽 + 自然 fallback，不做字体混排优化 |
| 圆角 8pt 对老版 macOS 14 以下的边缘抗锯齿不佳 | 视觉瑕疵 | 仅支持 macOS 14+（项目已声明） |

### 11.2 默认决策（可在实施中回头修正）

- **品牌紫对比度验收**：当前值（`#7C3AED` / `#A78BFA`）经过常见桌面背景目测可用。实施阶段在 §9.3 手动验收清单增加"在 macOS 标准壁纸 + 纯白 / 纯黑桌面下截屏对比"一项；不达标时提升暗色到 `#B59CFF` 或降低亮色到 `#6D28D9`。
- **菜单栏外观子菜单**：采用 flat 三选一（Auto / Light / Dark 并列），不做两层次级。
- **Onboarding 权限检测按钮**：同步检测，不加 loading 态（AX 检查非阻塞；按下后立即更新状态条）。
- **关于页**：不加赞助 / 反馈按钮；仅版本号 / GitHub 链接 / License / 更新日志。后续独立 issue 评估再加。

---

## 12. 附录：视觉资产

### 12.1 颜色令牌表（可直接导出 Xcode Assets）

（见 §3.1 的值列表）

### 12.2 参考视觉

Brainstorming 过程中的 mockup 文件保留在 `.superpowers/brainstorm/`：

- `design-language.html` — 初步三方向对比（已选方案 B）
- `accent-strategy.html` — 强调色策略（已选方案 2）
- `toolbar-shape-v2.html` — 工具栏圆角与拖拽把手（已选档位 1）
- `result-panel.html` / `result-panel-states.html` — 结果面板完整态
- `command-palette.html` — 命令面板
- `settings-structure.html` — 设置窗口（已选方案 A）
- `onboarding.html` — Onboarding 三步

这些文件不入库但供日后参考。

---

**下一步**：用户 review 本 spec → 如有修改需求回头修正 → 否则调用 `superpowers:writing-plans` 生成分步实施计划。
