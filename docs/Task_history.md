# Task History

SliceAI 项目任务历史记录索引。每条记录对应 `docs/Task-detail/` 目录下的详细文件。

---

## Task 22 · MenuBarController 增强 + PanelStyle 清理 + SwiftLint 总验收

- **时间**：2026-04-21
- **描述**：MVP v0.1 UI 美化阶段收官任务，清理历史技术债、补全菜单栏功能并通过 SwiftLint strict 总验收
- **详情**：[docs/Task-detail/ui-polish-2026-04-21.md](Task-detail/ui-polish-2026-04-21.md)
- **结果**：完成，swift build / swift test / xcodebuild / swiftlint --strict 全绿

---

## Task 21 · OnboardingFlow 重构

- **时间**：2026-04-20
- **描述**：重新设计首次启动引导流程，560×520 三步骤 + 步骤指示器 + Hero 图标风格
- **结果**：完成

---

## Task 18–20 · SettingsScene 重构 + 所有子页填充

- **时间**：2026-04-15 – 2026-04-19
- **描述**：Settings 迁移为 NavigationSplitView；依次填充 Hotkey/Trigger/Permissions/About/Providers/Tools 页面；新增 Appearance 外观切换页
- **结果**：完成

---

## Task 12–17 · 面板 UI 全面重构

- **时间**：2026-04-08 – 2026-04-14
- **描述**：FloatingToolbarPanel / ResultPanel / CommandPalettePanel 使用 DesignSystem token 彻底重构；ResultPanel 拖拽把手 / Header 4 按钮 / StreamingMarkdownView 增强
- **结果**：完成

---

## Task 1–11 · DesignSystem target 搭建

- **时间**：2026-03-28 – 2026-04-07
- **描述**：新建 DesignSystem SwiftPM target；依次完成颜色/字体/间距/圆角/阴影/动画 token、交互 modifier（GlassBackground/HoverHighlight/PressScale）、基础组件（IconButton/PillButton/Chip/KbdKey/SectionCard）、动画组件（DragHandle/ProgressStripe/ThinkingDots）、Onboarding 组件（StepIndicator/HeroIcon/ErrorBlock）；ThemeManager + AppearanceMode；AppContainer 注入 ThemeManager；Configuration.appearance 字段扩展
- **结果**：完成
