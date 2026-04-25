# Thinking Mode Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-tool thinking-mode toggle: result panel shows a brain button when the tool's provider declares a thinking capability; clicking it persists the preference, cancels the current stream, and re-runs in the new mode. Reasoning text streamed alongside the answer is rendered in a collapsible disclosure.

**Architecture:** Two thinking-switch mechanisms coexist (Provider-declared): `byModel` (swap model id, e.g. DeepSeek V3 / ByteDance dual-model) and `byParameter` (raw JSON merged into request body root, e.g. OpenRouter unified `reasoning`, DeepSeek V4 `thinking.type`, Claude 4.6+ `thinking.adaptive`, Qwen3 `enable_thinking`, OpenAI `reasoning_effort`). Tool holds the per-tool `thinkingEnabled` preference. ChatRequest gains a non-Codable `extraBody [String: Any]?` merged into request body root by OpenAICompatibleProvider. ChatChunk gains `reasoningDelta String?` extracted via fallback chain (`delta.reasoning` → `delta.reasoning_content` → nil) so any vendor template works automatically.

**Tech Stack:** Swift 6.0 strict concurrency, SwiftPM, SwiftUI on macOS 14+, XCTest, MockURLProtocol for HTTP fixtures, AsyncThrowingStream for SSE.

**Spec reference:** `docs/superpowers/specs/2026-04-24-thinking-mode-toggle-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `SliceAIKit/Sources/SliceCore/ProviderThinkingCapability.swift` | The two-case enum declaring how a Provider switches thinking |
| `SliceAIKit/Sources/SettingsUI/Thinking/ThinkingTemplate.swift` | UI-only enum + payload constants for byParameter templates |
| `SliceAIKit/Tests/SliceCoreTests/ProviderThinkingCapabilityTests.swift` | Codable round-trip for the new enum |
| `SliceAIKit/Tests/SliceCoreTests/Fixtures/legacy-config-no-thinking.json` | Backward-compat fixture (old config.json without thinking fields) |
| `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-openrouter-reasoning.txt` | OpenRouter-style SSE chunks with `delta.reasoning` |
| `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-deepseek-reasoning-content.txt` | DeepSeek-style SSE chunks with `delta.reasoning_content` |

### Modified files

| Path | Change |
|------|--------|
| `SliceAIKit/Sources/SliceCore/Provider.swift` | Add `thinking: ProviderThinkingCapability?` field + Codable `decodeIfPresent` for backward compat |
| `SliceAIKit/Sources/SliceCore/Tool.swift` | Add `thinkingModelId: String?` + `thinkingEnabled: Bool` (default false) + Codable `decodeIfPresent` |
| `SliceAIKit/Sources/SliceCore/ChatTypes.swift` | Add `extraBody: [String: Any]?` to ChatRequest (excluded from Codable, custom Equatable, `@unchecked Sendable`); add `reasoningDelta: String?` to ChatChunk |
| `SliceAIKit/Sources/SliceCore/ToolExecutor.swift` | After picking model id, branch on `tool.thinkingEnabled` × `provider.thinking` to set `modelId` or `extraBody` |
| `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift` | Add optional `reasoning` and `reasoning_content` fields to `OpenAIStreamChunk.Choice.Delta` |
| `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift` | Merge `request.extraBody` into request body root in `buildURLRequest`; extract reasoning via fallback chain in `decodeChunk` |
| `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift` | Add `toggleThinking(for: Tool.ID)` and `saveTools()` |
| `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift` | Add thinking section (mode picker + template picker + JSON textareas + validation) |
| `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift` | Conditionally show "Thinking model id" field when chosen Provider's thinking == .byModel |
| `SliceAIKit/Sources/Windowing/ResultPanel.swift` | Header: brain.head.profile toggle button (visible-when-Provider.thinking-non-nil); content top: collapsible "💭 思考过程" DisclosureGroup; accumulate `chunk.reasoningDelta` |
| `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift` | Extend with thinking-fields round-trip + backward compat |
| `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift` | Extend with `extraBody` Equatable behavior + `reasoningDelta` round-trip |
| `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift` | Add 7 new tests covering byModel/byParameter combinations |
| `SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift` | Add legacy-config-no-thinking decoding test |
| `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift` | Add extraBody merge tests + reasoning fallback tests |

---

## Task 1: SliceCore data model — Provider, Tool, ChatTypes

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ProviderThinkingCapability.swift`
- Modify: `SliceAIKit/Sources/SliceCore/Provider.swift`
- Modify: `SliceAIKit/Sources/SliceCore/Tool.swift`
- Modify: `SliceAIKit/Sources/SliceCore/ChatTypes.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ProviderThinkingCapabilityTests.swift`
- Modify: `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift`
- Modify: `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift`

### Step 1: Write failing test for ProviderThinkingCapability Codable

- [x] Create `SliceAIKit/Tests/SliceCoreTests/ProviderThinkingCapabilityTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ProviderThinkingCapabilityTests: XCTestCase {

    /// 验证 byModel case 的 Codable round-trip
    func test_byModel_codableRoundTrip() throws {
        let original = ProviderThinkingCapability.byModel
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderThinkingCapability.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    /// 验证 byParameter case 含 enable + nil disable 的 round-trip
    func test_byParameter_nilDisable_codableRoundTrip() throws {
        let original = ProviderThinkingCapability.byParameter(
            enableBodyJSON: #"{"thinking":{"type":"enabled"}}"#,
            disableBodyJSON: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderThinkingCapability.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    /// 验证 byParameter case 含 enable + 显式 disable 的 round-trip
    func test_byParameter_withDisable_codableRoundTrip() throws {
        let original = ProviderThinkingCapability.byParameter(
            enableBodyJSON: #"{"reasoning":{"effort":"medium"}}"#,
            disableBodyJSON: #"{"reasoning":{"effort":"none"}}"#
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderThinkingCapability.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
```

### Step 2: Run tests to verify failure

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --filter SliceCoreTests.ProviderThinkingCapabilityTests`

Expected: compilation error "no such type 'ProviderThinkingCapability'"

### Step 3: Implement ProviderThinkingCapability enum

- [x] Create `SliceAIKit/Sources/SliceCore/ProviderThinkingCapability.swift`:

```swift
import Foundation

/// Provider 声明的 thinking 切换机制
///
/// 设计要点：
///   - 两种机制并存以覆盖现存与未来所有混合模型
///   - byParameter 用 raw JSON 字符串存储而不是 typed struct，避开 Swift Codable
///     的 AnyCodable 复杂度；用户在 SettingsUI 直接面对 JSON 文本框
///   - disableBodyJSON 设计为 Optional：Anthropic adaptive / budget 的"关闭"=
///     省略 thinking 字段，OpenRouter / DeepSeek V4 的"关闭"= 显式传值
public enum ProviderThinkingCapability: Sendable, Codable, Equatable {
    /// 通过切换 model id 开关（典型：DeepSeek V3、字节 doubao 双 model）
    /// Tool 必须配置 thinkingModelId 才能真正切换
    case byModel

    /// 通过 request body root 透传 JSON 字段开关
    /// - enableBodyJSON: thinking=on 时 merge 到 request body root 的 JSON 字符串
    /// - disableBodyJSON: thinking=off 时 merge（nil 表示不传，等同省略字段）
    case byParameter(enableBodyJSON: String, disableBodyJSON: String?)
}
```

Note: Swift 编译器自动合成的 Codable 对 enum-with-associated-values 会生成嵌套 JSON 形如 `{"byModel": {}}` 或 `{"byParameter": {"enableBodyJSON": "...", "disableBodyJSON": "..."}}`，符合预期。

### Step 4: Run tests to verify pass

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --filter SliceCoreTests.ProviderThinkingCapabilityTests`

Expected: 3 tests pass.

### Step 5: Add Provider.thinking field with backward-compat decode

- [x] Modify `SliceAIKit/Sources/SliceCore/Provider.swift` — replace the entire struct body with:

