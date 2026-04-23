# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目定位

SliceAI 是 macOS 原生、开源的划词触发 LLM 工具栏。划词后弹出浮条工具栏（PopClip 风格），或按 `⌥Space` 调出命令面板（Raycast 风格），通过 OpenAI 兼容协议调用大模型并流式渲染结果。

- 平台：macOS 14 Sonoma+，Xcode 26+，Swift 6.0
- 状态：MVP v0.1 开发中（unsigned，不上架 App Store，需 Accessibility 权限）

## 常用命令

所有 Swift 包命令在 `SliceAIKit/` 子目录执行；App target 命令在仓库根目录执行。

```bash
# 构建 SliceAIKit（领域库 + 8 个子模块）
cd SliceAIKit && swift build

# 跑全部单元测试（并行 + 覆盖率）
cd SliceAIKit && swift test --parallel --enable-code-coverage

# 跑单个 target / 单个测试
cd SliceAIKit && swift test --filter SliceCoreTests
cd SliceAIKit && swift test --filter SliceCoreTests.ToolExecutorTests/test_execute_xxx

# Lint（CI 用 --strict，本地常规）
swiftlint lint
swiftlint lint --strict

# 构建 App（需要 Xcode）
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build

# 打包 unsigned DMG（默认版本 0.1.0；CI 用 tag 触发）
scripts/build-dmg.sh                # 输出 build/SliceAI-0.1.0.dmg
scripts/build-dmg.sh 0.2.0          # 自定义版本号
```

## 架构总览

两层结构：**App target（薄壳）+ 单一 Local SwiftPM Package**。

```
SliceAI.app  (Xcode App target, SliceAIApp/)
  ├─ @main 入口、菜单栏、Onboarding、Composition Root（AppContainer）
  └─ depends on → SliceAIKit (Local SwiftPM)

SliceAIKit  (SliceAIKit/Package.swift, 8 个 library target)
  ├─ SliceCore         领域层，Foundation only，零 UI 依赖
  ├─ LLMProviders      OpenAI 兼容协议 + SSE 流式
  ├─ SelectionCapture  AX 主路径 + Cmd+C 备份恢复路径
  ├─ HotkeyManager     Carbon RegisterEventHotKey 全局热键
  ├─ DesignSystem      颜色/字体/间距/圆角 token + ThemeManager + 共享组件（IconButton/PillButton/SectionCard…）
  ├─ Windowing         FloatingToolbar / CommandPalette / ResultPanel（依赖 DesignSystem）
  ├─ Permissions       Accessibility 权限轮询 + Onboarding 视图（依赖 DesignSystem）
  └─ SettingsUI        SwiftUI 设置界面 + KeychainStore + ConfigurationStore（依赖 DesignSystem）
```

### 模块依赖（关键不变量）

- **SliceCore 必须零 UI 依赖**（仅 Foundation）：保证未来能复用为 CLI / MCP server。`AppearanceMode`（`SliceCore/AppearanceMode.swift`）是这里唯一跟视觉相关的类型，但它只是 Codable enum，不碰 AppKit / SwiftUI。
- **DesignSystem 只被 UI 层依赖**（Windowing / Permissions / SettingsUI），**严禁被 SliceCore / LLMProviders / SelectionCapture / HotkeyManager 反向依赖**——否则领域层又会被拖进 AppKit，破坏"未来跑 CLI / MCP server"的前提。
- **Provider 是 protocol**（`SliceCore/LLMProvider.swift`）：当前只有 OpenAI 兼容实现，社区可零改动新增 Claude / Gemini / Ollama。
- **模块间只通过 SliceCore 的 protocol 通信**：`ConfigurationProviding`、`KeychainAccessing`、`LLMProvider` 都是 protocol，`SelectionSource` / `PasteboardProtocol` / `CopyKeystrokeInvoking` 同理。这让单元测试可以注入 Fake，模块替换不影响其他层。
- **配置与密钥严格分离**：`Configuration` 走 JSON（`~/Library/Application Support/SliceAI-lite/config.json`，schema 见 `config.schema.json`）；API Key 永远在 Keychain（`service: com.sliceai.lite.providers`），通过 `Provider.apiKeyRef = "keychain:<account>"` 间接引用。
- **Composition Root 集中在 `SliceAIApp/AppContainer.swift`**：所有跨模块依赖在 App 启动时一次性装配，业务层不再分散 init。
- **主题切换中枢是 `DesignSystem/Theme/ThemeManager`**：读写 `Configuration.appearanceMode`（system / light / dark），由 `AppContainer` 在启动时注入一次；切换时通过 `onModeChange` 回调把变更持久化回 `ConfigurationStore`。UI 层只读环境里的 `ThemeManager`，不直接碰 `NSApp.appearance`。

