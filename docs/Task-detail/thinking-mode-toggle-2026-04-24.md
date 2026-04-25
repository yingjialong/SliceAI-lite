# Task 26 · 思考模式切换功能（thinking mode toggle）

- **任务时间**：2026-04-24 起，2026-04-25 进入收尾阶段
- **分支**：`feat/thinking-mode-toggle`
- **设计文档**：[`docs/superpowers/specs/2026-04-24-thinking-mode-toggle-design.md`](../superpowers/specs/2026-04-24-thinking-mode-toggle-design.md)
- **实施计划**：[`docs/superpowers/plans/2026-04-24-thinking-mode-toggle.md`](../superpowers/plans/2026-04-24-thinking-mode-toggle.md)
- **当前状态**：代码层 Task 1–7 全部 commit；Task 8 自动化三件套（build / test / lint / xcodebuild）已通过；端到端真机 E2E 待手动验证

---

## 1. 任务背景与现状问题

### 1.1 现状问题

每个 `Tool` 固定指向一个 `providerId` + 一个 `modelId?`，请求时 `ChatRequest` 只透传 `model / messages / temperature / maxTokens`。无法让"翻译""润色"等同一工具在不同次执行时切换 thinking / non-thinking 模式，错失现代 reasoning 模型在难任务上的质量提升。

### 1.2 用户诉求

划词 → 选工具 → 默认非思考模式执行 → 结果面板顶部有切换按钮 → 切到思考模式 → 自动重跑一次 → 该工具下次默认就是思考模式（直到下次手动切回去）。即**按工具持久化 thinking 偏好**。

### 1.3 设计关键约束

- "思考模式"在 OpenAI 兼容协议下没有标准开关。业界双轨并存：
  - **切 model id**（DeepSeek V3 `deepseek-chat` ↔ `deepseek-reasoner`、字节 doubao 双 model）
  - **请求参数透传**（DeepSeek V4 `thinking`、Claude 4.6+ `thinking.adaptive`、Qwen3 `enable_thinking`、OpenAI o-series `reasoning_effort`、OpenRouter unified `reasoning`）
- 趋势是**混合模型**（同 model 用参数切）：Claude / Gemini / Qwen3 / DeepSeek V4 / OpenAI GPT-5 都已经走这条路，"切 model" 派只剩字节 doubao 与遗留 deepseek-v3
- OpenRouter 已对 OpenAI / Anthropic / Grok / DeepSeek 系全部 reasoning model 做了 unified `reasoning.effort` 接口，对 OpenRouter 用户用单一模板就覆盖所有 reasoning model

---

## 2. 实施方案（最终落地版）

### 2.1 架构核心

```
Provider.thinking: ProviderThinkingCapability?
  ├─ nil                  → 不支持 thinking 切换（结果面板不显示 toggle）
  ├─ .byModel             → 切 model id（Tool.thinkingModelId 必填）
  └─ .byParameter(JSON)   → 把 enable/disable JSON merge 到 request body root

Tool 新增字段：
  ├─ thinkingModelId: String?    // 仅 byModel 模式有意义
  └─ thinkingEnabled: Bool       // 用户上次切换偏好（默认 false）

ChatRequest 新增字段：
  └─ extraBody: [String: Any]?   // OpenAICompatibleProvider merge 进 body root
ChatChunk 新增字段：
  └─ reasoningDelta: String?     // SSE 解析时按 fallback chain 提取
```

SSE fallback chain：`delta.reasoning` (OpenRouter unified) → `delta.reasoning_content` (DeepSeek V4) → nil。**不绑定模板**，任何模板/直连都自动 work。

### 2.2 完整数据流