```swift
public struct Provider: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var apiKeyRef: String     // 如 "keychain:openai-official"
    public var defaultModel: String
    /// 该 Provider 支持的 thinking 切换机制；nil 表示不支持，结果面板不显示 toggle
    public var thinking: ProviderThinkingCapability?

    /// 构造 Provider 配置
    /// - Parameters:
    ///   - id: Provider 唯一标识（如 "openai"）
    ///   - name: 显示名称（如 "OpenAI"）
    ///   - baseURL: API 基础地址
    ///   - apiKeyRef: Keychain 引用字符串，用于懒加载真实密钥
    ///   - defaultModel: 默认模型标识，Tool 未指定 modelId 时使用
    ///   - thinking: 该 Provider 的 thinking 切换机制，nil = 不支持
    public init(id: String, name: String, baseURL: URL,
                apiKeyRef: String, defaultModel: String,
                thinking: ProviderThinkingCapability? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.defaultModel = defaultModel
        self.thinking = thinking
    }

    /// JSON 字段名映射，集中管理所有 key
    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKeyRef, defaultModel, thinking
    }

    /// 自定义 decode：thinking 使用 decodeIfPresent 保证向后兼容
    ///
    /// 旧版 config.json 不含 thinking 字段，解码时回落到 nil（不支持），
    /// 避免因缺字段抛 DecodingError。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decode(URL.self, forKey: .baseURL)
        self.apiKeyRef = try container.decode(String.self, forKey: .apiKeyRef)
        self.defaultModel = try container.decode(String.self, forKey: .defaultModel)
        self.thinking = try container.decodeIfPresent(
            ProviderThinkingCapability.self, forKey: .thinking
        )
    }

    /// apiKeyRef 使用的 scheme 前缀；未来扩展 env: / file: 时在此枚举
    public static let keychainRefPrefix = "keychain:"

    /// 解析 apiKeyRef 得到 Keychain 中的 account 名；非 keychain: 前缀返回 nil
    public var keychainAccount: String? {
        guard apiKeyRef.hasPrefix(Self.keychainRefPrefix) else { return nil }
        return String(apiKeyRef.dropFirst(Self.keychainRefPrefix.count))
    }
}
```

### Step 6: Add Tool.thinkingModelId + Tool.thinkingEnabled with backward-compat decode

- [x] Modify `SliceAIKit/Sources/SliceCore/Tool.swift` — change `public struct Tool` to:

  - Add two stored properties after `labelStyle`:
    ```swift
    /// 仅当所选 Provider.thinking == .byModel 时有意义；nil + thinkingEnabled=true
    /// 时 ToolExecutor 会抛 SliceError.configuration
    public var thinkingModelId: String?

    /// 用户上次切换的 thinking 偏好；默认 false（非思考）
    /// toggle 后立即持久化到 config.json
    public var thinkingEnabled: Bool
    ```

  - Update `init` signature (after `labelStyle: ToolLabelStyle = .icon` add):
    ```swift
    thinkingModelId: String? = nil,
    thinkingEnabled: Bool = false
    ```
    and assign in body:
    ```swift
    self.thinkingModelId = thinkingModelId
    self.thinkingEnabled = thinkingEnabled
    ```

  - Add cases to `CodingKeys`:
    ```swift
    case thinkingModelId, thinkingEnabled
    ```

  - In `init(from decoder:)` after the labelStyle line, add:
    ```swift
    self.thinkingModelId = try container.decodeIfPresent(String.self, forKey: .thinkingModelId)
    self.thinkingEnabled = try container.decodeIfPresent(Bool.self, forKey: .thinkingEnabled) ?? false
    ```

### Step 7: Write failing test for Tool backward-compat decode

- [x] Modify `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift` — add at end of class:

```swift
/// 旧版 JSON 不含 thinkingModelId / thinkingEnabled 时应解码成 nil / false
func test_toolDecode_legacyJSON_thinkingFieldsDefaultToNilFalse() throws {
    let legacyJSON = """
    {
      "id": "summary",
      "name": "Summary",
      "icon": "doc.text",
      "userPrompt": "Summarize: {{selection}}",
      "providerId": "openai",
      "displayMode": "window",
      "variables": {}
    }
    """.data(using: .utf8)!
    let tool = try JSONDecoder().decode(Tool.self, from: legacyJSON)
    XCTAssertNil(tool.thinkingModelId)
    XCTAssertFalse(tool.thinkingEnabled)
}

/// 新版 JSON 含 thinkingModelId + thinkingEnabled 时应正确解码
func test_toolDecode_newJSON_thinkingFieldsRoundTrip() throws {
    let newJSON = """
    {
      "id": "summary",
      "name": "Summary",
      "icon": "doc.text",
      "userPrompt": "Summarize: {{selection}}",
      "providerId": "deepseek",
      "modelId": "deepseek-chat",
      "displayMode": "window",
      "variables": {},
      "thinkingModelId": "deepseek-reasoner",
      "thinkingEnabled": true
    }
    """.data(using: .utf8)!
    let tool = try JSONDecoder().decode(Tool.self, from: newJSON)
    XCTAssertEqual(tool.thinkingModelId, "deepseek-reasoner")
    XCTAssertTrue(tool.thinkingEnabled)
}
```

### Step 8: Run Tool tests

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --filter SliceCoreTests.ToolTests`

Expected: existing tests still pass + 2 new tests pass.

### Step 9: Add ChatRequest.extraBody and ChatChunk.reasoningDelta

- [x] Modify `SliceAIKit/Sources/SliceCore/ChatTypes.swift` — replace ChatRequest struct with:

```swift
/// 聊天请求
/// nil 的 temperature / maxTokens 会被序列化省略，保持服务端默认
///
/// `extraBody` 是非 Codable 的运行时字段，由 Provider.byParameter 的 enable/
/// disableBodyJSON parse 而来。OpenAICompatibleProvider 在序列化 body 时手动
/// merge 进 root JSON。该字段不通过 Codable 序列化，避免 AnyCodable 痛点。
///
/// 标记为 `@unchecked Sendable` 因为 `[String: Any]` 不是天然 Sendable，
/// 但运行时只在 actor (ToolExecutor) 内构造、value-type 传递不会跨 actor 共享可变状态。
public struct ChatRequest: @unchecked Sendable, Codable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?
    public let extraBody: [String: Any]?

    /// 构造聊天请求
    /// - Parameters:
    ///   - model: 模型标识
    ///   - messages: 历史消息数组
    ///   - temperature: 采样温度，nil 时沿用服务端默认
    ///   - maxTokens: 生成最大 token 数，nil 时沿用服务端默认
    ///   - extraBody: 额外要 merge 到 request body root 的字段；nil 时不 merge
    public init(model: String, messages: [ChatMessage],
                temperature: Double? = nil, maxTokens: Int? = nil,
                extraBody: [String: Any]? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.extraBody = extraBody
    }

    /// CodingKeys 不含 extraBody，意味着 JSONEncoder 不会编码它，
    /// 也不会从 JSON 反序列化它。extraBody 只在 OpenAICompatibleProvider
    /// 内部访问，merge 进 body 时手动处理。
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// ChatRequest Equatable：extraBody 用 NSDictionary 桥接比较
extension ChatRequest: Equatable {
    public static func == (lhs: ChatRequest, rhs: ChatRequest) -> Bool {
        lhs.model == rhs.model
            && lhs.messages == rhs.messages
            && lhs.temperature == rhs.temperature
            && lhs.maxTokens == rhs.maxTokens
            && (lhs.extraBody as NSDictionary?) == (rhs.extraBody as NSDictionary?)
    }
}
```

Then replace ChatChunk struct with:

```swift
/// 流式 chunk（delta 为增量文本，finishReason 仅在最后一个 chunk 非 nil）
/// 不声明 Codable：仅由 SSE 解码器生产，不会作为整体通过网络发送
public struct ChatChunk: Sendable, Equatable {
    public let delta: String
    /// 主推理过程的增量文本（OpenRouter `delta.reasoning` /
    /// DeepSeek `delta.reasoning_content` 等的 fallback 提取）
    /// 为 nil 表示该 chunk 没有 reasoning 内容（兼容非 thinking 模型）
    public let reasoningDelta: String?
    public let finishReason: FinishReason?

    /// 构造流式响应块
    /// - Parameters:
    ///   - delta: 本次主内容增量文本
    ///   - reasoningDelta: 本次推理过程增量文本，无则传 nil
    ///   - finishReason: 仅最后一个 chunk 非 nil
    public init(delta: String, reasoningDelta: String? = nil,
                finishReason: FinishReason? = nil) {
        self.delta = delta
        self.reasoningDelta = reasoningDelta
        self.finishReason = finishReason
    }
}
```

### Step 10: Write failing tests for ChatRequest extraBody Equatable + ChatChunk reasoningDelta

- [x] Modify `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift` — add at end of class:

```swift
/// extraBody 内容相同时两个 ChatRequest 应相等（NSDictionary 桥接比较）
func test_chatRequest_extraBodyEqual_whenContentsMatch() {
    let a = ChatRequest(model: "m", messages: [],
                        extraBody: ["thinking": ["type": "enabled"]])
    let b = ChatRequest(model: "m", messages: [],
                        extraBody: ["thinking": ["type": "enabled"]])
    XCTAssertEqual(a, b)
}

/// extraBody 内容不同时两个 ChatRequest 应不相等
func test_chatRequest_extraBodyDiffer_notEqual() {
    let a = ChatRequest(model: "m", messages: [],
                        extraBody: ["thinking": ["type": "enabled"]])
    let b = ChatRequest(model: "m", messages: [],
                        extraBody: ["thinking": ["type": "disabled"]])
    XCTAssertNotEqual(a, b)
}

/// 一边 nil 一边有内容的 extraBody 应不相等
func test_chatRequest_extraBodyOneNil_notEqual() {
    let a = ChatRequest(model: "m", messages: [], extraBody: nil)
    let b = ChatRequest(model: "m", messages: [], extraBody: ["foo": 1])
    XCTAssertNotEqual(a, b)
}

