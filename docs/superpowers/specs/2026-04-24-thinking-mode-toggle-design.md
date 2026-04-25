# 思考模式切换功能 — 设计文档

**状态**：Draft for review
**日期**：2026-04-24
**作者**：majiajun + Claude
**影响范围**：SliceCore / LLMProviders / SettingsUI / Windowing 4 个 SwiftPM target + Configuration JSON schema

---

## 1. 背景与动机

### 1.1 现状

每个工具（`Tool`）固定指向一个 `providerId` + 一个 `modelId?`，请求时 `ChatRequest` 只透传 `model / messages / temperature / maxTokens` 4 个字段。无法让同一个工具在不同次执行时切换 thinking / non-thinking 模式。

### 1.2 用户诉求

划词 → 选工具 → 默认非思考模式执行 → 结果面板顶部有切换按钮 → 切到思考模式 → 自动重跑一次 → 该工具下次默认就是思考模式（直到下次手动切回去）。即：**按工具持久化 thinking 偏好**。

### 1.3 关键约束（来自 brainstorming）

- **"思考模式"在 OpenAI 兼容协议下没有标准开关**：业界双轨并存
  - **切 model id**（DeepSeek V3 `deepseek-chat` ↔ `deepseek-reasoner`、字节双 model 如 doubao-pro / doubao-1-5-pro-thinking）
  - **请求参数透传**（Claude 4.6+ `thinking: {type: "adaptive"}`、DeepSeek V4 `thinking: {type: "enabled"}`、Qwen3 `enable_thinking`、OpenAI o-series `reasoning_effort`）
- **趋势是混合模型**（同一 model 用参数切）：Claude / Gemini / Qwen3 / DeepSeek V4 / OpenAI GPT-5 都已经走这条路。"切 model" 派只剩字节 doubao 双 model 和遗留 deepseek-v3
- **OpenRouter 已做了 unified reasoning 接口**（跨 OpenAI / Anthropic / Grok / DeepSeek 全标准化为 `reasoning: {effort: ...}` / `reasoning: {max_tokens: ...}`）—— 对 OpenRouter 用户用单一模板就覆盖所有 reasoning model

### 1.4 设计目标

- **双机制并存**：同时支持"切 model"和"参数透传"两种策略，覆盖所有现存和未来混合模型
- **Provider 配置一次复用**：thinking 能力声明在 Provider 层（设置一次），工具层只持有上次切换偏好
- **零 schema 破坏**：现有 `config.json` 加载不丢字段
- **避免 AnyCodable 复杂度**：byParameter 用 raw JSON string 存储，运行时 parse 为字典 merge 到 request body root
- **YAGNI 边界**：不做 thinking 模式下 strip temperature、不让用户在 UI 选 effort 等级（写死 medium，进阶用户改 raw JSON）

---

## 2. 设计概览

### 2.1 三类 Provider thinking 能力

```
Provider.thinking: ProviderThinkingCapability?
  ├─ nil                 → 不支持 thinking 切换（结果面板不显示 toggle 按钮）
  ├─ .byModel            → 通过切 model id 开关
  └─ .byParameter(json)  → 通过 request body root 透传 JSON 字段开关
```

### 2.2 Tool 层数据

```
Tool {
  modelId          // 默认（非思考）model id（已有字段）
  thinkingModelId  // 仅 byModel 模式有意义
  thinkingEnabled  // 用户上次切换偏好，默认 false
}
```

### 2.3 切换数据流

```
用户在 ResultPanel 点 toggle 按钮
  ↓
SettingsViewModel/ConfigurationStore.updateTool(toolId, thinkingEnabled: !current)
  ↓ atomic write 到 config.json
ResultPanel.onRegenerate()
  ↓ cancel 旧 stream, panel 清空
ToolExecutor.execute(tool, payload)
  ↓ 读取最新 tool.thinkingEnabled
  ↓ 查 Provider.thinking 决定怎么开
  ├─ byModel + thinkingEnabled=true   → ChatRequest.model = tool.thinkingModelId
  └─ byParameter + thinkingEnabled=true → ChatRequest.extraBody = parse(enableBodyJSON)
  ↓ OpenAICompatibleProvider.stream(request)
  ↓ SSE 流式返回，parse delta.reasoning / delta.reasoning_content → chunk.reasoningDelta
ResultPanel
  ├─ 主 content 累积到 markdown 区
  └─ reasoningDelta 累积到 DisclosureGroup（"💭 思考过程"，默认折叠）
```