```
ResultPanel 用户点 thinking toggle
  ↓
SettingsViewModel.toggleThinking(toolId)
  ↓ atomic write 到 config.json
ResultPanel onRegenerate()
  ↓ AppDelegate.onToggleThinking 取消旧 streamTask、清空 panel
ToolExecutor.execute(tool, payload)
  ↓ 读最新 tool.thinkingEnabled × provider.thinking
  ├─ byModel + thinkingEnabled=true   → ChatRequest.model = tool.thinkingModelId
  ├─ byParameter + thinkingEnabled=true  → ChatRequest.extraBody = parse(enableBodyJSON)
  └─ byParameter + thinkingEnabled=false 且 disableBodyJSON 非 nil → 显式传 disable
  ↓
OpenAICompatibleProvider.stream(request)
  ↓ buildURLRequest 把 extraBody merge 进 body root（不覆盖既有字段）
  ↓ decodeChunk 提取 reasoningDelta
  ↓
ResultPanel
  ├─ 主 content 累积到 markdown 区
  └─ reasoningDelta 累积到 DisclosureGroup（"💭 思考过程"，默认折叠）
```

### 2.3 backward compatibility

- 全部新字段 optional / 有 default（`thinking: nil`、`thinkingEnabled: false`、`thinkingModelId: nil`、`extraBody: nil`、`reasoningDelta: nil`）
- `Configuration.currentSchemaVersion` **不 bump**，旧 JSON 加载新字段为 nil/false，老字段保留
- 旧 ResultPanel 在 `Provider.thinking == nil` 时不显示 toggle 按钮
- 旧 ChatRequest 调用方不传 extraBody，行为完全等同原版

### 2.4 默认 seed Provider 适配（2026-04-25 收尾）

`DefaultConfiguration.initial()` 从 1 个 Provider 扩到 3 个，全部预填 thinking 模板：

| Provider id | name | baseURL | defaultModel | thinking 模板 |
|-------------|------|---------|--------------|----------------|
| `openai-official` | OpenAI | `https://api.openai.com/v1` | `gpt-5` | `byParameter(reasoning_effort=medium ↔ minimal)` |
| `openrouter` | OpenRouter | `https://openrouter.ai/api/v1` | `openai/gpt-5` | `byParameter(reasoning.effort=medium ↔ none)` |
| `deepseek-v4` | DeepSeek V4 | `https://api.deepseek.com/v1` | `deepseek-chat` | `byParameter(thinking.type=enabled ↔ disabled)` |

**4 个内置工具仍然 default `providerId = openai-official`**——OpenAI 是最常见入口；其他两家作为预填模板，等用户在 Settings 主动把工具切到对应 provider id。

**JSON 字符串与 `SettingsUI/Thinking/ThinkingTemplate.swift` 的 `openAIReasoningEffort` / `openRouterUnified` / `deepSeekV4` case 字符精确一致**。`DefaultConfigurationTests.test_defaultConfig_providersThinkingPrefilled()` 守住这个不变量；不一致会导致 ProviderEditorView 打开默认 Provider 时 `ThinkingTemplate.match()` 错把模板识别成"自定义"，破坏开箱即用体验。

---

## 3. ToDoList（与 plan Task 1–8 对应）

### 已完成

- [x] **Task 1** SliceCore 数据模型（`Provider.thinking` / `Tool.thinkingModelId+thinkingEnabled` / `ChatRequest.extraBody` / `ChatChunk.reasoningDelta` / `ProviderThinkingCapability` enum）— commit `d7f1ed0`
- [x] **Task 2** `ToolExecutor` thinking 决策分支 — commit `60e031e`，错误类型修订 `07b8f91`（新增 `SliceError.configuration(.incompleteThinkingConfig)` 取代复用 `.invalidJSON`，UX 更准确）
- [x] **Task 3** `LLMProviders` extraBody merge + SSE reasoning fallback 解析 — commits `8ef9bad` + `8704c8a`
- [x] **Task 4** `SettingsViewModel.toggleThinking` + `ThinkingTemplate` 模板库（7 个 case：openRouterUnified / deepSeekV4 / anthropicAdaptive / anthropicBudget / openAIReasoningEffort / qwen3 / custom）— commits `d380830` + `52a9044`
- [x] **Task 5** `ProviderEditorView` thinking 折叠区（模式 Picker + 模板 Picker + 双 JSON 编辑器 + 实时校验）— commits `99939f8` + `7264ce9`
- [x] **Task 6** `ToolEditorView` 条件显示 `thinkingModelId` 字段（仅 byModel）— commits `3b2b97b` + `5414602`
- [x] **Task 7** `Windowing/ResultPanel` toggle 按钮 + 「💭 思考过程」DisclosureGroup + AppDelegate 桥接（`onToggleThinking` 取消旧 streamTask 后重 execute）— commits `9ad6873` + `4e1d619`
- [x] **Task 8 收尾 - 自动化** `swift build` / `swift test --parallel --enable-code-coverage`（123 用例全过）/ `swiftlint lint --strict`（0 violations）/ `xcodebuild ... build`（BUILD SUCCEEDED）
- [x] **Task 8 收尾 - 默认 seed Provider 适配** OpenAI / OpenRouter / DeepSeek V4 三家 seed Provider，全部预填 thinking 模板（本次 2026-04-25 新增）