### 触发与执行流（核心数据流）

```
mouseDown → 记录起点 → mouseUp → 算位移 ≥ 5pt → debounce(triggerDelayMs)
  → SelectionService.capture()                       // AX 主 → Cmd+C fallback（透明降级）
  → 黑名单 / 长度过滤
  → FloatingToolbarPanel.show(tools, anchor)
  → onPick(tool)
  → ToolExecutor.execute(tool, payload)             // actor，渲染 prompt + 取 Key
  → OpenAICompatibleProvider.stream(request)        // SSE 流
  → ResultPanel.open(..., anchor, onDismiss: { streamTask.cancel() })   // 浮出于选区附近，可钉可拖可 resize
  → ResultPanel.append(chunk.delta) / .finish() / .fail(SliceError, onRetry, onOpenSettings)
  ↑ 非钉态：装 outside-click monitor，点 panel 外 → dismiss → onDismiss 回调 cancel streamTask
    → 执行链 catch `CancellationError` / `URLError.cancelled` 静默退出
  ↑ 钉态（pin.fill）：level=.statusBar、移除 monitor；跨 open() 保留
```

两条触发路径（mouseUp 浮条 / ⌥Space 命令面板）都走 `SelectionService.capture()` 的"AX 优先 → Cmd+C fallback 透明降级"链路——spec §1.4 / §3.1 / §7.2 明确要求这样以覆盖 Sublime / VSCode / Figma / Slack 等不暴露 AX 的应用。被动触发（mouseUp）的"虚假浮条"由三道防线挡住：5pt 位移过滤（installMouseMonitor）+ `ClipboardSelectionSource` 的 `changeCount` 校验（无真正选中时 ⌘C 是 no-op、changeCount 不变就返回 nil）+ `minimumSelectionLength` 长度过滤。`SelectionService.captureFromPrimaryOnly()` API 仍保留，作为未来"strict AX-only"策略的入口，当前生产路径不使用。

### Swift 6 严格并发约定

- `Package.swift` 全 target 启用 `StrictConcurrency=complete` + `ExistentialAny`。
- UI 类（`AppContainer`、`AppDelegate`、`MenuBarController`、所有 `Panel`）一律 `@MainActor`。
- 跨 actor 边界的依赖通过 `protocol Sendable` 约束；`HotkeyRegistrar` 等基于 C 回调的类标 `@unchecked Sendable` 并在注释中说明运行时不变量。
- Carbon / NSEvent 等 C 回调跳回主线程时统一用 `Task { @MainActor in ... }`，禁止 `MainActor.assumeIsolated`（曾在 ClipboardSelectionSource 因 assumeIsolated 触发运行时陷阱，已在 `focusProvider` 改为 `@MainActor @Sendable` 闭包 + `await` 跳主线程）。

### 错误模型