---

## 3. Schema 改动

### 3.1 SliceCore — Provider 扩展

文件：`SliceAIKit/Sources/SliceCore/Configuration.swift`（Provider 定义所在）

```swift
public struct Provider: Sendable, Codable, Equatable {
    // existing fields: id, name, baseURL, apiKeyRef, defaultModel
    
    /// 该 Provider 支持的 thinking 切换机制；nil 表示不支持，结果面板不显示 toggle
    public var thinking: ProviderThinkingCapability?
}

/// Provider 声明的 thinking 切换机制
public enum ProviderThinkingCapability: Sendable, Codable, Equatable {
    /// 通过切换 model id 开/关 thinking（典型：DeepSeek V3、字节 doubao 双 model）
    /// Tool 必须配置 thinkingModelId 字段才能真正切换
    case byModel
    
    /// 通过 request body root 透传 JSON 字段开/关 thinking
    /// - enableBodyJSON: thinking=on 时要 merge 到 request body root 的 JSON
    /// - disableBodyJSON: thinking=off 时要 merge（nil 表示不传）
    /// 用 raw String 而不是 [String: AnyCodable] 是为了避开 Swift Codable 的 AnyCodable 痛点；
    /// 用户在 SettingsUI 直接面对 JSON 文本框，运行时 parse 为字典再 merge
    case byParameter(enableBodyJSON: String, disableBodyJSON: String?)
}
```

### 3.2 SliceCore — Tool 扩展

文件：`SliceAIKit/Sources/SliceCore/Tool.swift`

```swift
public struct Tool: Identifiable, Sendable, Codable, Equatable {
    // existing fields: id, name, icon, description, systemPrompt, userPrompt,
    //                   providerId, modelId, temperature, displayMode, variables, labelStyle
    
    /// 仅当所选 Provider.thinking == .byModel 时有意义。nil 时即便 thinkingEnabled=true
    /// 也不会切（ToolExecutor 会抛 SliceError.configuration）
    public var thinkingModelId: String?
    
    /// 用户上次切换的 thinking 偏好；默认 false（非思考）
    /// toggle 后立即持久化到 config.json
    public var thinkingEnabled: Bool
}
```

构造函数与 `init(from:)` Codable 实现需要给两个新字段加 default（`nil` / `false`），保证旧 JSON 反序列化不报错。

### 3.3 SliceCore — ChatRequest 扩展

文件：`SliceAIKit/Sources/SliceCore/ChatTypes.swift`

```swift
public struct ChatRequest: Sendable, Equatable {  // 注意：不再 Codable（见下方说明）
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?
    
    /// 由 Provider.byParameter 的 enable/disableBodyJSON parse 而来，在
    /// OpenAICompatibleProvider 序列化时 merge 到 request body root JSON
    public let extraBody: [String: Any]?
}
```

**关于 `Codable`**：`[String: Any]` 不能直接 Codable。两个选项：
- **A 我倾向**：把 ChatRequest 整体改为非 Codable，因为它本来就只在 LLMProviders 内部用（用户 / config 不直接 encode 它）。Equatable 用 `NSDictionary` 桥接比较 extraBody。
- B 备选：保留 ChatRequest Codable，extraBody 单独走 raw JSON String，OpenAICompatibleProvider 在 encode body 时拼字符串。

选 A：搜过代码，ChatRequest 没有从外部 JSON 反序列化的场景（用户配置都是 ChatMessage 之外的字段），去掉 Codable 不破坏调用方。

### 3.4 ToolExecutor 扩展

文件：`SliceAIKit/Sources/SliceCore/ToolExecutor.swift`

`execute(tool:payload:)` 内部决策逻辑增加：