/// extraBody 不参与 Codable：encode 后的 JSON 不含 extraBody 字段
func test_chatRequest_extraBody_notInJSONOutput() throws {
    let req = ChatRequest(model: "m", messages: [],
                          extraBody: ["thinking": ["type": "enabled"]])
    let data = try JSONEncoder().encode(req)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertNotNil(json)
    XCTAssertNil(json?["extraBody"])
    XCTAssertNil(json?["thinking"])  // 也不会泄漏到 root
}

/// ChatChunk 的 reasoningDelta 字段在构造时正确赋值
func test_chatChunk_reasoningDelta_init() {
    let chunk = ChatChunk(delta: "answer", reasoningDelta: "thinking", finishReason: nil)
    XCTAssertEqual(chunk.delta, "answer")
    XCTAssertEqual(chunk.reasoningDelta, "thinking")
}

/// 默认参数下 reasoningDelta 为 nil（兼容非 thinking 模型）
func test_chatChunk_reasoningDelta_defaultsNil() {
    let chunk = ChatChunk(delta: "answer")
    XCTAssertNil(chunk.reasoningDelta)
}
```

### Step 11: Run all SliceCore tests

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --filter SliceCoreTests --parallel`

Expected: all existing tests still pass + new tests pass. **No existing test should break.** If any existing test breaks (e.g. `Tool.init` call sites missing the new `thinkingModelId` / `thinkingEnabled` defaults), the fix is to use the default-arg form (parameters have defaults so call sites need no change).

### Step 12: Commit

- [x] Run:

```bash
git -C /Users/majiajun/workspace/SliceAI-lite add \
  SliceAIKit/Sources/SliceCore/ProviderThinkingCapability.swift \
  SliceAIKit/Sources/SliceCore/Provider.swift \
  SliceAIKit/Sources/SliceCore/Tool.swift \
  SliceAIKit/Sources/SliceCore/ChatTypes.swift \
  SliceAIKit/Tests/SliceCoreTests/ProviderThinkingCapabilityTests.swift \
  SliceAIKit/Tests/SliceCoreTests/ToolTests.swift \
  SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift

git -C /Users/majiajun/workspace/SliceAI-lite commit -m "feat(slicecore): add thinking-mode data model

- ProviderThinkingCapability enum (.byModel | .byParameter)
- Provider.thinking optional field, decodeIfPresent for backward compat
- Tool.thinkingModelId / Tool.thinkingEnabled, decodeIfPresent
- ChatRequest.extraBody [String: Any]? excluded from Codable, custom Equatable
- ChatChunk.reasoningDelta optional

All new fields default to nil/false; old config.json loads unchanged."
```

---

## Task 2: SliceCore — ToolExecutor decision logic

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/ToolExecutor.swift`
- Modify: `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift`

### Step 1: Write failing tests for thinking-mode decision branches

- [x] Modify `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift` — add helper plus 7 new tests:

```swift
// MARK: - Thinking mode tests

/// 用一个能拦截 ChatRequest 的 spy provider 来 verify ToolExecutor 决策
/// （生产代码里 LLMProvider 来自 LLMProviders target，这里复用现有 spy 模式）
private final class CapturingProvider: LLMProvider, @unchecked Sendable {
    var captured: ChatRequest?
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        captured = request
        return AsyncThrowingStream { $0.finish() }
    }
}

private final class CapturingFactory: LLMProviderFactory, @unchecked Sendable {
    let provider = CapturingProvider()
    func make(for: Provider, apiKey: String) throws -> any LLMProvider {
        return provider
    }
}

/// byModel + thinkingEnabled=true 时应使用 thinkingModelId
func test_execute_byModel_thinkingEnabled_usesThinkingModelId() async throws {
    let provider = Provider(id: "ds", name: "DeepSeek",
                            baseURL: URL(string: "https://api")!,
                            apiKeyRef: "keychain:ds",
                            defaultModel: "deepseek-chat",
                            thinking: .byModel)
    let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                    systemPrompt: nil, userPrompt: "{{selection}}",
                    providerId: "ds", modelId: "deepseek-chat",
                    temperature: nil, displayMode: .window, variables: [:],
                    thinkingModelId: "deepseek-reasoner",
                    thinkingEnabled: true)
    let factory = CapturingFactory()
    let executor = makeExecutor(provider: provider, tool: tool, factory: factory)
    _ = try await executor.execute(tool: tool, payload: makePayload())
    XCTAssertEqual(factory.provider.captured?.model, "deepseek-reasoner")
    XCTAssertNil(factory.provider.captured?.extraBody)
}

/// byModel + thinkingEnabled=true 但 thinkingModelId=nil 时应抛配置错误
func test_execute_byModel_thinkingEnabled_noThinkingModelId_throws() async throws {
    let provider = Provider(id: "ds", name: "DeepSeek",
                            baseURL: URL(string: "https://api")!,
                            apiKeyRef: "keychain:ds",
                            defaultModel: "deepseek-chat",
                            thinking: .byModel)
    let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                    systemPrompt: nil, userPrompt: "{{selection}}",
                    providerId: "ds", modelId: "deepseek-chat",
                    temperature: nil, displayMode: .window, variables: [:],
                    thinkingModelId: nil,
                    thinkingEnabled: true)
    let executor = makeExecutor(provider: provider, tool: tool,
                                factory: CapturingFactory())
    do {
        _ = try await executor.execute(tool: tool, payload: makePayload())
        XCTFail("expected throw")
    } catch SliceError.configuration {
        // OK
    }
}

/// byParameter + thinkingEnabled=true 时 extraBody 应为 enableBodyJSON 解析结果
func test_execute_byParameter_thinkingEnabled_setsExtraBody() async throws {
    let provider = Provider(id: "or", name: "OpenRouter",
                            baseURL: URL(string: "https://api")!,
                            apiKeyRef: "keychain:or",
                            defaultModel: "claude",
                            thinking: .byParameter(
                                enableBodyJSON: #"{"reasoning":{"effort":"medium"}}"#,
                                disableBodyJSON: #"{"reasoning":{"effort":"none"}}"#
                            ))
    let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                    systemPrompt: nil, userPrompt: "{{selection}}",
                    providerId: "or", modelId: "claude",
                    temperature: nil, displayMode: .window, variables: [:],
                    thinkingEnabled: true)
    let factory = CapturingFactory()
    let executor = makeExecutor(provider: provider, tool: tool, factory: factory)
    _ = try await executor.execute(tool: tool, payload: makePayload())
    let extra = factory.provider.captured?.extraBody as? [String: Any]
    XCTAssertNotNil(extra?["reasoning"])
}

/// byParameter + thinkingEnabled=false + 有 disableBodyJSON 时也应 merge
func test_execute_byParameter_thinkingDisabled_withDisableBody_setsExtraBody() async throws {
    let provider = Provider(id: "or", name: "OpenRouter",
                            baseURL: URL(string: "https://api")!,
                            apiKeyRef: "keychain:or",
                            defaultModel: "claude",
                            thinking: .byParameter(
                                enableBodyJSON: #"{"reasoning":{"effort":"medium"}}"#,
                                disableBodyJSON: #"{"reasoning":{"effort":"none"}}"#
                            ))
    let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                    systemPrompt: nil, userPrompt: "{{selection}}",
                    providerId: "or", modelId: "claude",
                    temperature: nil, displayMode: .window, variables: [:],
                    thinkingEnabled: false)
    let factory = CapturingFactory()
    let executor = makeExecutor(provider: provider, tool: tool, factory: factory)
    _ = try await executor.execute(tool: tool, payload: makePayload())
    let extra = factory.provider.captured?.extraBody as? [String: Any]
    XCTAssertNotNil(extra?["reasoning"])
}

/// byParameter + thinkingEnabled=false + 无 disableBodyJSON 时 extraBody 应为 nil
func test_execute_byParameter_thinkingDisabled_noDisableBody_extraBodyNil() async throws {
    let provider = Provider(id: "an", name: "Anthropic",
                            baseURL: URL(string: "https://api")!,
                            apiKeyRef: "keychain:an",
                            defaultModel: "claude-4.6",
                            thinking: .byParameter(
                                enableBodyJSON: #"{"thinking":{"type":"adaptive"}}"#,
                                disableBodyJSON: nil
                            ))
    let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                    systemPrompt: nil, userPrompt: "{{selection}}",
                    providerId: "an", modelId: "claude-4.6",
                    temperature: nil, displayMode: .window, variables: [:],
                    thinkingEnabled: false)
    let factory = CapturingFactory()
    let executor = makeExecutor(provider: provider, tool: tool, factory: factory)
    _ = try await executor.execute(tool: tool, payload: makePayload())
    XCTAssertNil(factory.provider.captured?.extraBody)
}

