# SliceAI-lite

> macOS 开源划词触发 LLM 工具栏 · 轻量持续迭代版

SliceAI-lite 让你在任何 Mac 应用里选中文字后，通过快捷工具栏或 `⌥Space` 命令面板调用 OpenAI 兼容的大模型，流式查看结果。

## Relation to SliceAI

本仓库是 [yingjialong/SliceAI](https://github.com/yingjialong/SliceAI) 在 2026-04-23 基于 commit `6c62016` 分出的独立仓库：

- **主仓库 `SliceAI`**：进行 v2 架构重构（见主仓库 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`）
- **本仓库 `SliceAI-lite`**：在 MVP v0.1 基础上持续做增量功能迭代

两者可在同一台机器上并存安装（bundle id `com.sliceai.SliceAI` vs `com.sliceai.lite`，配置目录 / Keychain / Logger subsystem 完全隔离）。

## Features (MVP v0.1)

- 划词后自动弹出浮条工具栏（PopClip 风格）
- `⌥Space` 快捷键唤起中央命令面板
- 独立浮窗 Markdown 流式渲染
- 支持 OpenAI 兼容协议（OpenAI、DeepSeek、Moonshot、OpenRouter、自建中转…）
- 4 个内置工具：Translate / Polish / Summarize / Explain
- 自定义 prompt、供应商、模型
- API Key 存 macOS Keychain

## Install

从 [Releases 页](https://github.com/yingjialong/SliceAI-lite/releases) 下载 `SliceAI-lite-<version>.dmg`（unsigned + ad-hoc codesign，免费分发）：

```bash
# 1. 挂载 DMG
open ~/Downloads/SliceAI-lite-0.1.0.dmg
# Finder 里把 SliceAI-lite.app 拖到 Applications 软链

# 2. 解除 Gatekeeper quarantine（否则首次双击会报"无法验证开发者"）
xattr -d com.apple.quarantine /Applications/SliceAI-lite.app

# 3. 启动（会弹 Onboarding 窗口）
open /Applications/SliceAI-lite.app
```

首次启动必须授予 Accessibility 权限：

1. 系统设置 → 隐私与安全 → 辅助功能
2. 点 `+` → 选 `/Applications/SliceAI-lite.app` → 打勾启用
3. **完全退出 app 再重启**（macOS 不会让运行中的 app 中途拿到新授权）：
   ```bash
   osascript -e 'tell application "SliceAI-lite" to quit' && sleep 1 && open /Applications/SliceAI-lite.app
   ```
4. 菜单栏点 SliceAI-lite 图标 → Settings → Providers → 添加 OpenAI 兼容 + 填 API Key
5. 在任意 app 里划词 → 浮条弹出选工具 → 流式结果窗口显示

### Accessibility 权限失效排查

正常情况授权一次就持久。但**覆盖安装新版本后需要重新授权一次**，因为 macOS 按 binary cdhash 识别身份，新打包的 .app cdhash 跟旧的不同。

如果划词没反应：

```bash
tccutil reset Accessibility com.sliceai.lite
```

然后重新走上面"在系统设置里加权限 → 完全退出重启"流程。

## Build from source

```bash
git clone https://github.com/yingjialong/SliceAI-lite.git
cd SliceAI-lite

# 方式 A：打包 DMG（Release + ad-hoc 签名，产物在 build/）
scripts/build-dmg.sh                # → build/SliceAI-lite-0.1.0.dmg
scripts/build-dmg.sh 0.2.0          # 自定义版本号

# 方式 B：Xcode 直接跑
open SliceAI.xcodeproj
# Product → Run
```

跑 SwiftPM 单测：

```bash
cd SliceAIKit && swift test --parallel --enable-code-coverage
```

## Requirements

- macOS 14 Sonoma 或更新
- Xcode 26 或更新
- Swift 6.0

## 项目修改变动记录

### 2026-04-25 · 思考模式切换功能（thinking mode toggle）— 自动化收尾

**范围**：Task 26（spec / plan 见 `docs/superpowers/specs/2026-04-24-thinking-mode-toggle-design.md`、`docs/superpowers/plans/2026-04-24-thinking-mode-toggle.md`，详情见 `docs/Task-detail/thinking-mode-toggle-2026-04-24.md`）

**主要变更**：
- SliceCore 引入 `ProviderThinkingCapability`（`byModel` / `byParameter`）；`Tool` 加 `thinkingModelId` / `thinkingEnabled`；`ChatRequest` 加 `extraBody`（去 Codable 换简洁性）；`ChatChunk` 加 `reasoningDelta`
- LLMProviders 在 `OpenAICompatibleProvider.buildURLRequest` merge `extraBody` 进 body root（不覆盖既有字段）；`decodeChunk` 用 fallback chain 提取 reasoning（`delta.reasoning` → `delta.reasoning_content` → nil）—— 任何模板/直连无需绑定即可工作
- SettingsUI 新增 `ProviderThinkingSectionView`：模式 Picker + 7 模板选择（OpenRouter unified / DeepSeek V4 / Anthropic adaptive+budget / OpenAI reasoning_effort / Qwen3 / custom）+ 双 JSON 编辑器 + 实时校验；`ToolEditorView` 在 byModel 模式下显示 `thinkingModelId` 字段；`SettingsViewModel.toggleThinking()` 提供持久化入口
- Windowing/ResultPanel 顶部新增 brain.head.profile toggle 按钮 + "💭 思考过程" DisclosureGroup（默认折叠、流式累积 reasoningDelta）；AppDelegate 桥接 `onToggleThinking`：cancel 旧 streamTask → 新 execute
- DefaultConfiguration seed Provider 从 1 → 3：OpenAI（`reasoning_effort`）+ OpenRouter（unified `reasoning.effort`）+ DeepSeek V4（`thinking.type`），全部预填 thinking 模板，用户首次启动只需填 API Key 即可启用 thinking 切换
- 全部新字段 backward compat（`decodeIfPresent`），schemaVersion 不 bump；老用户 config.json 不会自动注入新增 Provider，需要手动添加

**验证状态**：
- `swift build`：Build complete
- `swift test --parallel --enable-code-coverage`：124/124 通过（新增 1 个 `test_defaultConfig_providersThinkingPrefilled` 字面值断言）
- `swiftlint lint --strict`：0 violations
- `xcodebuild -scheme SliceAI -configuration Debug build`：BUILD SUCCEEDED
- 真机 E2E（DeepSeek V4 / OpenRouter / 错误路径）：**待验收**

### 2026-04-23 · 从 SliceAI 分叉为独立 SliceAI-lite 仓库

**范围**：仓库隔离 + 产物重命名 + 图标 + 签名修复（commits `4119621..a8712d5`）

**主要变更**：
- 新建 GitHub 仓库 `yingjialong/SliceAI-lite`，切断与主仓库的共享
- 运行时数据隔离：bundle id `com.sliceai.lite`、配置目录 `~/Library/Application Support/SliceAI-lite/`、Keychain service `com.sliceai.lite.providers`、Logger subsystem `com.sliceai.lite` / `com.sliceai.lite.core`
- 产物命名：`.app` → `SliceAI-lite.app`、DMG → `SliceAI-lite-<ver>.dmg`（Xcode project/scheme 名保持 `SliceAI` 以最小化改动，只改 `PRODUCT_NAME`）
- 新增 App Icon：紫色霓虹 "AI" + Lite 角标（10 个尺寸 PNG 编入 `Assets.car`）
- `build-dmg.sh` 增加 ad-hoc codesign 步骤，根治 Accessibility 授权"一刷新就失效"问题：原因是完全 unsigned 的 .app 只有 linker-signed 伪签名，TCC 无法稳定追踪 cdhash + bundle id；ad-hoc 签名（不需要任何开发者证书）能产生完整 cdhash + sealed resources

**验证状态**：
- `swift test --parallel`：99/99 通过
- `swiftlint lint --strict`：0 violations
- `xcodebuild archive`：BUILD SUCCEEDED
- `scripts/build-dmg.sh`：成功产出带图标 + ad-hoc 签名的 3.8MB DMG
- 实际装机 + 划词 + Accessibility 授权持久化：全部验证 OK

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
