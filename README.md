# SliceAI

> macOS 开源划词触发 LLM 工具栏

SliceAI 让你在任何 Mac 应用里选中文字后，通过快捷工具栏或 `⌥Space` 命令面板调用 OpenAI 兼容的大模型，流式查看结果。

## Status

v0.1 开发中。参见 [docs/superpowers/plans](docs/superpowers/plans/) 跟踪进度。

## Features (MVP v0.1)

- 划词后自动弹出浮条工具栏（PopClip 风格）
- `⌥Space` 快捷键唤起中央命令面板
- 独立浮窗 Markdown 流式渲染
- 支持 OpenAI 兼容协议（OpenAI、DeepSeek、Moonshot、OpenRouter、自建中转…）
- 4 个内置工具：Translate / Polish / Summarize / Explain
- 自定义 prompt、供应商、模型
- API Key 存 macOS Keychain

## Build from source

```bash
git clone https://github.com/<you>/SliceAI.git
cd SliceAI
open SliceAI.xcodeproj
# Product → Run
```

## Requirements

- macOS 14 Sonoma 或更新
- Xcode 26 或更新
- Swift 6.0

## 项目修改变动记录

### 2026-04-21 · UI 全面美化 + Task 22 收官

**范围**：Task 18–22（跨越约 4 周的 MVP v0.1 UI 迭代）

**主要变更**：
- 新增 `DesignSystem` SwiftPM target：颜色/字体/间距/圆角/阴影/动画 token + 交互 modifier（GlassBackground、HoverHighlight、PressScale）+ 基础组件（IconButton、PillButton、Chip、KbdKey、SectionCard）
- `ThemeManager` + `AppearanceMode`：全局浅色/深色/跟随系统主题切换，`onModeChange` 回调持久化到 config.json
- 重构所有面板（FloatingToolbarPanel / CommandPalettePanel / ResultPanel）使用 DesignSystem token，删除旧 `PanelStyle.swift`
- 设置界面迁移为 `NavigationSplitView`，新增外观页（Appearance）；填充所有设置子页内容
- `OnboardingFlow` 重设计：560×520 步骤指示器 + Hero 图标风格
- `MenuBarController` 增强：外观子菜单（跟随系统/浅色/深色）+ 未配置 Provider 时图标右上角叠加紫色小红点
- SwiftLint strict 清零：修复 `implicit_return`、`opening_brace`、`sorted_imports`、`line_length`、`force_unwrapping` 共 6 处（4 项真实修复，2 项加 disable 注释说明原因）

**验证状态**：
- `swift build`：Build complete
- `swift test --parallel`：All tests passed
- `swiftlint lint --strict`：0 violations, 0 serious
- `xcodebuild`：BUILD SUCCEEDED

## License

MIT — see [LICENSE](LICENSE)