/// byParameter 的 enableBodyJSON 不是合法 JSON 时应抛配置错误
func test_execute_byParameter_invalidEnableJSON_throws() async throws {
    let provider = Provider(id: "x", name: "X",
                            baseURL: URL(string: "https://api")!,
                            apiKeyRef: "keychain:x",
                            defaultModel: "m",
                            thinking: .byParameter(
                                enableBodyJSON: "not valid json !!!",
                                disableBodyJSON: nil
                            ))
    let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                    systemPrompt: nil, userPrompt: "{{selection}}",
                    providerId: "x", modelId: "m",
                    temperature: nil, displayMode: .window, variables: [:],
                    thinkingEnabled: true)
    let executor = makeExecutor(provider: provider, tool: tool,
                                factory: CapturingFactory())
    do {
        _ = try await executor.execute(tool: tool, payload: makePayload())
        XCTFail("expected throw")
    } catch SliceError.configuration {
        // OK
    }
}

/// Provider.thinking == nil 时应忽略 thinkingEnabled，使用默认 modelId 且无 extraBody
func test_execute_providerThinkingNil_ignoresThinkingEnabled() async throws {
    let provider = Provider(id: "old", name: "Old",
                            baseURL: URL(string: "https://api")!,
                            apiKeyRef: "keychain:old",
                            defaultModel: "gpt-3.5",
                            thinking: nil)
    let tool = Tool(id: "t", name: "T", icon: "x", description: nil,
                    systemPrompt: nil, userPrompt: "{{selection}}",
                    providerId: "old", modelId: "gpt-3.5",
                    temperature: nil, displayMode: .window, variables: [:],
                    thinkingModelId: "gpt-4",
                    thinkingEnabled: true)
    let factory = CapturingFactory()
    let executor = makeExecutor(provider: provider, tool: tool, factory: factory)
    _ = try await executor.execute(tool: tool, payload: makePayload())
    XCTAssertEqual(factory.provider.captured?.model, "gpt-3.5")
    XCTAssertNil(factory.provider.captured?.extraBody)
}

// MARK: - Test helpers

/// 构造一个 ToolExecutor，注入 single-Provider 配置 + spy keychain（返回固定 API Key）
private func makeExecutor(provider: Provider, tool: Tool,
                          factory: any LLMProviderFactory) -> ToolExecutor {
    let cfg = Configuration(
        schemaVersion: Configuration.currentSchemaVersion,
        providers: [provider], tools: [tool],
        hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
        triggers: TriggerSettings(floatingToolbarEnabled: true,
                                  commandPaletteEnabled: true,
                                  minimumSelectionLength: 1,
                                  triggerDelayMs: 100),
        telemetry: TelemetrySettings(enabled: false),
        appBlocklist: []
    )
    return ToolExecutor(
        configurationProvider: ImmediateConfigProvider(cfg: cfg),
        providerFactory: factory,
        keychain: AlwaysOKKeychain()
    )
}

private struct ImmediateConfigProvider: ConfigurationProviding {
    let cfg: Configuration
    func current() async -> Configuration { cfg }
    func update(_ configuration: Configuration) async throws {}
}

private struct AlwaysOKKeychain: KeychainAccessing {
    func readAPIKey(providerId: String) async throws -> String? { "test-key" }
    func writeAPIKey(_ value: String, providerId: String) async throws {}
    func deleteAPIKey(providerId: String) async throws {}
}

private func makePayload() -> SelectionPayload {
    SelectionPayload(text: "hi", appName: "TestApp",
                     appBundleID: "test.app", url: nil,
                     screenPoint: .zero, source: .axPrimary)
}
```

Notes for the implementer:
- `LLMProvider` and `LLMProviderFactory` protocols are in SliceCore (verify with `grep -rn "protocol LLMProvider" SliceAIKit/Sources/SliceCore`)
- `SelectionPayload` constructor signature may differ slightly — match the existing signature in `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`

### Step 2: Run tests to verify they fail (TDD red)

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --filter SliceCoreTests.ToolExecutorTests`

Expected: 7 new tests fail (model is still `tool.modelId` regardless of `thinkingEnabled`, and extraBody is always nil).

### Step 3: Implement ToolExecutor decision logic

- [x] Modify `SliceAIKit/Sources/SliceCore/ToolExecutor.swift` — replace step 5 block (the `let request = ChatRequest(...)` line) with:

```swift
        // 5. 构造 ChatRequest：按 tool.thinkingEnabled × provider.thinking 决定 model + extraBody
        var modelId = tool.modelId ?? provider.defaultModel
        var extraBody: [String: Any]? = nil

        if let thinking = provider.thinking {
            switch thinking {
            case .byModel:
                if tool.thinkingEnabled {
                    // byModel 模式开启 thinking：必须有 thinkingModelId 才能切
                    guard let alt = tool.thinkingModelId else {
                        throw SliceError.configuration(
                            .invalidJSON("Tool '\(tool.id)' has thinkingEnabled=true but no thinkingModelId for Provider '\(provider.id)' (byModel)")
                        )
                    }
                    modelId = alt
                }
                // thinkingEnabled=false 时使用 tool.modelId（已是默认值）
            case .byParameter(let enableJSON, let disableJSON):
                let payload = tool.thinkingEnabled ? enableJSON : disableJSON
                if let json = payload {
                    do {
                        guard let dict = try JSONSerialization.jsonObject(with: Data(json.utf8))
                                as? [String: Any] else {
                            throw SliceError.configuration(
                                .invalidJSON("thinking template payload must be JSON object")
                            )
                        }
                        extraBody = dict
                    } catch let error as SliceError {
                        throw error
                    } catch {
                        throw SliceError.configuration(
                            .invalidJSON("thinking template parse failed: \(error.localizedDescription)")
                        )
                    }
                }
            }
        }

        let request = ChatRequest(
            model: modelId,
            messages: messages,
            temperature: tool.temperature,
            maxTokens: nil,
            extraBody: extraBody
        )
```

### Step 4: Run tests to verify they pass

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --filter SliceCoreTests.ToolExecutorTests`

Expected: all existing ToolExecutorTests pass + 7 new tests pass.

### Step 5: Commit

- [x] Run:

```bash
git -C /Users/majiajun/workspace/SliceAI-lite add \
  SliceAIKit/Sources/SliceCore/ToolExecutor.swift \
  SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift

git -C /Users/majiajun/workspace/SliceAI-lite commit -m "feat(slicecore): ToolExecutor branches on tool.thinkingEnabled × provider.thinking

byModel + on  -> ChatRequest.model = tool.thinkingModelId (throws if nil)
byModel + off -> ChatRequest.model = tool.modelId (unchanged)
byParameter   -> parses enable/disableBodyJSON to ChatRequest.extraBody
provider.thinking == nil -> ignores thinkingEnabled (unchanged behavior)"
```

---

## Task 3: LLMProviders — extraBody merge + reasoning fallback

**Files:**
- Modify: `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift`
- Modify: `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift`
- Create: `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-openrouter-reasoning.txt`
- Create: `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-deepseek-reasoning-content.txt`
- Modify: `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift`

### Step 1: Add reasoning fields to OpenAIStreamChunk DTO

- [x] Modify `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift` — find `OpenAIStreamChunk.Choice.Delta` struct and add two optional fields:

```swift
// 现有字段（如 content 等）保留
public let content: String?
/// OpenRouter unified reasoning：thinking 增量
public let reasoning: String?
/// DeepSeek V4 风格：reasoning_content 增量
public let reasoningContent: String?

private enum CodingKeys: String, CodingKey {
    case content
    case reasoning
    case reasoningContent = "reasoning_content"
}
```

Update the existing `init` and explicit Codable if any (keep the existing `content` decoding logic intact, just add `reasoning` and `reasoningContent` as `decodeIfPresent`).

Verify exact struct location: `grep -n "struct.*Delta\|delta:" SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift`

### Step 2: Modify decodeChunk to extract reasoning via fallback chain

- [x] Modify `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift` — replace the `decodeChunk` method body (around lines 187-205) with:

```swift
private static func decodeChunk(json: String) throws -> ChatChunk? {
    guard let data = json.data(using: .utf8) else {
        throw SliceError.provider(.sseParseError("non-utf8 data line"))
    }
    let parsed: OpenAIStreamChunk
    do {
        parsed = try JSONDecoder().decode(OpenAIStreamChunk.self, from: data)
    } catch let error as DecodingError {
        throw SliceError.provider(.sseParseError(summarize(decodingError: error)))
    } catch {
        throw SliceError.provider(.sseParseError("decode failed"))
    }
    let firstDelta = parsed.choices.first?.delta
    let delta = firstDelta?.content ?? ""
    // Reasoning fallback chain: OpenRouter (delta.reasoning) → DeepSeek (delta.reasoning_content) → nil
    // 不绑定模板，让任何 vendor 自动 work
    let reasoningDelta = firstDelta?.reasoning ?? firstDelta?.reasoningContent
    let reason = parsed.choices.first?.finishReason.flatMap(FinishReason.init(rawValue:))
    // 只有所有字段都为空时才丢弃 chunk
    if delta.isEmpty && (reasoningDelta?.isEmpty ?? true) && reason == nil { return nil }
    return ChatChunk(delta: delta, reasoningDelta: reasoningDelta, finishReason: reason)
}
```

### Step 3: Modify buildURLRequest to merge extraBody into request body

- [x] Modify `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift` — replace `buildURLRequest` body's body construction block (around lines 62-68):

```swift
// 追加 stream: true 与 extraBody（thinking 模式参数）；其余字段由 ChatRequest 编码产出
var body = try JSONEncoder().encode(request)
if var dict = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
    dict["stream"] = true
    // 防御性 merge：extraBody 不覆盖现有字段（防止用户在模板里写 model 误改）
    if let extra = request.extraBody {
        for (k, v) in extra where dict[k] == nil {
            dict[k] = v
        }
    }
    body = try JSONSerialization.data(withJSONObject: dict)
}
httpReq.httpBody = body
```

### Step 4: Create SSE fixture for OpenRouter reasoning

- [x] Create `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-openrouter-reasoning.txt` — exact content (note the empty line between events):

```
data: {"choices":[{"delta":{"reasoning":"Let me think...","content":""}}]}