```swift
let provider = ...  // 现有逻辑找到 Provider
var modelId = tool.modelId ?? provider.defaultModel
var extraBody: [String: Any]? = nil

if tool.thinkingEnabled, let thinking = provider.thinking {
    switch thinking {
    case .byModel:
        guard let alt = tool.thinkingModelId else {
            throw SliceError.configuration(.invalidJSON("工具未配置 thinking 模式 model id"))
        }
        modelId = alt
    case .byParameter(let enableJSON, _):
        extraBody = try parseJSON(enableJSON)  // 失败抛 SliceError.configuration
    }
} else if !tool.thinkingEnabled, let thinking = provider.thinking,
          case .byParameter(_, let disableJSON?) = thinking {
    // 非思考模式但模板有 disableBodyJSON：也要带（如 OpenRouter 显式 effort=none）
    extraBody = try parseJSON(disableJSON)
}

let request = ChatRequest(model: modelId, messages: ..., extraBody: extraBody)
```

### 3.5 LLMProviders — extraBody merge

文件：`SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift`

`stream(request:)` 内构造 HTTP body 的逻辑：

```swift
// 现有：把 ChatRequest 编码为字典
var bodyDict: [String: Any] = [
    "model": request.model,
    "messages": ...,
    "stream": true,
    ...
]
if let temp = request.temperature { bodyDict["temperature"] = temp }
if let max = request.maxTokens { bodyDict["max_tokens"] = max }

// 新增：merge extraBody（不覆盖现有字段，让 thinking 等新字段附加）
if let extra = request.extraBody {
    for (k, v) in extra where bodyDict[k] == nil {
        bodyDict[k] = v
    }
}

let body = try JSONSerialization.data(withJSONObject: bodyDict)
```

merge 策略：**extraBody 不覆盖 ChatRequest 已有字段**（防止用户在 enableBodyJSON 里写 `"model": "xxx"` 误改 model）。如果未来要支持覆盖，加 conflict 提示给用户。

### 3.6 LLMProviders — SSE reasoning 解析

文件：`SliceAIKit/Sources/LLMProviders/SSEDecoder.swift` 或同 target 内的 chunk parsing 逻辑

每个 SSE delta chunk 在提取 `delta.content` 之外，再按 fallback chain 提取 reasoning：

```swift
let reasoningDelta: String? = 
    delta["reasoning"] as? String          // OpenRouter unified
    ?? delta["reasoning_content"] as? String  // DeepSeek V4
    // 不绑定模板，任何模板/直连都自动 work（fallback chain）
```

`ChatStreamChunk` 加新字段：

```swift
public struct ChatStreamChunk: Sendable, Equatable {
    public let delta: String
    public let reasoningDelta: String?  // 新增
    public let finishReason: FinishReason?
}
```

### 3.7 backward compatibility

- 所有新字段 optional / 有 default
- `Configuration.currentSchemaVersion` **不 bump**（旧 JSON 加载新字段为 nil/false，不丢老字段）
- 旧 ResultPanel 不显示 toggle 按钮（Provider.thinking == nil 时不出按钮）
- 老 ChatRequest 调用方不传 extraBody，行为完全等同当前

---

## 4. byParameter 模板库（UI 常量）

模板**不进 schema**，是 SettingsUI 内部的 enum + 静态字符串常量。用户在 Provider 设置页选模板 → UI 自动填两个 textarea → 用户可微调 → 保存为 `byParameter(enableJSON, disableJSON)`。

### 4.1 模板列表

文件：`SliceAIKit/Sources/SettingsUI/Thinking/ThinkingTemplate.swift`（新建）

```swift
enum ProviderThinkingTemplate: String, CaseIterable, Identifiable {
    case openRouterUnified   // ⭐ 推荐 OpenRouter 用户首选（一个模板覆盖 OpenAI/Claude/Grok/DeepSeek 系所有 reasoning model）
    case deepSeekV4
    case anthropicAdaptive   // Claude 4.6+
    case anthropicBudget     // Claude 4.5 及以下
    case openAIReasoningEffort
    case qwen3
    case custom              // 用户手填
    
    var displayName: String { ... }
    var enableBodyJSON: String { ... }
    var disableBodyJSON: String? { ... }
}
```

### 4.2 各模板的 payload（写死 medium / 标准取值）