### 待完成（手动 E2E + 远端）

- [ ] **Task 8 Step 4** Manual: backward compat（用旧 config.json 启动确认无崩溃，新字段缺省）
- [ ] **Task 8 Step 5** Manual: DeepSeek V4 byParameter 端到端（真机 API Key + reasoning_content 流式展示）
- [ ] **Task 8 Step 6** Manual: OpenRouter unified 端到端（真机 API Key + reasoning 流式展示）
- [ ] **Task 8 Step 7** Manual: byModel 模式（DeepSeek V3 双 model 或字节 doubao 双 model）
- [ ] **Task 8 Step 8** Manual: 错误路径（byModel 缺 thinkingModelId → `SliceError.configuration(.incompleteThinkingConfig)` 友好显示）
- [ ] **Task 8 Step 10** `git push` feat 分支至 origin（用户授权后执行）

---

## 4. 变动文件清单

### 新增

| Path | 用途 |
|------|------|
| `SliceAIKit/Sources/SliceCore/ProviderThinkingCapability.swift` | 两态 enum（byModel / byParameter）+ Codable 自动合成 |
| `SliceAIKit/Sources/SettingsUI/Thinking/ThinkingTemplate.swift` | 7 模板常量（含 displayName / description / enable+disable JSON） |
| `SliceAIKit/Sources/SettingsUI/Thinking/ProviderThinkingSectionView.swift` | Provider 编辑页 thinking SectionCard 子视图 |
| `SliceAIKit/Tests/SliceCoreTests/ProviderThinkingCapabilityTests.swift` | enum Codable round-trip |
| `SliceAIKit/Tests/SliceCoreTests/Fixtures/legacy-config-no-thinking.json` | 旧配置反序列化兼容 fixture |
| `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-openrouter-reasoning.txt` | OpenRouter `delta.reasoning` SSE fixture |
| `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-deepseek-reasoning-content.txt` | DeepSeek `delta.reasoning_content` SSE fixture |

### 修改

| Path | 改动概要 |
|------|----------|
| `SliceAIKit/Sources/SliceCore/Provider.swift` | 加 `thinking: ProviderThinkingCapability?` + `decodeIfPresent` |
| `SliceAIKit/Sources/SliceCore/Tool.swift` | 加 `thinkingModelId: String?` + `thinkingEnabled: Bool` + `decodeIfPresent` |
| `SliceAIKit/Sources/SliceCore/ChatTypes.swift` | `ChatRequest` 加 `extraBody: [String: Any]?`（去 Codable，`@unchecked Sendable`，自定义 Equatable）；`ChatChunk` 加 `reasoningDelta: String?` |
| `SliceAIKit/Sources/SliceCore/ToolExecutor.swift` | 决策分支：`tool.thinkingEnabled × provider.thinking` 决定切 model 还是塞 extraBody |
| `SliceAIKit/Sources/SliceCore/SliceError.swift` | 新增 `incompleteThinkingConfig` case（byModel 缺 thinkingModelId 的专属错误） |
| `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift` | seed Provider 从 1 → 3（OpenAI / OpenRouter / DeepSeek V4），全部预填 thinking 模板 |
| `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift` | `OpenAIStreamChunk.Choice.Delta` 加 `reasoning` / `reasoning_content` 两个 optional 字段 |
| `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift` | `buildURLRequest` merge `extraBody`（不覆盖既有字段）；`decodeChunk` fallback chain 提取 reasoning |
| `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift` | 新增 `toggleThinking(for:)` + `saveTools()` |
| `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift` | 嵌入 `ProviderThinkingSectionView` 子视图 |
| `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift` | 当 Provider.thinking == .byModel 时显示 `thinkingModelId` 输入框 |
| `SliceAIKit/Sources/Windowing/ResultPanel.swift` | Header brain.head.profile toggle 按钮 + 「💭 思考过程」DisclosureGroup |
| `SliceAIApp/AppDelegate.swift` | `onToggleThinking` 注入：cancel 旧 streamTask → execute 新 stream |
| `config.schema.json` | providers.items 加 `thinking`；tools.items 加 `thinkingModelId` + `thinkingEnabled` |
| `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift` | thinking 字段 round-trip + 旧 JSON 兼容 |
| `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift` | `extraBody` Equatable + `reasoningDelta` round-trip |
| `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift` | 新增 7 个 thinking 决策分支用例 |
| `SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift` | legacy-config-no-thinking 解码 |
| `SliceAIKit/Tests/SliceCoreTests/DefaultConfigurationTests.swift` | `hasOneProvider` → `hasThreeProviders` + `providersThinkingPrefilled` 字面值断言 |
| `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift` | extraBody merge + reasoning fallback |