data: {"choices":[{"delta":{"reasoning":" the answer is 42","content":""}}]}

data: {"choices":[{"delta":{"content":"42"}}]}

data: [DONE]

```

### Step 5: Create SSE fixture for DeepSeek reasoning_content

- [x] Create `SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-deepseek-reasoning-content.txt`:

```
data: {"choices":[{"delta":{"reasoning_content":"Analyzing the input...","content":""}}]}

data: {"choices":[{"delta":{"reasoning_content":" computing result.","content":""}}]}

data: {"choices":[{"delta":{"content":"Result: 42"}}]}

data: [DONE]

```

### Step 6: Write failing tests for extraBody merge + reasoning extraction

- [x] Modify `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift` — add at end of class (verify `MockURLProtocol` setup style by reading existing tests in the same file):

```swift
// MARK: - extraBody merge

/// extraBody 字典在 buildURLRequest 时正确 merge 到 root body
func test_extraBody_mergedToRootBody() async throws {
    let extra: [String: Any] = ["thinking": ["type": "enabled"]]
    let request = ChatRequest(
        model: "test-model",
        messages: [ChatMessage(role: .user, content: "hi")],
        extraBody: extra
    )
    var capturedBody: Data?
    MockURLProtocol.requestHandler = { req in
        capturedBody = req.httpBody
        let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (response, "data: [DONE]\n\n".data(using: .utf8)!)
    }
    let provider = makeProvider()
    let stream = try await provider.stream(request: request)
    for try await _ in stream { }  // drain

    XCTAssertNotNil(capturedBody)
    let bodyDict = try JSONSerialization.jsonObject(with: capturedBody!) as? [String: Any]
    let thinking = bodyDict?["thinking"] as? [String: Any]
    XCTAssertEqual(thinking?["type"] as? String, "enabled")
    // sanity: stream still added
    XCTAssertEqual(bodyDict?["stream"] as? Bool, true)
}

/// extraBody 不应覆盖 ChatRequest 的现有字段（防御性）
func test_extraBody_doesNotOverrideExistingFields() async throws {
    let request = ChatRequest(
        model: "real-model",
        messages: [ChatMessage(role: .user, content: "hi")],
        extraBody: ["model": "evil-model"]  // user tries to override
    )
    var capturedBody: Data?
    MockURLProtocol.requestHandler = { req in
        capturedBody = req.httpBody
        let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (response, "data: [DONE]\n\n".data(using: .utf8)!)
    }
    let provider = makeProvider()
    let stream = try await provider.stream(request: request)
    for try await _ in stream { }

    let bodyDict = try JSONSerialization.jsonObject(with: capturedBody!) as? [String: Any]
    XCTAssertEqual(bodyDict?["model"] as? String, "real-model")
}

// MARK: - Reasoning extraction (fallback chain)

/// OpenRouter 风格的 SSE chunk: chunk.reasoningDelta 应来自 delta.reasoning
func test_chunk_reasoning_extractsFromOpenRouterField() async throws {
    let fixture = try loadFixture("sse-openrouter-reasoning.txt")
    MockURLProtocol.requestHandler = { req in
        let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (response, fixture)
    }
    let provider = makeProvider()
    let stream = try await provider.stream(request: makeRequest())
    var reasonings: [String] = []
    var deltas: [String] = []
    for try await chunk in stream {
        if let r = chunk.reasoningDelta { reasonings.append(r) }
        if !chunk.delta.isEmpty { deltas.append(chunk.delta) }
    }
    XCTAssertEqual(reasonings, ["Let me think...", " the answer is 42"])
    XCTAssertEqual(deltas, ["42"])
}

/// DeepSeek 风格的 SSE chunk: chunk.reasoningDelta 应来自 delta.reasoning_content
func test_chunk_reasoning_extractsFromDeepSeekField() async throws {
    let fixture = try loadFixture("sse-deepseek-reasoning-content.txt")
    MockURLProtocol.requestHandler = { req in
        let response = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (response, fixture)
    }
    let provider = makeProvider()
    let stream = try await provider.stream(request: makeRequest())
    var reasonings: [String] = []
    var deltas: [String] = []
    for try await chunk in stream {
        if let r = chunk.reasoningDelta { reasonings.append(r) }
        if !chunk.delta.isEmpty { deltas.append(chunk.delta) }
    }
    XCTAssertEqual(reasonings, ["Analyzing the input...", " computing result."])
    XCTAssertEqual(deltas, ["Result: 42"])
}

// MARK: - Helpers (add if not already present in test file)

private func loadFixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: nil,
                                subdirectory: "Fixtures")!
    return try Data(contentsOf: url)
}

private func makeProvider() -> OpenAICompatibleProvider {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return OpenAICompatibleProvider(
        baseURL: URL(string: "https://api.test.local/v1")!,
        apiKey: "test-key",
        session: session
    )
}

private func makeRequest() -> ChatRequest {
    ChatRequest(model: "m", messages: [ChatMessage(role: .user, content: "hi")])
}
```

Notes:
- `MockURLProtocol` and `Bundle.module` setup may already exist in the test target — reuse the existing helpers if so (verify with `grep -rn "MockURLProtocol.requestHandler\|Bundle.module" SliceAIKit/Tests/LLMProvidersTests/`)
- The `Package.swift` for SliceAIKit must include the new fixture files in `LLMProvidersTests` target's `resources:`. Check `SliceAIKit/Package.swift` and verify `resources: [.copy("Fixtures")]` (or similar) covers the Fixtures directory; if not, add the new `.copy()` entries

### Step 7: Run tests

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --filter LLMProvidersTests --parallel`

Expected: existing tests still pass + 4 new tests pass.

### Step 8: Commit

- [x] Run:

```bash
git -C /Users/majiajun/workspace/SliceAI-lite add \
  SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift \
  SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift \
  SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-openrouter-reasoning.txt \
  SliceAIKit/Tests/LLMProvidersTests/Fixtures/sse-deepseek-reasoning-content.txt \
  SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift

git -C /Users/majiajun/workspace/SliceAI-lite commit -m "feat(llmproviders): merge extraBody into request body, extract reasoning from SSE

- buildURLRequest merges request.extraBody into root body (does not override
  existing fields like model)
- decodeChunk extracts reasoning via fallback chain:
  delta.reasoning (OpenRouter unified) -> delta.reasoning_content (DeepSeek)
  -> nil (no reasoning), so any thinking template auto-works
- OpenAIStreamChunk.Delta gains optional reasoning + reasoning_content fields
- Two SSE fixtures cover both styles"
```

---

## Task 4: SettingsUI — toggleThinking + ThinkingTemplate library

**Files:**
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`
- Create: `SliceAIKit/Sources/SettingsUI/Thinking/ThinkingTemplate.swift`

### Step 1: Add toggleThinking + saveTools to SettingsViewModel

- [x] Modify `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift` — add at end of class (before closing brace):

```swift
/// 切换指定工具的 thinking 偏好并立即持久化
///
/// 用于 ResultPanel 的 toggle 按钮回调：用户点击后立即写盘，
/// 下次该工具执行时按新偏好走。
/// IO 失败仅打日志（内存态已更新，下次启动 reload 以磁盘为准），
/// 与 saveTriggers / saveHotkeys 的处理风格一致。
/// - Parameter toolId: 要切换的工具 id
public func toggleThinking(for toolId: Tool.ID) async {
    guard let idx = configuration.tools.firstIndex(where: { $0.id == toolId }) else {
        print("[SettingsViewModel] toggleThinking: tool '\(toolId)' not found")
        return
    }
    configuration.tools[idx].thinkingEnabled.toggle()
    do {
        try await store.update(configuration)
        print("[SettingsViewModel] toggleThinking: '\(toolId)' -> \(configuration.tools[idx].thinkingEnabled)")
    } catch {
        print("[SettingsViewModel] toggleThinking: persist failed – \(error.localizedDescription)")
    }
}