| 模板 | enableBodyJSON | disableBodyJSON |
|------|----------------|------------------|
| `openRouterUnified` | `{"reasoning": {"effort": "medium"}}` | `{"reasoning": {"effort": "none"}}` |
| `deepSeekV4` | `{"thinking": {"type": "enabled"}}` | `{"thinking": {"type": "disabled"}}` |
| `anthropicAdaptive` | `{"thinking": {"type": "adaptive"}}` | `null`（省略 thinking 字段即关闭） |
| `anthropicBudget` | `{"thinking": {"type": "enabled", "budget_tokens": 8000}}` | `null` |
| `openAIReasoningEffort` | `{"reasoning_effort": "medium"}` | `{"reasoning_effort": "minimal"}` |
| `qwen3` | `{"enable_thinking": true}` | `{"enable_thinking": false}` |
| `custom` | （空，用户填） | （空，用户填或留空） |

每个模板带 displayName（显示给用户）和注释说明适用模型/版本。

---

## 5. UI 设计

### 5.1 SettingsUI — Provider 配置页面新增

文件：`SliceAIKit/Sources/SettingsUI/Pages/ProvidersSettingsPage.swift`（已有）

每个 Provider 编辑区底部新增 "Thinking 切换" 折叠区：

```
[v] Thinking 切换
    模式: [无 / 切 model / 参数透传 ▾]
    
    （选"参数透传"时显示）：
    模板: [自定义 / OpenRouter 统一 / DeepSeek V4 / Anthropic 4.6+ / ... ▾]
    
    开启 thinking 时塞入 request body:
    ┌──────────────────────────────────────┐
    │ {"reasoning": {"effort": "medium"}}  │
    └──────────────────────────────────────┘
    
    关闭 thinking 时塞入 request body（可选）:
    ┌──────────────────────────────────────┐
    │ {"reasoning": {"effort": "none"}}    │
    └──────────────────────────────────────┘
    
    [JSON 校验通过 ✓]
```

- 模板下拉切换 → 自动填两个 textarea
- 离焦 / 保存时 JSON parse 校验，invalid 时 textarea 红框 + 阻止保存
- 选"切 model"时不显示 textarea，提示"请在工具配置里填写 thinking 模式的 model id"

### 5.2 SettingsUI — Tool 配置页面新增

文件：`SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`（已有）

每个工具编辑区根据所选 Provider 的 thinking 类型动态显示：

- Provider.thinking == nil：不显示任何 thinking 字段
- Provider.thinking == .byModel：显示一个 "Thinking 模式 model id" 输入框
- Provider.thinking == .byParameter：显示一行只读说明 "该 Provider 已配置参数透传，无需在工具层配置"

### 5.3 Windowing/ResultPanel — toggle 按钮

文件：`SliceAIKit/Sources/Windowing/ResultPanel.swift`

顶部 header（现有 toolName / model / pin / regenerate / close 控件）右侧加一个紧凑按钮：

```
SF Symbol: "brain.head.profile"
状态:
  - thinking ON  : tint = accent color (purple), filled
  - thinking OFF : tint = secondary, outline
```

显示条件（任一不满足则隐藏按钮）：
- `tool.providerId` 对应的 Provider.thinking != nil
- 如果是 byModel：tool.thinkingModelId != nil

点击行为：
1. 立即更新 UI（按钮状态翻转，无需等回包）
2. `await settingsViewModel.toggleThinking(for: tool.id)` → 持久化 config.json
3. 调用 `onRegenerate()`（已有 closure，cancel 旧 stream + 重新 execute）
4. ResultPanel 清空主 content + reasoning 区，stream 新结果

### 5.4 Windowing/ResultPanel — Reasoning disclosure

主 content 区上方新增 SwiftUI `DisclosureGroup`：

```
[> 💭 思考过程]   ← 默认折叠
   （展开后）：
   ┌─────────────────────────────────┐
   │ 用 secondary color + 11pt font  │
   │ 流式累积 reasoningDelta 内容    │
   └─────────────────────────────────┘
```

- 仅当 `accumulatedReasoning.count > 0` 时出现
- 默认折叠（避免遮挡主 content）
- 用户主动展开后保持展开状态（不自动 collapse）
- 字体：DesignSystem 的 `Typography.caption` + `Color.secondary`

---

## 6. 错误处理