---

## 5. 自检结果（Task 8 Step 1–3）

| 验证项 | 命令 | 结果 |
|--------|------|------|
| SwiftPM 构建 | `cd SliceAIKit && swift build` | exit 0 |
| SwiftPM 单测 | `cd SliceAIKit && swift test --parallel --enable-code-coverage` | exit 0，123 用例全通过 |
| SwiftLint | `swiftlint lint --strict` | exit 0，0 violations |
| Xcode App 构建 | `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` | exit 0，BUILD SUCCEEDED |
| seed Provider 字面一致性 | `DefaultConfigurationTests.test_defaultConfig_providersThinkingPrefilled` | PASS |

**自检无遗漏**。Task 8 Step 4–8 涉及真实 API Key 与人眼观察，不在本次自动化覆盖内。

---

## 6. 注意事项 / 已知风险

1. **覆盖安装升级用户不会自动获得新 seed Provider**。`ConfigurationStore.load()` 仅在 `config.json` 不存在时调用 `DefaultConfiguration.initial()`；老用户的 `config.json` 已经存在，新增的 OpenRouter / DeepSeek V4 Provider 不会自动注入。属于 KISS 选择（避免迁移代码 + 不覆盖用户编辑），但需在 README 升级说明中提示用户手动添加。
2. **`ProviderThinkingSectionView` 残留的 6 处 manual-E2E 调试 `print` 已在本次收尾清理**（与 commit `5414602` 清理 ToolEditorView 的口径一致）；`ProviderEditorView` 内 8 处 `print`（key load / save / test 路径）属于 thinking 任务**之前**就存在的老技术债，按 scope 控制原则不在本任务一并处理，留待独立 polish commit。
3. **`reasoning_effort=medium` 写死**。OpenAI / OpenRouter 模板均预填 medium，进阶用户改 raw JSON。这个取舍来自 spec §9 YAGNI 边界，不在本任务扩展。
4. **DeepSeek V4 `extra_body` vs root JSON 假定为 root**。spec §10.2 标注的"待 M2 真实请求验证"风险至今未通过真机消解，需在 Task 8 Step 5 端到端验收时核实。
5. **Anthropic 4.6 `adaptive` 在 OpenAI 兼容协议下的兼容性未验证**。本次 seed 不预置 Anthropic 直连 Provider（用户走 OpenRouter 间接调用 Anthropic 已能覆盖），降低了这条风险面，但 ThinkingTemplate 仍保留 anthropicAdaptive / anthropicBudget 模板供有 Anthropic 直连需求的用户手动选用。
6. **CHATRequest 不再 Codable**。这是为了 `extraBody: [String: Any]?` 的简洁权衡，已确认调用方未受影响（无外部 JSON 反序列化场景），但未来若引入 ChatRequest 持久化（如对话历史）需重新评估。