/// 将当前 configuration.tools 写回磁盘，供工具编辑页 onChange 立即持久化
///
/// 与 saveTriggers / saveHotkeys 同构：调用方更新 configuration.tools 后调用此方法；
/// IO 失败仅打日志，不向上抛错。
public func saveTools() async {
    do {
        try await store.update(configuration)
        print("[SettingsViewModel] saveTools: persisted OK")
    } catch {
        print("[SettingsViewModel] saveTools: persist failed – \(error.localizedDescription)")
    }
}
```

### Step 2: Create ThinkingTemplate enum + payload constants

- [x] Create `SliceAIKit/Sources/SettingsUI/Thinking/ThinkingTemplate.swift`:

```swift
import Foundation
import SliceCore

/// Provider 配置 UI 提供的 byParameter 模板库
///
/// 模板**不进 schema**，是 SettingsUI 内部的常量。用户在 ProviderEditorView
/// 选模板 → UI 自动填两个 textarea → 用户可微调 → 保存为
/// `ProviderThinkingCapability.byParameter(enableJSON, disableJSON)`。
///
/// 各 payload 来自 2026-04-24 web 调研的官方文档；模板内 effort/budget 写死合理
/// 默认值（medium / 8000），需要别的取值用户改 raw JSON 即可。
public enum ProviderThinkingTemplate: String, CaseIterable, Identifiable {
    case openRouterUnified
    case deepSeekV4
    case anthropicAdaptive
    case anthropicBudget
    case openAIReasoningEffort
    case qwen3
    case custom

    public var id: String { rawValue }

    /// 显示给用户的名称（中文，与设置界面一致风格）
    public var displayName: String {
        switch self {
        case .openRouterUnified:     return "OpenRouter 统一接口（推荐）"
        case .deepSeekV4:             return "DeepSeek V4"
        case .anthropicAdaptive:      return "Anthropic 4.6+（adaptive）"
        case .anthropicBudget:        return "Anthropic 4.5 及以下（budget_tokens）"
        case .openAIReasoningEffort:  return "OpenAI / GPT-5（reasoning_effort）"
        case .qwen3:                  return "阿里 Qwen3（enable_thinking）"
        case .custom:                 return "自定义"
        }
    }

    /// 给用户的简短说明（出现在选项下方提示）
    public var description: String {
        switch self {
        case .openRouterUnified:
            return "OpenRouter 把 OpenAI / Anthropic / DeepSeek / Grok 全部 reasoning 模型统一为 reasoning.effort 参数。一个模板覆盖所有 vendor。"
        case .deepSeekV4:
            return "适用 deepseek-v4-pro / deepseek-v4-flash 直连。"
        case .anthropicAdaptive:
            return "Claude Sonnet 4.6 / Opus 4.6 起的 adaptive thinking，让模型自决思考量。"
        case .anthropicBudget:
            return "Claude Sonnet 3.7 / 4.5 等支持固定 budget_tokens 的 extended thinking。"
        case .openAIReasoningEffort:
            return "OpenAI o-series（o3/o4-mini）和 GPT-5 系列的 reasoning_effort 参数。"
        case .qwen3:
            return "阿里 Qwen3（含 235B / 32B 等）的 enable_thinking 开关。"
        case .custom:
            return "手动填写 enable / disable 的 JSON。"
        }
    }

    /// 模板预设的 enableBodyJSON
    public var enableBodyJSON: String {
        switch self {
        case .openRouterUnified:     return #"{"reasoning":{"effort":"medium"}}"#
        case .deepSeekV4:             return #"{"thinking":{"type":"enabled"}}"#
        case .anthropicAdaptive:      return #"{"thinking":{"type":"adaptive"}}"#
        case .anthropicBudget:        return #"{"thinking":{"type":"enabled","budget_tokens":8000}}"#
        case .openAIReasoningEffort:  return #"{"reasoning_effort":"medium"}"#
        case .qwen3:                  return #"{"enable_thinking":true}"#
        case .custom:                 return ""
        }
    }

    /// 模板预设的 disableBodyJSON；nil 表示"省略字段"
    public var disableBodyJSON: String? {
        switch self {
        case .openRouterUnified:     return #"{"reasoning":{"effort":"none"}}"#
        case .deepSeekV4:             return #"{"thinking":{"type":"disabled"}}"#
        case .anthropicAdaptive:      return nil  // Anthropic 关闭 = 省略 thinking 字段
        case .anthropicBudget:        return nil
        case .openAIReasoningEffort:  return #"{"reasoning_effort":"minimal"}"#
        case .qwen3:                  return #"{"enable_thinking":false}"#
        case .custom:                 return nil
        }
    }

    /// 试图从一个已存在的 (enableJSON, disableJSON) 推断对应模板，用于编辑现有 Provider
    /// 时 UI 显示当前模板。无匹配返回 .custom。
    public static func match(enableJSON: String, disableJSON: String?) -> ProviderThinkingTemplate {
        for template in allCases where template != .custom {
            if template.enableBodyJSON == enableJSON && template.disableBodyJSON == disableJSON {
                return template
            }
        }
        return .custom
    }
}
```

### Step 3: Build + run all SliceAIKit tests to confirm no regressions

- [x] Run: `swift build --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit`

Expected: build complete, no errors.

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --parallel`

Expected: all tests pass.

### Step 4: Commit

- [x] Run:

```bash
git -C /Users/majiajun/workspace/SliceAI-lite add \
  SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift \
  SliceAIKit/Sources/SettingsUI/Thinking/ThinkingTemplate.swift

git -C /Users/majiajun/workspace/SliceAI-lite commit -m "feat(settingsui): toggleThinking ViewModel method + ThinkingTemplate library

- SettingsViewModel.toggleThinking(for: toolId) flips Tool.thinkingEnabled
  and persists to config.json (mirrors saveTriggers/saveHotkeys style)
- SettingsViewModel.saveTools() for tool editor onChange persistence
- ThinkingTemplate enum: 7 cases (OpenRouter unified, DeepSeek V4, Claude
  adaptive/budget, OpenAI reasoning_effort, Qwen3, custom) with
  displayName / description / enableBodyJSON / disableBodyJSON constants
- Templates derived from 2026-04-24 vendor docs; effort hardcoded to
  medium / budget to 8000, advanced users edit raw JSON"
```

---

## Task 5: SettingsUI — ProviderEditorView thinking section

**Files:**
- Modify: `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift`

This task is UI-only; spec §7.2 explicitly accepts "no unit tests for SwiftUI views, manual verification only". Each step is a code change followed by `swift build` to catch type errors.

### Step 1: Read current ProviderEditorView structure

- [x] Read `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift` end-to-end. Identify where the existing "Provider name / baseURL / apiKey / defaultModel" form fields live. The thinking section will append below those.

### Step 2: Add ThinkingMode picker + template picker + JSON textareas

- [x] In `ProviderEditorView.swift`, add (or extend) the form `Section` block — pseudocode showing the structure to implement; adapt to the existing SwiftUI binding patterns in the file:

```swift
// 1. 顶部声明状态：当前编辑的 provider 是否启用 thinking、用什么模板、当前 JSON 文本
@State private var thinkingMode: ThinkingMode = .none  // none | byModel | byParameter
@State private var template: ProviderThinkingTemplate = .openRouterUnified
@State private var enableJSON: String = ""
@State private var disableJSON: String = ""
@State private var enableJSONError: String?
@State private var disableJSONError: String?

private enum ThinkingMode: String, CaseIterable, Identifiable {
    case none, byModel, byParameter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "不支持"
        case .byModel: return "切换 model id"
        case .byParameter: return "参数透传"
        }
    }
}

// 2. Section 内容
Section("Thinking 切换") {
    Picker("模式", selection: $thinkingMode) {
        ForEach(ThinkingMode.allCases) { mode in
            Text(mode.label).tag(mode)
        }
    }
    .onChange(of: thinkingMode) { _, new in
        commitThinking()
    }

    if thinkingMode == .byParameter {
        Picker("模板", selection: $template) {
            ForEach(ProviderThinkingTemplate.allCases) { tpl in
                Text(tpl.displayName).tag(tpl)
            }
        }
        .onChange(of: template) { _, new in
            // 切模板时填充 textareas（除非是 custom）
            if new != .custom {
                enableJSON = new.enableBodyJSON
                disableJSON = new.disableBodyJSON ?? ""
            }
            commitThinking()
        }

        Text(template.description)
            .font(.caption)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 4) {
            Text("开启 thinking 时塞入 request body:")
                .font(.caption)
            TextEditor(text: $enableJSON)
                .frame(height: 80)
                .font(.system(.body, design: .monospaced))
                .border(enableJSONError == nil ? Color.gray.opacity(0.3) : Color.red)
                .onChange(of: enableJSON) { _, _ in
                    enableJSONError = validateJSON(enableJSON)
                    commitThinking()
                }
            if let err = enableJSONError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("关闭 thinking 时塞入 request body（可选）:")
                .font(.caption)
            TextEditor(text: $disableJSON)
                .frame(height: 80)
                .font(.system(.body, design: .monospaced))
                .border(disableJSONError == nil ? Color.gray.opacity(0.3) : Color.red)
                .onChange(of: disableJSON) { _, _ in
                    disableJSONError = disableJSON.isEmpty ? nil : validateJSON(disableJSON)
                    commitThinking()
                }
            if let err = disableJSONError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    } else if thinkingMode == .byModel {
        Text("切 model 模式：请在工具配置里填 thinking 模式的 model id。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

3. 帮助函数（同文件内 private）：

```swift
/// 校验 JSON 字符串：返回 nil 表示合法，非 nil 是错误描述
private func validateJSON(_ s: String) -> String? {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "JSON 不能为空" }
    guard let data = trimmed.data(using: .utf8) else { return "非 UTF-8" }
    do {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard obj is [String: Any] else { return "必须是 JSON object（{...}）" }
        return nil
    } catch {
        return "JSON 解析失败: \(error.localizedDescription)"
    }
}