| 场景 | 处理 |
|------|------|
| `byModel` + `thinkingEnabled=true` 但 `thinkingModelId == nil` | ToolExecutor 抛 `SliceError.configuration(.invalidJSON("工具未配置 thinking 模式 model id"))`，ResultPanel 通过 `fail(with:onRetry:onOpenSettings:)` 显示错误 + "去设置" 按钮 |
| `byParameter` 的 `enableBodyJSON` 不是合法 JSON | (a) Settings 保存前 JSON parse 校验，invalid 阻止保存 (b) 运行时 ToolExecutor 防御性 parse，失败抛 `SliceError.configuration(.invalidJSON(...))` |
| API 报 model 不支持 thinking（4xx） | 已有 `SliceError.provider` 链路兜底，ResultPanel 显示 provider 错误 |
| toggle 后新 stream 启动失败 | Panel 显示新错误，`tool.thinkingEnabled` **不回滚**（保留用户主观选择，可再点切回） |
| reasoningDelta 为乱码 / 极长 | 不做特殊处理（fallback 到不显示），按 markdown 普通文本累积 |

---

## 7. 测试策略

### 7.1 单测覆盖（必须）

`SliceAIKit/Tests/SliceCoreTests/`：

- `ToolExecutorTests`：
  - `test_execute_byModel_thinkingEnabled_usesThinkingModelId`
  - `test_execute_byModel_thinkingEnabled_noThinkingModelId_throws`
  - `test_execute_byParameter_thinkingEnabled_setsExtraBody`
  - `test_execute_byParameter_thinkingDisabled_withDisableBody_setsExtraBody`
  - `test_execute_byParameter_thinkingDisabled_noDisableBody_extraBodyNil`
  - `test_execute_invalidEnableBodyJSON_throws`
  - `test_execute_providerThinkingNil_ignoresThinkingEnabled`

- `ConfigurationStoreTests`：
  - `test_loadOldJSON_thinkingFieldsDefaultToNilFalse`（喂 fixture：不含 thinking 字段的旧 config.json）
  - `test_roundTrip_byModelProvider`
  - `test_roundTrip_byParameterProvider`
  - `test_roundTrip_toolWithThinkingFields`

`SliceAIKit/Tests/LLMProvidersTests/`：

- `OpenAICompatibleProviderTests`：
  - `test_extraBody_mergedToRootBody`（fixture：ChatRequest 带 extraBody，verify 发出的 HTTP body 包含 extraBody 字段）
  - `test_extraBody_doesNotOverrideExistingFields`（防御性：用户 extraBody 写 model 不应覆盖 ChatRequest.model）
- `SSEDecoderTests`（新建或扩现有）：
  - `test_parse_chunkWithReasoningField_extractsToReasoningDelta`（OpenRouter 风格 fixture）
  - `test_parse_chunkWithReasoningContent_extractsToReasoningDelta`（DeepSeek 风格 fixture）
  - `test_parse_chunkWithoutReasoning_reasoningDeltaIsNil`

### 7.2 手动验证（无单测）

- SettingsUI 模板下拉切换正确填充 textarea
- SettingsUI invalid JSON 阻止保存（红框反馈）
- ResultPanel toggle 按钮在 Provider.thinking == nil 时不出现
- ResultPanel toggle 按钮点击后正确切换 + 重跑
- ResultPanel reasoning DisclosureGroup 默认折叠 / 展开后正确流式累积
- thinking 切换持久化：重启 app 后默认值仍是上次切的状态

### 7.3 端到端冒烟（用户自行验收）

- DeepSeek V4 真实 API：申请 deepseek-v4-pro 模型，配 byParameter + DeepSeek V4 模板，划词 → 切换 → reasoning 内容流式展示
- OpenRouter Anthropic：配 byParameter + OpenRouter 模板，划词 → 切换 → reasoning 内容流式展示

---

## 8. 工作量切割与里程碑

| Milestone | 范围 | 工作量 | 可独立合并 |
|-----------|------|--------|-----------|
| **M1** | SliceCore schema 改动（Provider/Tool/ChatRequest/ToolExecutor）+ 单测 | 0.5 天 | ✓ |
| **M2** | LLMProviders extraBody merge + SSE reasoning parse + 单测 | 0.5 天 | ✓ |
| **M3** | SettingsUI Provider 配置 UI（thinking 折叠区 + 模板下拉） | 0.5 天 | 依赖 M1 |
| **M4** | SettingsUI Tool 配置 UI（动态字段） | 0.5 天 | 依赖 M1 |
| **M5** | Windowing/ResultPanel toggle 按钮 + reasoning DisclosureGroup | 1 天 | 依赖 M1 + M2 |
| **M6** | 端到端手动验证 + bug fix | 0.5-1 天 | 依赖 M1-M5 |
| **合计** | | **3.5-4 天** | |