`SliceError`（`SliceCore/SliceError.swift`）是统一错误枚举，分四类（selection / provider / configuration / permission）。每个 case 提供：
- `userMessage`：中文友好文案，由 `ResultPanel.fail(...)` 直接展示给用户。
- `developerContext`：脱敏后的日志摘要——**对携带任意字符串 payload 的 case（如 `invalidResponse(String)`、`sseParseError(String)`、`invalidJSON(String)`）一律输出 `<redacted>`**，避免 API Key / 响应体 / 用户文本流入日志。新增带 String 关联值的错误 case 时必须遵守这一约定。

### "无自由日志"规范

部分模块（典型：`AppDelegate.registerHotkey`）在解析 / 注册失败时刻意静默吞错（`try?`），不打 `print` 也不抛异常给上层。原因是这些路径在用户配置错误时会被频繁触发，自由日志会污染 Console；正确做法是把错误状态暴露在 Settings UI（如 Hotkey 输入框旁边的红色提示）。新增逻辑前先确认这条规范是否适用。

## 测试策略

- `SliceCoreTests`：业务逻辑全单测，期望覆盖率 ≥ 90%。
- `LLMProvidersTests`：用 `MockURLProtocol` 拦截网络，从 `Tests/LLMProvidersTests/Fixtures/` 喂 SSE 固件验证流式解码、`Retry-After`、429 重试。
- `SelectionCaptureTests`：`ClipboardSelectionSource` 通过注入 `PasteboardProtocol` + `CopyKeystrokeInvoking` 的 Fake 实现做单测；AX 路径无单测（依赖系统权限），靠手动验收。
- `HotkeyManagerTests`：只测 `Hotkey.parse` 等纯逻辑；Carbon 注册靠手动验收。
- `WindowingTests`：只测 `ScreenAwarePositioner` 这种纯算法；NSPanel 行为靠手动验收。
- `DesignSystemTests`：只测 token 常量、`ThemeManager` 状态切换等纯逻辑；SwiftUI 视图渲染靠手动验收。

新增依赖外部状态（系统权限、网络、剪贴板）的代码时，先抽 protocol 让生产实现走真实路径、测试注入 Fake，而不是直接在测试里 mock 系统 API。

## 配置与密钥的写入约定

- **新增 Provider 时，`apiKeyRef` 必须用 `keychain:<provider.id>` 形式**（见 `SettingsScene.addProvider()`）。这样 `SettingsViewModel.setAPIKey(_:for:)`（写）与 `ToolExecutor.execute`（读）通过 `Provider.keychainAccount` 解析出同一个 account。
- 修改 `Provider.apiKeyRef` 时不会自动迁移 Keychain 槽位；UI 层需要提示用户重新填写 API Key。
- 删除 Provider 时**不**主动清除 Keychain 槽位（`SettingsScene.deleteSelectedProvider`），保留以兼容"误删后重建同 id"。

## 文档与流程

- `docs/superpowers/specs/`：设计冻结文档（spec），跨 session 共享设计意图。
- `docs/superpowers/plans/`：实施计划（按 task 分解），跟踪 MVP 进度。
- 新增大功能前先查 spec / plan，避免与既有方向冲突。

## CI

- `.github/workflows/ci.yml`：每次 push/PR 跑 `swift build` + `swift test --parallel --enable-code-coverage` + `swiftlint lint --strict`（runs-on: macos-latest）。
- `.github/workflows/release.yml`：tag `v*` 触发，调用 `scripts/build-dmg.sh`、计算 SHA256、创建 GitHub Release（draft）。

## 风格 / 工具配置

- `.swiftlint.yml`：file_length warning 500 / error 700，function_body warning 40 / error 80；启用 `force_unwrapping`、`unused_import`、`sorted_imports`。仓库内已有的 `// swiftlint:disable:next force_unwrapping` 都附了注释说明为什么安全（如硬编码 URL）。
- `.swift-format`：4 空格缩进，行宽 120。
- 所有 public API 必须带 `///` 文档注释（`AllPublicDeclarationsHaveDocumentation` 关闭仅是为了避免私有 helper 被误报；公开声明仍要写）。