/// 把当前 UI 状态写回 provider.thinking，触发 ViewModel 持久化
private func commitThinking() {
    let new: ProviderThinkingCapability?
    switch thinkingMode {
    case .none:
        new = nil
    case .byModel:
        new = .byModel
    case .byParameter:
        // 仅在两者校验通过时才 commit；invalid 时保持上次合法值
        if enableJSONError != nil { return }
        if !disableJSON.isEmpty && disableJSONError != nil { return }
        new = .byParameter(
            enableBodyJSON: enableJSON,
            disableBodyJSON: disableJSON.isEmpty ? nil : disableJSON
        )
    }
    // 通过 binding 反写到 viewModel.configuration.providers[idx].thinking
    provider.thinking = new
    Task { await viewModel.save() }  // 复用现有 save() 方法
}

/// 视图初始化时根据 provider.thinking 反推 UI 状态（用于编辑现有 Provider）
private func loadThinkingFromProvider() {
    switch provider.thinking {
    case .none:
        thinkingMode = .none
    case .byModel:
        thinkingMode = .byModel
    case .byParameter(let en, let dis):
        thinkingMode = .byParameter
        enableJSON = en
        disableJSON = dis ?? ""
        template = ProviderThinkingTemplate.match(enableJSON: en, disableJSON: dis)
    }
}
```

4. 在 view 的 `.onAppear` 调 `loadThinkingFromProvider()`。

### Step 3: Verify build

- [x] Run: `swift build --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit`

Expected: build succeeds. If type errors appear (e.g. binding to provider in a List), follow the existing pattern in ProviderEditorView for that.

### Step 4: Commit

- [x] Run:

```bash
git -C /Users/majiajun/workspace/SliceAI-lite add \
  SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift

git -C /Users/majiajun/workspace/SliceAI-lite commit -m "feat(settingsui): ProviderEditorView thinking section

Add 'Thinking 切换' section with three subsections:
- Mode picker (none / byModel / byParameter)
- byParameter: template picker + two JSON textareas with live validation
- byModel: instructional text directing user to per-tool configuration

Templates auto-fill the textareas; users can fine-tune; invalid JSON is
flagged inline (red border + caption) and not committed to the config."
```

---

## Task 6: SettingsUI — ToolEditorView thinkingModelId field

**Files:**
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`

### Step 1: Read current ToolEditorView

- [x] Read `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`. Locate the existing fields (modelId, providerId picker, etc.).

### Step 2: Add conditional thinkingModelId field

- [x] In `ToolEditorView.swift`, near the existing `modelId` field, add:

```swift
// 在 view body 内部，找到 modelId TextField 那一节后面
if let provider = currentProvider, provider.thinking == .byModel {
    HStack {
        Text("Thinking 模式 model id")
        Spacer()
        TextField("如 deepseek-reasoner", text: Binding(
            get: { tool.thinkingModelId ?? "" },
            set: { newValue in
                tool.thinkingModelId = newValue.isEmpty ? nil : newValue
                Task { await viewModel.saveTools() }
            }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 200)
    }
}
```

`currentProvider` 是 view 内通过 `tool.providerId` 在 `viewModel.configuration.providers` 里查出来的 helper computed property。如果不存在，加一个：

```swift
private var currentProvider: Provider? {
    viewModel.configuration.providers.first { $0.id == tool.providerId }
}
```

### Step 3: Verify build

- [x] Run: `swift build --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit`

Expected: build succeeds.

### Step 4: Commit

- [x] Run:

```bash
git -C /Users/majiajun/workspace/SliceAI-lite add \
  SliceAIKit/Sources/SettingsUI/ToolEditorView.swift

git -C /Users/majiajun/workspace/SliceAI-lite commit -m "feat(settingsui): ToolEditorView shows thinkingModelId field for byModel providers

The Tool editor now conditionally displays a 'Thinking 模式 model id' input
when the chosen Provider's thinking == .byModel. Field persists via
SettingsViewModel.saveTools() on each change."
```

---

## Task 7: Windowing — ResultPanel toggle button + reasoning DisclosureGroup

**Files:**
- Modify: `SliceAIKit/Sources/Windowing/ResultPanel.swift`
- Modify: `SliceAIKit/Sources/Windowing/ResultContentView.swift` (likely needs changes too)

This task is also UI-only (spec §7.2). Each step is code + `swift build`.

### Step 1: Read ResultPanel + ResultContentView structure

- [x] Read both files to understand:
  - Where the header HStack with toolName / model / pin / regenerate / close lives
  - How `chunk.delta` is currently accumulated (likely a `@Published` or `@Observable` String)
  - How `onRegenerate` closure is invoked

### Step 2: Add reasoning accumulator + toggle state to ResultPanel state model

- [x] Find the state-holding object in ResultPanel (likely `@Observable` or `ObservableObject` view model). Add:

```swift
/// 流式累积的 reasoning 文本（OpenRouter delta.reasoning / DeepSeek delta.reasoning_content）
public private(set) var accumulatedReasoning: String = ""

/// reasoning DisclosureGroup 的展开状态
@Published public var reasoningExpanded: Bool = false  // or @State if @Observable
```

In the chunk-receiving function (likely `append(_ chunk: ChatChunk)` or similar — verify name):

```swift
public func append(_ chunk: ChatChunk) {
    // 现有逻辑：累积 chunk.delta 到主内容
    self.accumulatedContent += chunk.delta

    // 新增：累积 reasoning
    if let r = chunk.reasoningDelta {
        self.accumulatedReasoning += r
    }
}
```

Note: the existing API may use a separate `append(_ delta: String)` overload taking a String — if so, also add `func append(reasoning: String)` and update the call site in `AppDelegate.execute(...)` to pass `chunk.reasoningDelta` separately. Match the existing style.

### Step 3: Add toggle button to header

- [x] In ResultPanel's header HStack, add (next to the pin / regenerate buttons):

```swift
// 仅当 tool 的 provider 支持 thinking 切换时显示
if shouldShowThinkingToggle {
    Button {
        onToggleThinking?()  // ResultPanel 的 closure，由 AppDelegate 注入
    } label: {
        Image(systemName: "brain.head.profile")
            .symbolVariant(thinkingEnabled ? .fill : .none)
            .foregroundStyle(thinkingEnabled ? Color.accentColor : Color.secondary)
    }
    .buttonStyle(.plain)
    .help(thinkingEnabled ? "切换为非思考模式" : "切换为思考模式")
}
```

`shouldShowThinkingToggle` / `thinkingEnabled` / `onToggleThinking` 三个属性需要在 ResultPanel 暴露给 AppDelegate 注入。

### Step 4: Add reasoning DisclosureGroup above main content

- [x] In ResultContentView (or wherever main markdown render lives), add ABOVE the existing markdown view:

```swift
if !state.accumulatedReasoning.isEmpty {
    DisclosureGroup(isExpanded: $state.reasoningExpanded) {
        ScrollView {
            Text(state.accumulatedReasoning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 150)
    } label: {
        HStack {
            Text("💭 思考过程")
                .font(.caption.weight(.medium))
            Spacer()
        }
    }
    .padding(.bottom, 4)
}
```

### Step 5: Wire AppDelegate to inject onToggleThinking and read provider.thinking

- [x] In `SliceAIApp/AppDelegate.swift` `execute(tool:payload:)` function, where `container.resultPanel.open(...)` is called, add `shouldShowThinkingToggle` based on `provider.thinking != nil` and `onToggleThinking` closure:

```swift
let provider = container.configStore.current.providers.first { $0.id == tool.providerId }
let showToggle = provider?.thinking != nil
    && (provider?.thinking != .byModel || tool.thinkingModelId != nil)

container.resultPanel.open(
    toolName: tool.name,
    model: tool.modelId ?? "default",
    anchor: payload.screenPoint,
    showThinkingToggle: showToggle,
    thinkingEnabled: tool.thinkingEnabled,
    onToggleThinking: { [weak self] in
        Task { @MainActor in
            await self?.container.settingsViewModel.toggleThinking(for: tool.id)
            // 重跑：cancel 旧 stream + 重新 execute
            self?.execute(tool: tool, payload: payload)
        }
    },
    onDismiss: { streamTask.cancel() },
    onRegenerate: { [weak self] in
        streamTask.cancel()
        self?.execute(tool: tool, payload: payload)
    }
)
```