每个 M 独立提交一个 commit，方便 review 和 rollback。

---

## 9. 不在范围内（YAGNI 边界）

明确**不做**的事，避免 scope creep：

- **thinking 模式下自动 strip temperature / top_p**：让 API silently ignore 即可（DeepSeek V4 / Anthropic thinking 都不报错）
- **Provider 配置 UI 暴露 effort 等级下拉**：模板写死 medium，进阶用户改 raw JSON
- **支持 Anthropic structured `thinking` blocks 响应**：Anthropic 原生 API 在 stream response 里 thinking 是结构化 content blocks 而不是 simple delta string；本 spec 仅适配通过 OpenAI 兼容接口的 thinking 字段（OpenRouter 转译过的，或 DeepSeek `reasoning_content`）
- **Tool 之间共享 thinking 偏好**：每个 tool 各自记忆，不做 group
- **划词触发时检测 model 是否支持 thinking 而 fail-fast**：只在用户主动切换时校验
- **历史 reasoning 内容持久化**：每次 panel 关闭即丢失（reasoning 只是当前 result 的一部分）

---

## 10. 风险与决策记录

### 10.1 关键决策

- **byParameter 用 raw JSON 而不是 typed struct / AnyCodable**：避开 Swift Codable 复杂度，用户配置直接面对 JSON。代价：用户要懂 JSON 语法
- **OpenRouter 模板作为推荐首选**：因 OpenRouter 已统一接口，覆盖最广。但 OpenRouter 的 reasoning 在某些模型上 [silently dropped](https://medium.com/@fhorvat90/i-tested-reasoning-tokens-on-5-llms-via-openrouter-most-models-silently-drop-them-b8071b5d857d)，spec 不处理（让模型自己决定）
- **disableBodyJSON 可选**：Anthropic adaptive / budget 的"关闭" = 省略字段；OpenRouter / DeepSeek / OpenAI 的"关闭" = 显式传值。设计 disableBodyJSON 为 Optional<String> 兼容两种模式
- **ChatRequest 去掉 Codable**：换取 extraBody 用 `[String: Any]` 的简洁性，调用方未受影响

### 10.2 已知风险

- **DeepSeek V4 `extra_body` vs root JSON**：官方 docs 用 OpenAI Python SDK 的 `extra_body=` 描述，实际 raw HTTP 是 root JSON 字段。需要在 M2 阶段用真实请求 verify
- **Anthropic 4.6+ adaptive 在 OpenAI 兼容协议上的兼容性**：Anthropic 原生 API 接受 `thinking: {type: "adaptive"}`，OpenRouter 应该转译，但**直连 Anthropic 通过 OpenAI 兼容 wrapper 是否 work** 待验证
- **新模板的快速迭代**：未来出现新厂家时需要更新 ProviderThinkingTemplate enum；这是 source 改动，不是配置改动。建议每季度 review 一次模板库

---

## 附录 A：各 provider 当前 SSE chunk 中 reasoning 字段位置

| Provider | chunk JSON 路径 | 字段名 |
|----------|----------------|--------|
| OpenRouter（任何 model） | `choices[0].delta.reasoning` | string |
| DeepSeek V4 直连 | `choices[0].delta.reasoning_content` | string |
| Anthropic 直连（OpenAI 兼容 wrapper） | 待验证（M2 阶段） | 待验证 |
| OpenAI o-series 直连 | 不在 SSE delta 暴露 reasoning（仅在 final response 的 reasoning summary）；不支持本 spec 的流式 reasoning UI | — |

fallback 顺序：`reasoning` → `reasoning_content` → nil。

---

## 附录 B：参考资料

- [OpenRouter Reasoning Tokens (Unified)](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
- [DeepSeek V4 Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode)
- [Anthropic Claude Extended/Adaptive Thinking](https://docs.claude.com/en/docs/build-with-claude/extended-thinking)
- [OpenAI Reasoning Models](https://platform.openai.com/docs/guides/reasoning)
- [DeepSeek V4 Preview Release Notes (2026-04-24)](https://api-docs.deepseek.com/news/news260424)