Note: `ResultPanel.open(...)` signature changes — extend it with the three new parameters (`showThinkingToggle`, `thinkingEnabled`, `onToggleThinking`). Default them to `false`/`false`/`nil` so other call sites (if any, like CommandPalette path) still compile.

Also note: after `toggleThinking(for:)` runs (it mutates `configuration.tools[idx].thinkingEnabled`), the `tool` local variable in the closure is stale. Read the fresh tool from `container.settingsViewModel.configuration.tools` before re-executing:

```swift
onToggleThinking: { [weak self] in
    Task { @MainActor in
        guard let self else { return }
        await self.container.settingsViewModel.toggleThinking(for: tool.id)
        // 用最新 tool 重跑
        if let fresh = self.container.settingsViewModel.configuration.tools.first(where: { $0.id == tool.id }) {
            self.execute(tool: fresh, payload: payload)
        }
    }
}
```

### Step 6: Verify build

- [x] Run: `swift build --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit`

Expected: build succeeds.

- [x] Run: `xcodebuild -project /Users/majiajun/workspace/SliceAI-lite/SliceAI.xcodeproj -scheme SliceAI -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

### Step 7: Commit

- [x] Run:

```bash
git -C /Users/majiajun/workspace/SliceAI-lite add \
  SliceAIKit/Sources/Windowing/ResultPanel.swift \
  SliceAIKit/Sources/Windowing/ResultContentView.swift \
  SliceAIApp/AppDelegate.swift

git -C /Users/majiajun/workspace/SliceAI-lite commit -m "feat(windowing): ResultPanel thinking toggle button + reasoning DisclosureGroup

- Header brain.head.profile button (visible only when Provider.thinking is
  non-nil and, for byModel, tool.thinkingModelId is configured)
- Tap toggles tool.thinkingEnabled, persists via SettingsViewModel, then
  re-executes with the fresh tool snapshot
- Above-content collapsible '思考过程' DisclosureGroup accumulates
  chunk.reasoningDelta; default collapsed, secondary color, scrollable
  capped at 150pt"
```

---

## Task 8: End-to-end verification

**Files:**
- None modified (pure verification)

This task confirms each layer integrates correctly. Each step is a manual user-driven check; the engineer runs the build, the user (or engineer in a test environment) drives the actual interaction.

### Step 1: Full SwiftPM test sweep

- [x] Run: `swift test --package-path /Users/majiajun/workspace/SliceAI-lite/SliceAIKit --parallel --enable-code-coverage`

Expected: all tests pass (existing 99 + ~17 new ones from Tasks 1-3).

### Step 2: Full SwiftLint sweep

- [x] Run: `(cd /Users/majiajun/workspace/SliceAI-lite && swiftlint lint --strict)`

Expected: 0 violations.

### Step 3: Xcode build

- [x] Run: `scripts/build-dmg.sh 0.2.0` (or `xcodebuild -scheme SliceAI -configuration Debug build` if just testing the build)

Expected: build succeeds and produces DMG with ad-hoc-signed .app.

### Step 4: Manual verification — backward compat

- [x] Install the new DMG over an existing SliceAI-lite install (which has a config.json without thinking fields).
- [x] Launch app. Verify:
  - App launches without crash
  - Existing tools still work (划词 → 浮条 → 选工具 → 流式结果)
  - Settings → Providers shows existing providers; "Thinking 切换" section defaults to `不支持`
  - Settings → Tools shows existing tools; no thinkingModelId field appears (since all providers default to `不支持`)

### Step 5: Manual verification — DeepSeek V4 byParameter end-to-end

- [x] In Settings → Providers, edit your DeepSeek provider:
  - Set Thinking 切换 → 模式 = 参数透传
  - 模板 = DeepSeek V4
  - Verify both textareas auto-filled
  - Save
- [x] Pick any tool that uses this provider
- [x] 划词 → 选工具 → 默认非思考模式应执行
- [x] 结果面板顶部应出现 brain 图标按钮（灰色 = thinking off）
- [x] 点击按钮 → 自动重跑 → 看到 reasoning 流式渲染（默认折叠的"💭 思考过程"出现）→ 主内容流式
- [x] 关闭面板，再次划词同一工具 → 默认应是 thinking on（按钮亮色）
- [x] 再次点击按钮 → 切回非思考 → 持久化

### Step 6: Manual verification — OpenRouter unified end-to-end

- [x] In Settings → Providers, add or edit OpenRouter provider:
  - Set Thinking 切换 → 模式 = 参数透传 → 模板 = OpenRouter 统一接口
- [x] Pick a tool using this provider with a reasoning-capable model (e.g. `anthropic/claude-sonnet-4.6`)
- [x] Repeat the toggle / regenerate / persistence flow from Step 5

### Step 7: Manual verification — byModel mode (DeepSeek V3 dual-model)

- [x] Edit a DeepSeek V3 provider:
  - Thinking 切换 → 模式 = 切换 model id
- [x] Edit a tool using this provider:
  - modelId = `deepseek-chat`
  - Thinking 模式 model id = `deepseek-reasoner`
- [x] 划词 → 工具 → toggle → 看到 model 切换为 `deepseek-reasoner` (Console.app 看 com.sliceai.lite Logger 输出)
- [x] reasoning 字段：DeepSeek V3 reasoner 用 `reasoning_content` → 应该正确渲染到 DisclosureGroup

### Step 8: Manual verification — error path

- [x] Edit a Provider thinking → 参数透传 → 自定义；输入 invalid JSON 如 `not valid`
- [x] Verify save 被阻止（红框 + 错误描述）
- [x] Edit a Tool 设置 thinkingEnabled=true 但 byModel provider 的 thinkingModelId 为空（直接改 config.json 模拟），重启 app 划词 → 应展示错误面板（"工具未配置 thinking 模式 model id"）+ "去设置" 按钮

### Step 9: Cleanup commit (only if E2E found bugs requiring code changes)

- [x] If Steps 4-8 found bugs needing fixes, commit them with descriptive messages. If everything works, no commit needed in Task 8.

### Step 10: Push the entire feature branch

- [x] Run: `git -C /Users/majiajun/workspace/SliceAI-lite push`

Expected: 7 commits (Tasks 1-7) pushed; CI runs green.

- [x] Watch CI: `gh -R yingjialong/SliceAI-lite run watch $(gh -R yingjialong/SliceAI-lite run list --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status`

Expected: CI passes (build + tests + SwiftLint).

---

## Self-Review (run after writing the plan)

**Spec coverage:**
- §3.1 Provider.thinking ✓ (Task 1)
- §3.2 Tool.thinkingModelId / thinkingEnabled ✓ (Task 1)
- §3.3 ChatRequest.extraBody ✓ (Task 1) — note plan keeps Codable instead of removing it (revised from spec; reason in Task 1)
- §3.4 ToolExecutor decision ✓ (Task 2)
- §3.5 OpenAICompatibleProvider extraBody merge ✓ (Task 3)
- §3.6 SSE reasoning fallback ✓ (Task 3)
- §3.7 Backward compat ✓ (Task 1 covers it; Task 8 verifies)
- §4 ThinkingTemplate library ✓ (Task 4)
- §5.1 Provider config UI ✓ (Task 5)
- §5.2 Tool config UI ✓ (Task 6)
- §5.3 ResultPanel toggle button ✓ (Task 7)
- §5.4 Reasoning DisclosureGroup ✓ (Task 7)
- §6 error handling ✓ (Tasks 2 + 5 + 7 + 8)
- §7.1 unit tests ✓ (Tasks 1-3)
- §7.2 manual checks ✓ (Task 8)
- §7.3 end-to-end smoke ✓ (Task 8 Steps 5-7)

**Placeholder scan:** No "TBD" / "TODO" / vague instructions. Each step has either complete code or an exact command. UI tasks (5/6/7) require reading the existing file to find anchor lines; the plan acknowledges this and provides the structure to add.

**Type consistency:**
- `ProviderThinkingCapability` consistently named across Tasks 1-2-4-5
- `Tool.thinkingEnabled` / `Tool.thinkingModelId` consistent across Tasks 1-2-6-7
- `ChatRequest.extraBody [String: Any]?` consistent Tasks 1-2-3
- `ChatChunk.reasoningDelta String?` consistent Tasks 1-3-7
- `SettingsViewModel.toggleThinking(for:)` + `saveTools()` consistent Tasks 4-6-7
- `ProviderThinkingTemplate` enum consistent Tasks 4-5

**Spec deviation noted:** `ChatRequest` keeps Codable (spec said remove). Reason: less invasive to OpenAICompatibleProvider.buildURLRequest which already uses `JSONEncoder().encode(request)`; only `extraBody` is excluded from Codable via CodingKeys. This is a stronger design — captured in Task 1's notes.

---

## Execution

Plan complete. Estimated total: **~3.5-4 days** (matches spec).
