# SliceAI MVP v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship SliceAI v0.1 — a macOS-native open-source toolbar that triggers on text selection, sends the selection through user-configurable prompts to OpenAI-compatible LLMs, and streams Markdown results in a floating panel. Deliverable: unsigned DMG, working end-to-end on user's Mac.

**Architecture:** Single Local Swift Package (`SliceAIKit`) with 7 targets wrapped by a minimal Xcode App target. `SliceCore` is zero-UI domain layer; `LLMProviders` implements OpenAI-compatible SSE streaming; `SelectionCapture` combines AX API with Cmd+C fallback; `Windowing` hosts three NSPanel types; `HotkeyManager` uses Carbon; `SettingsUI` is SwiftUI; `Permissions` handles first-run onboarding. Dependency injection via protocols, no singletons.

**Tech Stack:** Swift 6.0 (strict concurrency), SwiftUI, AppKit, Carbon HotKey API, XCTest, Swift Package Manager, GitHub Actions, SwiftLint, swift-format.

**Reference spec:** `docs/superpowers/specs/2026-04-20-sliceai-design.md`

---

## File Structure

```
SliceAI/
├── .github/workflows/
│   ├── ci.yml                          # swift build + test + lint on PR/push
│   └── release.yml                     # build unsigned DMG on tag
├── .gitignore                          # already exists
├── .swiftlint.yml                      # Task 3
├── .swift-format                       # Task 3
├── LICENSE                             # MIT (Task 5)
├── README.md                           # Task 5
├── SliceAIKit/                         # Local Swift Package (all 7 modules)
│   ├── Package.swift                   # Task 2
│   ├── Sources/
│   │   ├── SliceCore/                  # Phase 1 - domain layer
│   │   │   ├── SelectionPayload.swift
│   │   │   ├── Tool.swift
│   │   │   ├── Provider.swift
│   │   │   ├── Configuration.swift
│   │   │   ├── ChatTypes.swift
│   │   │   ├── LLMProvider.swift
│   │   │   ├── PromptTemplate.swift
│   │   │   ├── SliceError.swift
│   │   │   ├── ConfigurationProviding.swift
│   │   │   ├── KeychainAccessing.swift
│   │   │   ├── ToolExecutor.swift
│   │   │   └── DefaultConfiguration.swift
│   │   ├── LLMProviders/               # Phase 2
│   │   │   ├── SSEDecoder.swift
│   │   │   ├── OpenAIDTOs.swift
│   │   │   └── OpenAICompatibleProvider.swift
│   │   ├── SelectionCapture/           # Phase 3
│   │   │   ├── SelectionSource.swift
│   │   │   ├── PasteboardProtocol.swift
│   │   │   ├── ClipboardSelectionSource.swift
│   │   │   ├── AXSelectionSource.swift
│   │   │   └── SelectionService.swift
│   │   ├── HotkeyManager/              # Phase 4
│   │   │   ├── Hotkey.swift
│   │   │   └── HotkeyRegistrar.swift
│   │   ├── Windowing/                  # Phase 5
│   │   │   ├── ScreenAwarePositioner.swift
│   │   │   ├── PanelStyle.swift
│   │   │   ├── FloatingToolbarPanel.swift
│   │   │   ├── CommandPalettePanel.swift
│   │   │   ├── ResultPanel.swift
│   │   │   └── StreamingMarkdownView.swift
│   │   ├── Permissions/                # Phase 6
│   │   │   ├── AccessibilityMonitor.swift
│   │   │   └── OnboardingFlow.swift
│   │   └── SettingsUI/                 # Phase 7
│   │       ├── ConfigurationStore.swift
│   │       ├── KeychainStore.swift
│   │       ├── SettingsScene.swift
│   │       ├── ToolEditorView.swift
│   │       ├── ProviderEditorView.swift
│   │       └── HotkeyEditorView.swift
│   └── Tests/
│       ├── SliceCoreTests/
│       ├── LLMProvidersTests/
│       │   └── Fixtures/               # SSE fixtures
│       ├── SelectionCaptureTests/
│       ├── HotkeyManagerTests/
│       └── WindowingTests/
├── SliceAI.xcodeproj/                  # Phase 8 (manual Xcode setup)
├── SliceAIApp/                         # Phase 8
│   ├── SliceAIApp.swift                # @main
│   ├── AppDelegate.swift
│   ├── MenuBarController.swift
│   ├── AppContainer.swift              # DI composition root
│   ├── Info.plist
│   └── Assets.xcassets/
├── config.schema.json                  # Task 9 (JSON Schema for config)
├── docs/superpowers/
│   ├── specs/2026-04-20-sliceai-design.md  # exists
│   └── plans/2026-04-20-sliceai-mvp-v01.md # this file
└── scripts/
    ├── build-dmg.sh                    # Phase 9
    └── install-dev.sh                  # Phase 9 (helper)
```

---

## Milestones

- **M1 — Project green (end of Phase 0)**: SPM builds clean, CI runs on push, README/LICENSE in place
- **M2 — Testable core (end of Phase 2)**: `SliceCore` + `LLMProviders` pass all tests; can hand-call `OpenAICompatibleProvider.stream()` against real OpenAI API
- **M3 — Input stack (end of Phase 4)**: Selection capture + hotkeys have unit tests + manual smoke verification
- **M4 — UI stack (end of Phase 7)**: All three NSPanels render; Settings GUI works with sample config
- **M5 — Integrated app (end of Phase 8)**: Full app runs end-to-end: select text → toolbar → click tool → LLM streams result
- **M6 — Shippable (end of Phase 9)**: `SliceAI-0.1.0.dmg` built by CI, installs on fresh Mac

---

## Phase 0 — Project Bootstrap

### Task 1: Initialize Swift Package

**Files:**
- Create: `SliceAIKit/Package.swift`
- Create: `SliceAIKit/Sources/SliceCore/.gitkeep` (and 6 other module stubs)

- [ ] **Step 1.1:** Create SliceAIKit directory structure

```bash
cd /Users/majiajun/workspace/SliceAI
mkdir -p SliceAIKit/Sources/{SliceCore,LLMProviders,SelectionCapture,HotkeyManager,Windowing,Permissions,SettingsUI}
mkdir -p SliceAIKit/Tests/{SliceCoreTests,LLMProvidersTests,SelectionCaptureTests,HotkeyManagerTests,WindowingTests}
mkdir -p SliceAIKit/Tests/LLMProvidersTests/Fixtures
touch SliceAIKit/Sources/{SliceCore,LLMProviders,SelectionCapture,HotkeyManager,Windowing,Permissions,SettingsUI}/.gitkeep
touch SliceAIKit/Tests/{SliceCoreTests,LLMProvidersTests,SelectionCaptureTests,HotkeyManagerTests,WindowingTests}/.gitkeep
```

Expected: directories created.

- [ ] **Step 1.2:** Commit scaffold

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/
git commit -m "chore: scaffold SliceAIKit SPM directory structure"
```

### Task 2: Define Package.swift with 7 targets

**Files:**
- Create: `SliceAIKit/Package.swift`

- [ ] **Step 2.1:** Write Package.swift

```swift
// swift-tools-version:6.0
// SliceAIKit - SliceAI 核心功能包，7 个 target 承载领域层、LLM 调用、划词捕获、快捷键、窗口、权限、设置界面
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // 启用 Swift 6 严格并发检查，所有类型强制 Sendable
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableExperimentalFeature("StrictConcurrency=complete"),
]

let package = Package(
    name: "SliceAIKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SliceCore", targets: ["SliceCore"]),
        .library(name: "LLMProviders", targets: ["LLMProviders"]),
        .library(name: "SelectionCapture", targets: ["SelectionCapture"]),
        .library(name: "HotkeyManager", targets: ["HotkeyManager"]),
        .library(name: "Windowing", targets: ["Windowing"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "SettingsUI", targets: ["SettingsUI"]),
    ],
    targets: [
        .target(name: "SliceCore", swiftSettings: swiftSettings),
        .target(name: "LLMProviders", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "SelectionCapture", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "HotkeyManager", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "Windowing", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "Permissions", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "SettingsUI",
                dependencies: ["SliceCore", "LLMProviders", "HotkeyManager"],
                swiftSettings: swiftSettings),
        .testTarget(name: "SliceCoreTests", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .testTarget(name: "LLMProvidersTests",
                    dependencies: ["LLMProviders", "SliceCore"],
                    resources: [.copy("Fixtures")],
                    swiftSettings: swiftSettings),
        .testTarget(name: "SelectionCaptureTests",
                    dependencies: ["SelectionCapture", "SliceCore"],
                    swiftSettings: swiftSettings),
        .testTarget(name: "HotkeyManagerTests",
                    dependencies: ["HotkeyManager", "SliceCore"],
                    swiftSettings: swiftSettings),
        .testTarget(name: "WindowingTests",
                    dependencies: ["Windowing", "SliceCore"],
                    swiftSettings: swiftSettings),
    ]
)
```

- [ ] **Step 2.2:** Verify package builds (with empty targets we need at least one stub Swift file)

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit
# 每个 target 至少需要一个 Swift 文件
for m in SliceCore LLMProviders SelectionCapture HotkeyManager Windowing Permissions SettingsUI; do
  echo "// Module marker" > "Sources/$m/_ModuleMarker.swift"
done
for m in SliceCoreTests LLMProvidersTests SelectionCaptureTests HotkeyManagerTests WindowingTests; do
  echo "import XCTest" > "Tests/$m/_TestMarker.swift"
done
swift build
```

Expected: `Build complete!` with zero warnings.

- [ ] **Step 2.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/
git commit -m "chore: add Package.swift with 7 library targets + strict concurrency"
```

### Task 3: Linting & Formatting Config

**Files:**
- Create: `.swiftlint.yml`
- Create: `.swift-format`

- [ ] **Step 3.1:** Write `.swiftlint.yml`

```yaml
# SliceAI SwiftLint 配置，开源项目的宽松但有原则的风格
disabled_rules:
  - trailing_whitespace
  - identifier_name   # 业务缩写常见 (AX, LLM, SSE)，不做强制

opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - force_unwrapping
  - implicit_return
  - redundant_nil_coalescing
  - sorted_imports
  - toggle_bool
  - unused_import

line_length:
  warning: 120
  error: 160

file_length:
  warning: 500      # 对应 spec §9.3 "文件行数 ≤ 500 行"
  error: 700

function_body_length:
  warning: 40
  error: 80

type_body_length:
  warning: 250
  error: 400

cyclomatic_complexity:
  warning: 12
  error: 20

included:
  - SliceAIKit/Sources
  - SliceAIApp

excluded:
  - .build
  - SliceAIKit/.build
  - SliceAIKit/Tests/*/Fixtures
```

- [ ] **Step 3.2:** Write `.swift-format`

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 },
  "tabWidth": 4,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": false,
  "prioritizeKeepingFunctionOutputTogether": true,
  "indentConditionalCompilationBlocks": true,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": true,
    "AlwaysUseLowerCamelCase": false,
    "AmbiguousTrailingClosureOverload": true,
    "NoLeadingUnderscores": false,
    "UseLetInEveryBoundCaseVariable": true,
    "UseSingleLinePropertyGetter": true
  }
}
```

- [ ] **Step 3.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add .swiftlint.yml .swift-format
git commit -m "chore: add SwiftLint and swift-format config"
```

### Task 4: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 4.1:** Write CI YAML

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    name: Build & Test
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 16
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Swift version
        run: swift --version

      - name: Build SliceAIKit
        working-directory: SliceAIKit
        run: swift build -v

      - name: Test SliceAIKit
        working-directory: SliceAIKit
        run: swift test --parallel --enable-code-coverage

      - name: Install SwiftLint
        run: brew install swiftlint

      - name: Run SwiftLint
        run: swiftlint lint --strict
```

- [ ] **Step 4.2:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for build + test + lint"
```

### Task 5: README + LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

- [ ] **Step 5.1:** Write MIT LICENSE

```
MIT License

Copyright (c) 2026 SliceAI Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 5.2:** Write README.md stub (full content populated over time; minimum needed to publish)

```markdown
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

## License

MIT — see [LICENSE](LICENSE)
```

- [ ] **Step 5.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add README.md LICENSE
git commit -m "docs: add README and MIT LICENSE"
```

**M1 reached:** SPM project compiles, CI workflow defined, README/LICENSE in place. You can push to GitHub and see CI run at this point (though no meaningful tests yet).

---

## Phase 1 — SliceCore Domain Layer

Phase goal: all domain types, protocols, and the `ToolExecutor` actor fully implemented with ≥ 90% test coverage.

### Task 6: SelectionPayload + tests

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift`
- Delete: `SliceAIKit/Sources/SliceCore/_ModuleMarker.swift`

- [ ] **Step 6.1:** Write failing test

```swift
// SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift
import XCTest
@testable import SliceCore

final class SelectionPayloadTests: XCTestCase {
    func test_equatableByAllFields() {
        // 两个 payload 所有字段相等时应当 ==
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SelectionPayload(
            text: "hi", appBundleID: "com.apple.Safari", appName: "Safari",
            url: URL(string: "https://example.com"), screenPoint: CGPoint(x: 10, y: 20),
            source: .accessibility, timestamp: date
        )
        let b = SelectionPayload(
            text: "hi", appBundleID: "com.apple.Safari", appName: "Safari",
            url: URL(string: "https://example.com"), screenPoint: CGPoint(x: 10, y: 20),
            source: .accessibility, timestamp: date
        )
        XCTAssertEqual(a, b)
    }

    func test_sourceRawValuesStable() {
        // rawValue 是 Codable 持久化基础，必须稳定
        XCTAssertEqual(SelectionPayload.Source.accessibility.rawValue, "accessibility")
        XCTAssertEqual(SelectionPayload.Source.clipboardFallback.rawValue, "clipboardFallback")
    }
}
```

- [ ] **Step 6.2:** Run to verify fail

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit
swift test --filter SelectionPayloadTests 2>&1 | tail -20
```

Expected: FAIL with "cannot find 'SelectionPayload' in scope"

- [ ] **Step 6.3:** Implement type

```swift
// SliceAIKit/Sources/SliceCore/SelectionPayload.swift
import Foundation

/// 划词事件的载荷，在 SelectionCapture 与 Windowing / ToolExecutor 之间传递
public struct SelectionPayload: Sendable, Equatable, Codable {
    public let text: String
    public let appBundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint
    public let source: Source
    public let timestamp: Date

    public init(
        text: String, appBundleID: String, appName: String,
        url: URL?, screenPoint: CGPoint, source: Source, timestamp: Date
    ) {
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.url = url
        self.screenPoint = screenPoint
        self.source = source
        self.timestamp = timestamp
    }

    /// 选中文字的来源，用于日志与诊断
    public enum Source: String, Sendable, Codable {
        case accessibility       // 通过 AX API 直接读取
        case clipboardFallback   // 通过模拟 Cmd+C + 剪贴板备份恢复获取
    }
}
```

- [ ] **Step 6.4:** Delete module marker

```bash
rm /Users/majiajun/workspace/SliceAI/SliceAIKit/Sources/SliceCore/_ModuleMarker.swift
```

- [ ] **Step 6.5:** Run tests

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit
swift test --filter SelectionPayloadTests
```

Expected: PASS 2 tests

- [ ] **Step 6.6:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/SelectionPayload.swift SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift
git rm SliceAIKit/Sources/SliceCore/_ModuleMarker.swift 2>/dev/null || true
git commit -m "feat(core): add SelectionPayload with source enum"
```

### Task 7: ChatTypes (ChatMessage / ChatRequest / ChatChunk)

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ChatTypes.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift`

- [ ] **Step 7.1:** Write failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift
import XCTest
@testable import SliceCore

final class ChatTypesTests: XCTestCase {
    func test_chatMessageEncoding_systemRole() throws {
        let msg = ChatMessage(role: .system, content: "You are helpful.")
        let data = try JSONEncoder().encode(msg)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\"role\":\"system\""))
        XCTAssertTrue(s.contains("\"content\":\"You are helpful.\""))
    }

    func test_chatRequest_nilFieldsOmitted() throws {
        // temperature/maxTokens 为 nil 时必须不出现在 JSON 中，保持服务端默认
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: nil, maxTokens: nil)
        let data = try JSONEncoder().encode(req)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(s.contains("temperature"))
        XCTAssertFalse(s.contains("max_tokens"))
        XCTAssertTrue(s.contains("\"model\":\"gpt-5\""))
    }

    func test_chatRequest_nonNilFieldsPresent() throws {
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: 0.5, maxTokens: 100)
        let data = try JSONEncoder().encode(req)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\"temperature\":0.5"))
        XCTAssertTrue(s.contains("\"max_tokens\":100"))
    }
}
```

- [ ] **Step 7.2:** Run and verify fail

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit
swift test --filter ChatTypesTests
```

Expected: FAIL — types not defined

- [ ] **Step 7.3:** Implement

```swift
// SliceAIKit/Sources/SliceCore/ChatTypes.swift
import Foundation

/// 角色，对应 OpenAI Chat Completions 的 role 字段
public enum Role: String, Sendable, Codable {
    case system, user, assistant
}

/// 单条消息
public struct ChatMessage: Sendable, Codable, Equatable {
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// 聊天请求
/// nil 的 temperature / maxTokens 会被序列化省略，保持服务端默认
public struct ChatRequest: Sendable, Codable, Equatable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?

    public init(model: String, messages: [ChatMessage],
                temperature: Double? = nil, maxTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// 完成原因
public enum FinishReason: String, Sendable, Codable {
    case stop, length, contentFilter = "content_filter", toolCalls = "tool_calls"
}

/// 流式 chunk（delta 为增量文本，finishReason 仅在最后一个 chunk 非 nil）
public struct ChatChunk: Sendable, Equatable {
    public let delta: String
    public let finishReason: FinishReason?

    public init(delta: String, finishReason: FinishReason? = nil) {
        self.delta = delta
        self.finishReason = finishReason
    }
}
```

- [ ] **Step 7.4:** Run tests

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter ChatTypesTests
```

Expected: PASS 3 tests

- [ ] **Step 7.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/ChatTypes.swift SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift
git commit -m "feat(core): add Chat types with JSON-compliant omission of nil params"
```

### Task 8: Tool + Provider + DisplayMode

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/Tool.swift`
- Create: `SliceAIKit/Sources/SliceCore/Provider.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift`

- [ ] **Step 8.1:** Write failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/ToolTests.swift
import XCTest
@testable import SliceCore

final class ToolTests: XCTestCase {
    func test_toolCodable_roundTrip() throws {
        let tool = Tool(
            id: "translate", name: "Translate", icon: "🌐", description: nil,
            systemPrompt: "sys", userPrompt: "u {{selection}}",
            providerId: "openai", modelId: nil, temperature: 0.3,
            displayMode: .window, variables: ["language": "English"]
        )
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(Tool.self, from: data)
        XCTAssertEqual(decoded, tool)
    }

    func test_displayMode_rawValues() {
        XCTAssertEqual(DisplayMode.window.rawValue, "window")
        XCTAssertEqual(DisplayMode.bubble.rawValue, "bubble")
        XCTAssertEqual(DisplayMode.replace.rawValue, "replace")
    }

    func test_providerCodable_roundTrip() throws {
        let p = Provider(id: "openai", name: "OpenAI",
                         baseURL: URL(string: "https://api.openai.com/v1")!,
                         apiKeyRef: "keychain:openai", defaultModel: "gpt-5")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Provider.self, from: data)
        XCTAssertEqual(decoded, p)
    }
}
```

- [ ] **Step 8.2:** Run — verify fail

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter ToolTests
```

- [ ] **Step 8.3:** Implement Tool

```swift
// SliceAIKit/Sources/SliceCore/Tool.swift
import Foundation

/// 工具定义，一个 Tool 代表菜单栏上的一个按钮 + 一套 prompt
public struct Tool: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var icon: String              // emoji 或 SF Symbol 名
    public var description: String?
    public var systemPrompt: String?
    public var userPrompt: String
    public var providerId: String        // 指向 Configuration.providers 中的 Provider.id
    public var modelId: String?          // nil 则使用 Provider.defaultModel
    public var temperature: Double?
    public var displayMode: DisplayMode
    public var variables: [String: String]

    public init(
        id: String, name: String, icon: String, description: String?,
        systemPrompt: String?, userPrompt: String,
        providerId: String, modelId: String?, temperature: Double?,
        displayMode: DisplayMode, variables: [String: String]
    ) {
        self.id = id; self.name = name; self.icon = icon
        self.description = description
        self.systemPrompt = systemPrompt; self.userPrompt = userPrompt
        self.providerId = providerId; self.modelId = modelId
        self.temperature = temperature
        self.displayMode = displayMode
        self.variables = variables
    }
}

/// 结果展示模式（MVP v0.1 只实现 .window，另外两种预留给 v0.2+）
public enum DisplayMode: String, Sendable, Codable, CaseIterable {
    case window    // A - 独立浮窗
    case bubble    // B - v0.2
    case replace   // C - v0.2
}
```

- [ ] **Step 8.4:** Implement Provider

```swift
// SliceAIKit/Sources/SliceCore/Provider.swift
import Foundation

/// LLM 供应商配置（API Key 不在此结构内，通过 apiKeyRef 指向 Keychain）
public struct Provider: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var apiKeyRef: String     // 如 "keychain:openai-official"
    public var defaultModel: String

    public init(id: String, name: String, baseURL: URL,
                apiKeyRef: String, defaultModel: String) {
        self.id = id; self.name = name
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.defaultModel = defaultModel
    }
}
```

- [ ] **Step 8.5:** Run tests

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter ToolTests
```

Expected: PASS 3 tests

- [ ] **Step 8.6:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/Tool.swift SliceAIKit/Sources/SliceCore/Provider.swift SliceAIKit/Tests/SliceCoreTests/ToolTests.swift
git commit -m "feat(core): add Tool, Provider, and DisplayMode types"
```

### Task 9: Configuration aggregate + JSON schema file

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/Configuration.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`
- Create: `config.schema.json`

- [ ] **Step 9.1:** Failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift
import XCTest
@testable import SliceCore

final class ConfigurationTests: XCTestCase {
    func test_configuration_defaultDecoding() throws {
        let json = """
        {
          "schemaVersion": 1,
          "providers": [],
          "tools": [],
          "hotkeys": { "toggleCommandPalette": "option+space" },
          "triggers": {
            "floatingToolbarEnabled": true,
            "commandPaletteEnabled": true,
            "minimumSelectionLength": 1,
            "triggerDelayMs": 150
          },
          "telemetry": { "enabled": false },
          "appBlocklist": []
        }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(Configuration.self, from: json)
        XCTAssertEqual(cfg.schemaVersion, 1)
        XCTAssertEqual(cfg.hotkeys.toggleCommandPalette, "option+space")
        XCTAssertEqual(cfg.triggers.triggerDelayMs, 150)
        XCTAssertFalse(cfg.telemetry.enabled)
    }
}
```

- [ ] **Step 9.2:** Run — fail

- [ ] **Step 9.3:** Implement

```swift
// SliceAIKit/Sources/SliceCore/Configuration.swift
import Foundation

/// 整个应用的持久化配置，对应 config.json
public struct Configuration: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public var providers: [Provider]
    public var tools: [Tool]
    public var hotkeys: HotkeyBindings
    public var triggers: TriggerSettings
    public var telemetry: TelemetrySettings
    public var appBlocklist: [String]

    public init(schemaVersion: Int, providers: [Provider], tools: [Tool],
                hotkeys: HotkeyBindings, triggers: TriggerSettings,
                telemetry: TelemetrySettings, appBlocklist: [String]) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.tools = tools
        self.hotkeys = hotkeys
        self.triggers = triggers
        self.telemetry = telemetry
        self.appBlocklist = appBlocklist
    }

    public static let currentSchemaVersion = 1
}

/// 快捷键绑定
public struct HotkeyBindings: Sendable, Codable, Equatable {
    public var toggleCommandPalette: String     // "option+space"

    public init(toggleCommandPalette: String) {
        self.toggleCommandPalette = toggleCommandPalette
    }
}

/// 触发行为设置
public struct TriggerSettings: Sendable, Codable, Equatable {
    public var floatingToolbarEnabled: Bool
    public var commandPaletteEnabled: Bool
    public var minimumSelectionLength: Int       // 小于此长度不触发浮条
    public var triggerDelayMs: Int               // mouseUp 后 debounce 毫秒

    public init(floatingToolbarEnabled: Bool, commandPaletteEnabled: Bool,
                minimumSelectionLength: Int, triggerDelayMs: Int) {
        self.floatingToolbarEnabled = floatingToolbarEnabled
        self.commandPaletteEnabled = commandPaletteEnabled
        self.minimumSelectionLength = minimumSelectionLength
        self.triggerDelayMs = triggerDelayMs
    }
}

/// 遥测设置，MVP v0.1 只有开关
public struct TelemetrySettings: Sendable, Codable, Equatable {
    public var enabled: Bool

    public init(enabled: Bool) { self.enabled = enabled }
}
```

- [ ] **Step 9.4:** Write JSON schema

```json
// config.schema.json （放在 repo 根目录）
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/<owner>/SliceAI/blob/main/config.schema.json",
  "title": "SliceAI Configuration",
  "type": "object",
  "required": ["schemaVersion", "providers", "tools", "hotkeys", "triggers", "telemetry", "appBlocklist"],
  "properties": {
    "schemaVersion": { "type": "integer", "const": 1 },
    "providers": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "name", "baseURL", "apiKeyRef", "defaultModel"],
        "properties": {
          "id": { "type": "string" },
          "name": { "type": "string" },
          "baseURL": { "type": "string", "format": "uri" },
          "apiKeyRef": { "type": "string", "pattern": "^keychain:" },
          "defaultModel": { "type": "string" }
        }
      }
    },
    "tools": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "name", "icon", "userPrompt", "providerId", "displayMode", "variables"],
        "properties": {
          "id": { "type": "string" },
          "name": { "type": "string" },
          "icon": { "type": "string" },
          "description": { "type": ["string", "null"] },
          "systemPrompt": { "type": ["string", "null"] },
          "userPrompt": { "type": "string" },
          "providerId": { "type": "string" },
          "modelId": { "type": ["string", "null"] },
          "temperature": { "type": ["number", "null"] },
          "displayMode": { "type": "string", "enum": ["window", "bubble", "replace"] },
          "variables": {
            "type": "object",
            "additionalProperties": { "type": "string" }
          }
        }
      }
    },
    "hotkeys": {
      "type": "object",
      "required": ["toggleCommandPalette"],
      "properties": { "toggleCommandPalette": { "type": "string" } }
    },
    "triggers": {
      "type": "object",
      "required": ["floatingToolbarEnabled", "commandPaletteEnabled", "minimumSelectionLength", "triggerDelayMs"],
      "properties": {
        "floatingToolbarEnabled": { "type": "boolean" },
        "commandPaletteEnabled": { "type": "boolean" },
        "minimumSelectionLength": { "type": "integer", "minimum": 1 },
        "triggerDelayMs": { "type": "integer", "minimum": 0, "maximum": 5000 }
      }
    },
    "telemetry": {
      "type": "object",
      "required": ["enabled"],
      "properties": { "enabled": { "type": "boolean" } }
    },
    "appBlocklist": {
      "type": "array",
      "items": { "type": "string" }
    }
  }
}
```

- [ ] **Step 9.5:** Run tests

- [ ] **Step 9.6:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/Configuration.swift SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift config.schema.json
git commit -m "feat(core): add Configuration aggregate and JSON schema file"
```

### Task 10: PromptTemplate

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/PromptTemplate.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/PromptTemplateTests.swift`

- [ ] **Step 10.1:** Failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/PromptTemplateTests.swift
import XCTest
@testable import SliceCore

final class PromptTemplateTests: XCTestCase {
    func test_render_replacesSingleVariable() {
        let out = PromptTemplate.render("Hello {{name}}", variables: ["name": "World"])
        XCTAssertEqual(out, "Hello World")
    }

    func test_render_multipleVariables() {
        let out = PromptTemplate.render(
            "{{a}} and {{b}} and {{a}}",
            variables: ["a": "X", "b": "Y"]
        )
        XCTAssertEqual(out, "X and Y and X")
    }

    func test_render_unknownVariableKeptAsIs() {
        // 未定义的变量保留原文，便于用户在 UI 发现错字
        let out = PromptTemplate.render("Hello {{nope}}", variables: [:])
        XCTAssertEqual(out, "Hello {{nope}}")
    }

    func test_render_emptyTemplate() {
        XCTAssertEqual(PromptTemplate.render("", variables: ["a": "b"]), "")
    }

    func test_render_variableWithSpaces() {
        // 变量名内不允许空格，有空格的占位符原样保留
        let out = PromptTemplate.render("{{ has space }}", variables: ["has space": "x"])
        XCTAssertEqual(out, "{{ has space }}")
    }

    func test_render_variableWithSpecialChars() {
        let out = PromptTemplate.render("{{selection}}", variables: ["selection": "$pecial/chars\\"])
        XCTAssertEqual(out, "$pecial/chars\\")
    }
}
```

- [ ] **Step 10.2:** Run — fail

- [ ] **Step 10.3:** Implement

```swift
// SliceAIKit/Sources/SliceCore/PromptTemplate.swift
import Foundation

/// 轻量 {{variable}} 模板渲染器
/// 不支持循环 / 条件 / filter；保留语义极简以降低贡献门槛
public enum PromptTemplate {

    /// 渲染模板：将 {{name}} 替换为 variables[name]，未定义变量保留原样
    /// - Parameters:
    ///   - template: 含占位符的模板字符串
    ///   - variables: 变量表，key 为 {{}} 内的标识符
    /// - Returns: 渲染后的字符串
    public static func render(_ template: String, variables: [String: String]) -> String {
        guard !template.isEmpty else { return template }

        // 用正则匹配 {{identifier}}。identifier 只允许字母数字 / 下划线 / 连字符
        // 空白、换行都会使占位符保留原样
        let pattern = #"\{\{([A-Za-z][A-Za-z0-9_\-]*)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }

        let ns = template as NSString
        var result = ""
        var cursor = 0
        let fullRange = NSRange(location: 0, length: ns.length)

        regex.enumerateMatches(in: template, range: fullRange) { match, _, _ in
            guard let match else { return }
            let wholeRange = match.range
            let nameRange = match.range(at: 1)
            // 追加命中前的原文
            if wholeRange.location > cursor {
                result += ns.substring(with: NSRange(location: cursor,
                                                     length: wholeRange.location - cursor))
            }
            let name = ns.substring(with: nameRange)
            if let value = variables[name] {
                result += value
            } else {
                // 未知变量保留原占位符
                result += ns.substring(with: wholeRange)
            }
            cursor = wholeRange.location + wholeRange.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }
}
```

- [ ] **Step 10.4:** Run — pass

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter PromptTemplateTests
```

Expected: PASS 6 tests

- [ ] **Step 10.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/PromptTemplate.swift SliceAIKit/Tests/SliceCoreTests/PromptTemplateTests.swift
git commit -m "feat(core): add PromptTemplate with {{var}} syntax"
```

### Task 11: SliceError hierarchy

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/SliceError.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift`

- [ ] **Step 11.1:** Failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift
import XCTest
@testable import SliceCore

final class SliceErrorTests: XCTestCase {
    func test_userMessage_forEachCategory() {
        XCTAssertFalse(SliceError.permission(.accessibilityDenied).userMessage.isEmpty)
        XCTAssertFalse(SliceError.selection(.axEmpty).userMessage.isEmpty)
        XCTAssertFalse(SliceError.provider(.unauthorized).userMessage.isEmpty)
        XCTAssertFalse(SliceError.configuration(.fileNotFound).userMessage.isEmpty)
    }

    func test_providerRateLimited_includesRetryAfter() {
        let msg = SliceError.provider(.rateLimited(retryAfter: 30)).userMessage
        XCTAssertTrue(msg.contains("30"))
    }

    func test_developerContext_noSensitive() {
        // developerContext 用于日志，绝不包含 API Key 或选中文字
        let err = SliceError.provider(.unauthorized)
        XCTAssertFalse(err.developerContext.lowercased().contains("sk-"))
    }
}
```

- [ ] **Step 11.2:** Run — fail

- [ ] **Step 11.3:** Implement

```swift
// SliceAIKit/Sources/SliceCore/SliceError.swift
import Foundation

/// 应用级统一错误，每类都有 userMessage（给用户看）与 developerContext（日志）
public enum SliceError: Error, Sendable, Equatable {
    case selection(SelectionError)
    case provider(ProviderError)
    case configuration(ConfigurationError)
    case permission(PermissionError)

    /// 面向最终用户的友好错误文案
    public var userMessage: String {
        switch self {
        case .selection(let e): return e.userMessage
        case .provider(let e): return e.userMessage
        case .configuration(let e): return e.userMessage
        case .permission(let e): return e.userMessage
        }
    }

    /// 用于日志打印的开发者上下文，不含敏感信息
    public var developerContext: String {
        switch self {
        case .selection(let e): return "selection.\(e)"
        case .provider(let e): return "provider.\(e)"
        case .configuration(let e): return "configuration.\(e)"
        case .permission(let e): return "permission.\(e)"
        }
    }
}

public enum SelectionError: Error, Sendable, Equatable {
    case axUnavailable
    case axEmpty
    case clipboardTimeout
    case textTooLong(Int)

    public var userMessage: String {
        switch self {
        case .axUnavailable: return "SliceAI 需要辅助功能权限才能读取你选中的文字。"
        case .axEmpty: return "无法读取当前选中的文字，请确认已选中文本。"
        case .clipboardTimeout: return "读取选中文字超时，请再试一次。"
        case .textTooLong(let n): return "选中的文字过长（\(n) 字符），请缩短选区。"
        }
    }
}

public enum ProviderError: Error, Sendable, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case networkTimeout
    case invalidResponse(String)
    case sseParseError(String)

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "API Key 无效或未设置，请在设置中检查。"
        case .rateLimited(let t):
            if let t { return "请求过于频繁，请 \(Int(t)) 秒后重试。" }
            return "请求过于频繁，请稍后重试。"
        case .serverError(let code):
            return "服务端返回错误（HTTP \(code)），请稍后重试或切换模型。"
        case .networkTimeout:
            return "网络请求超时，请检查连接。"
        case .invalidResponse:
            return "服务端响应异常，无法解析。"
        case .sseParseError:
            return "接收到的流式数据格式无法识别。"
        }
    }
}

public enum ConfigurationError: Error, Sendable, Equatable {
    case fileNotFound
    case schemaVersionTooNew(Int)
    case invalidJSON(String)
    case referencedProviderMissing(String)

    public var userMessage: String {
        switch self {
        case .fileNotFound:
            return "找不到配置文件，将使用默认配置。"
        case .schemaVersionTooNew(let v):
            return "配置文件的 schemaVersion=\(v) 高于当前应用支持版本，请升级 SliceAI。"
        case .invalidJSON:
            return "配置文件 JSON 格式不正确，请参考 config.schema.json 校验。"
        case .referencedProviderMissing(let id):
            return "工具引用的供应商 \"\(id)\" 不存在。"
        }
    }
}

public enum PermissionError: Error, Sendable, Equatable {
    case accessibilityDenied
    case inputMonitoringDenied

    public var userMessage: String {
        switch self {
        case .accessibilityDenied:
            return "辅助功能权限未授予，SliceAI 无法读取划词。"
        case .inputMonitoringDenied:
            return "输入监控权限未授予，快捷键可能无法工作。"
        }
    }
}
```

- [ ] **Step 11.4:** Run — pass

- [ ] **Step 11.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/SliceError.swift SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift
git commit -m "feat(core): add SliceError hierarchy with user-facing messages"
```

### Task 12: LLMProvider protocol + ConfigurationProviding + KeychainAccessing

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/LLMProvider.swift`
- Create: `SliceAIKit/Sources/SliceCore/ConfigurationProviding.swift`
- Create: `SliceAIKit/Sources/SliceCore/KeychainAccessing.swift`

Protocols have minimal behavior to test directly; they're exercised by `ToolExecutor` tests in Task 14.

- [ ] **Step 12.1:** Implement LLMProvider

```swift
// SliceAIKit/Sources/SliceCore/LLMProvider.swift
import Foundation

/// LLM 调用的抽象协议，所有供应商（OpenAI 兼容 / 未来的 Anthropic / Gemini）必须实现
public protocol LLMProvider: Sendable {
    /// 流式调用。失败时 AsyncStream 会 throw SliceError.provider
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, Error>
}

/// 工厂：根据 Provider 配置创建对应的 LLMProvider
public protocol LLMProviderFactory: Sendable {
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider
}
```

- [ ] **Step 12.2:** Implement ConfigurationProviding

```swift
// SliceAIKit/Sources/SliceCore/ConfigurationProviding.swift
import Foundation

/// 提供当前 Configuration 的协议。SettingsUI 持有并发布 updates
public protocol ConfigurationProviding: Sendable {
    func current() async -> Configuration
    func update(_ configuration: Configuration) async throws
}
```

- [ ] **Step 12.3:** Implement KeychainAccessing

```swift
// SliceAIKit/Sources/SliceCore/KeychainAccessing.swift
import Foundation

/// Keychain 抽象，便于单元测试注入假实现
public protocol KeychainAccessing: Sendable {
    /// 读取 API Key；不存在返回 nil
    func readAPIKey(providerId: String) async throws -> String?

    /// 写入或覆盖 API Key
    func writeAPIKey(_ value: String, providerId: String) async throws

    /// 删除（可选使用）
    func deleteAPIKey(providerId: String) async throws
}
```

- [ ] **Step 12.4:** Build verify

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
```

- [ ] **Step 12.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/LLMProvider.swift SliceAIKit/Sources/SliceCore/ConfigurationProviding.swift SliceAIKit/Sources/SliceCore/KeychainAccessing.swift
git commit -m "feat(core): add LLMProvider, ConfigurationProviding, KeychainAccessing protocols"
```

### Task 13: DefaultConfiguration factory (4 built-in tools)

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/DefaultConfigurationTests.swift`

- [ ] **Step 13.1:** Failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/DefaultConfigurationTests.swift
import XCTest
@testable import SliceCore

final class DefaultConfigurationTests: XCTestCase {
    func test_defaultConfig_hasFourTools() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.tools.count, 4)
        let ids = Set(cfg.tools.map(\.id))
        XCTAssertEqual(ids, ["translate", "polish", "summarize", "explain"])
    }

    func test_defaultConfig_hasOneProvider() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.providers.count, 1)
        XCTAssertEqual(cfg.providers.first?.id, "openai-official")
    }

    func test_defaultConfig_allToolsReferValidProvider() {
        let cfg = DefaultConfiguration.initial()
        let providerIds = Set(cfg.providers.map(\.id))
        for tool in cfg.tools {
            XCTAssertTrue(providerIds.contains(tool.providerId), "Tool \(tool.id) refers missing provider \(tool.providerId)")
        }
    }

    func test_defaultConfig_promptsContainSelection() {
        for tool in DefaultConfiguration.initial().tools {
            XCTAssertTrue(tool.userPrompt.contains("{{selection}}"), "Tool \(tool.id) missing {{selection}} in userPrompt")
        }
    }
}
```

- [ ] **Step 13.2:** Run — fail

- [ ] **Step 13.3:** Implement

```swift
// SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift
import Foundation

/// 首次启动时注入的默认配置，包含 1 个 Provider 和 4 个内置工具
public enum DefaultConfiguration {

    public static func initial() -> Configuration {
        Configuration(
            schemaVersion: Configuration.currentSchemaVersion,
            providers: [openAIDefault],
            tools: [translate, polish, summarize, explain],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
            triggers: TriggerSettings(
                floatingToolbarEnabled: true,
                commandPaletteEnabled: true,
                minimumSelectionLength: 1,
                triggerDelayMs: 150
            ),
            telemetry: TelemetrySettings(enabled: false),
            appBlocklist: [
                "com.apple.keychainaccess",
                "com.1password.1password",
                "com.1password.1password7",
                "com.bitwarden.desktop"
            ]
        )
    }

    // MARK: - Provider

    public static let openAIDefault = Provider(
        id: "openai-official",
        name: "OpenAI",
        baseURL: URL(string: "https://api.openai.com/v1")!,  // swiftlint:disable:this force_unwrapping
        apiKeyRef: "keychain:openai-official",
        defaultModel: "gpt-5"
    )

    // MARK: - Tools

    public static let translate = Tool(
        id: "translate", name: "Translate", icon: "🌐",
        description: "将选中文字翻译为指定语言",
        systemPrompt: "You are a professional translator. Translate faithfully and naturally. Output only the translation without explanations.",
        userPrompt: "Translate the following to {{language}}:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.3,
        displayMode: .window,
        variables: ["language": "Simplified Chinese"]
    )

    public static let polish = Tool(
        id: "polish", name: "Polish", icon: "📝",
        description: "在保持原意的前提下润色文字",
        systemPrompt: "You are an expert editor. Polish the text while preserving the author's voice and meaning. Output only the polished version.",
        userPrompt: "Polish the following text:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.4,
        displayMode: .window,
        variables: [:]
    )

    public static let summarize = Tool(
        id: "summarize", name: "Summarize", icon: "✨",
        description: "总结关键要点",
        systemPrompt: "You are an expert summarizer. Produce concise, structured summaries.",
        userPrompt: "Summarize the key points of the following text. Use Markdown bullet points:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.3,
        displayMode: .window,
        variables: [:]
    )

    public static let explain = Tool(
        id: "explain", name: "Explain", icon: "💡",
        description: "解释专业术语或生词",
        systemPrompt: "You are a patient teacher. Explain concepts clearly, assuming an educated but non-expert audience.",
        userPrompt: "Explain the following in simple terms. If it's a technical term or acronym, expand and contextualize:\n\n{{selection}}",
        providerId: openAIDefault.id, modelId: nil, temperature: 0.4,
        displayMode: .window,
        variables: [:]
    )
}
```

- [ ] **Step 13.4:** Run — pass

- [ ] **Step 13.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift SliceAIKit/Tests/SliceCoreTests/DefaultConfigurationTests.swift
git commit -m "feat(core): add DefaultConfiguration with 4 built-in tools"
```

### Task 14: ToolExecutor actor

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ToolExecutor.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift`

- [ ] **Step 14.1:** Failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift
import XCTest
@testable import SliceCore

// MARK: - Fakes

private actor FakeConfig: ConfigurationProviding {
    var cfg: Configuration
    init(_ cfg: Configuration) { self.cfg = cfg }
    func current() async -> Configuration { cfg }
    func update(_ configuration: Configuration) async throws { self.cfg = configuration }
}

private actor FakeKeychain: KeychainAccessing {
    var store: [String: String]
    init(_ store: [String: String] = [:]) { self.store = store }
    func readAPIKey(providerId: String) async throws -> String? { store[providerId] }
    func writeAPIKey(_ value: String, providerId: String) async throws { store[providerId] = value }
    func deleteAPIKey(providerId: String) async throws { store.removeValue(forKey: providerId) }
}

private struct FakeProvider: LLMProvider {
    let chunks: [String]
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { cont in
            Task {
                for c in chunks { cont.yield(ChatChunk(delta: c)) }
                cont.finish()
            }
        }
    }
}

private struct FakeFactory: LLMProviderFactory {
    let chunks: [String]
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        FakeProvider(chunks: chunks)
    }
}

private struct CapturingFactory: LLMProviderFactory {
    final class Box: @unchecked Sendable { var capturedKey: String? }
    let box = Box()
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        box.capturedKey = apiKey
        return FakeProvider(chunks: ["ok"])
    }
}

final class ToolExecutorTests: XCTestCase {
    func test_execute_renderPromptAndStream() async throws {
        let cfg = DefaultConfiguration.initial()
        let keychain = FakeKeychain(["openai-official": "sk-test"])
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: FakeFactory(chunks: ["Hello ", "World"]),
            keychain: keychain
        )
        let payload = SelectionPayload(
            text: "hola", appBundleID: "x", appName: "X", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        let stream = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
        var collected = ""
        for try await chunk in stream { collected += chunk.delta }
        XCTAssertEqual(collected, "Hello World")
    }

    func test_execute_missingAPIKey_throwsUnauthorized() async {
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: FakeFactory(chunks: []),
            keychain: FakeKeychain()   // 空
        )
        let payload = SelectionPayload(
            text: "x", appBundleID: "", appName: "", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        do {
            _ = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
            XCTFail("should have thrown")
        } catch SliceError.provider(.unauthorized) {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_execute_passesAPIKeyToFactory() async throws {
        let factory = CapturingFactory()
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: factory,
            keychain: FakeKeychain(["openai-official": "sk-captured"])
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        let stream = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
        for try await _ in stream {}
        XCTAssertEqual(factory.box.capturedKey, "sk-captured")
    }

    func test_execute_unknownProvider_throws() async {
        var cfg = DefaultConfiguration.initial()
        cfg.tools[0].providerId = "ghost"     // 引用不存在的 provider
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: FakeFactory(chunks: []),
            keychain: FakeKeychain()
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        do {
            _ = try await exec.execute(tool: cfg.tools[0], payload: payload)
            XCTFail("should have thrown")
        } catch SliceError.configuration(.referencedProviderMissing(let id)) {
            XCTAssertEqual(id, "ghost")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
```

- [ ] **Step 14.2:** Run — fail

- [ ] **Step 14.3:** Implement

```swift
// SliceAIKit/Sources/SliceCore/ToolExecutor.swift
import Foundation

/// 工具执行的中枢：渲染 prompt → 取 Provider + API Key → 转发到 LLMProvider 流
public actor ToolExecutor {

    private let configurationProvider: any ConfigurationProviding
    private let providerFactory: any LLMProviderFactory
    private let keychain: any KeychainAccessing

    public init(
        configurationProvider: any ConfigurationProviding,
        providerFactory: any LLMProviderFactory,
        keychain: any KeychainAccessing
    ) {
        self.configurationProvider = configurationProvider
        self.providerFactory = providerFactory
        self.keychain = keychain
    }

    /// 执行一次工具调用
    /// - Returns: 流式 chunk，UI 层消费并渲染
    public func execute(
        tool: Tool,
        payload: SelectionPayload
    ) async throws -> AsyncThrowingStream<ChatChunk, Error> {

        let cfg = await configurationProvider.current()
        guard let provider = cfg.providers.first(where: { $0.id == tool.providerId }) else {
            throw SliceError.configuration(.referencedProviderMissing(tool.providerId))
        }

        guard let apiKey = try await keychain.readAPIKey(providerId: provider.id),
              !apiKey.isEmpty else {
            throw SliceError.provider(.unauthorized)
        }

        // 渲染变量：内置变量 + 工具预设变量，后者优先被系统变量覆盖
        var variables: [String: String] = tool.variables
        variables["selection"] = payload.text
        variables["app"] = payload.appName
        variables["url"] = payload.url?.absoluteString ?? ""
        if variables["language"] == nil { variables["language"] = "" }

        let userText = PromptTemplate.render(tool.userPrompt, variables: variables)
        var messages: [ChatMessage] = []
        if let sys = tool.systemPrompt, !sys.isEmpty {
            let systemText = PromptTemplate.render(sys, variables: variables)
            messages.append(ChatMessage(role: .system, content: systemText))
        }
        messages.append(ChatMessage(role: .user, content: userText))

        let request = ChatRequest(
            model: tool.modelId ?? provider.defaultModel,
            messages: messages,
            temperature: tool.temperature,
            maxTokens: nil
        )

        let llm = try providerFactory.make(for: provider, apiKey: apiKey)
        return try await llm.stream(request: request)
    }
}
```

- [ ] **Step 14.4:** Run all SliceCore tests

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter SliceCoreTests
```

Expected: all pass

- [ ] **Step 14.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/ToolExecutor.swift SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift
git commit -m "feat(core): add ToolExecutor actor with prompt rendering and error paths"
```

### Task 15: SliceCore coverage review

- [ ] **Step 15.1:** Generate coverage report

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/debug/SliceAIKitPackageTests.xctest/Contents/MacOS/SliceAIKitPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  -ignore-filename-regex='.build|Tests' 2>&1 | tail -20
```

Expected: SliceCore files > 90% coverage. If any file < 90%, write additional tests and re-run.

- [ ] **Step 15.2:** Delete test marker

```bash
rm /Users/majiajun/workspace/SliceAI/SliceAIKit/Tests/SliceCoreTests/_TestMarker.swift 2>/dev/null || true
git add -A && git commit -m "chore: remove SliceCoreTests marker" || true
```

**M2 partial:** SliceCore types complete, coverage ≥ 90%.

---

## Phase 2 — LLMProviders

### Task 16: SSE Decoder

**Files:**
- Create: `SliceAIKit/Sources/LLMProviders/SSEDecoder.swift`
- Create: `SliceAIKit/Tests/LLMProvidersTests/SSEDecoderTests.swift`
- Create: `SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_happy.sse`
- Create: `SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_done.sse`

- [ ] **Step 16.1:** Drop fixtures

```
# SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_happy.sse
data: {"id":"c","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hello"}}]}

data: {"id":"c","object":"chat.completion.chunk","choices":[{"delta":{"content":" World"}}]}

data: {"id":"c","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop"}]}

data: [DONE]

```

```
# SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_done.sse
data: [DONE]

```

Notes: each "event" ends with a blank line. Trailing newline is important.

- [ ] **Step 16.2:** Failing tests

```swift
// SliceAIKit/Tests/LLMProvidersTests/SSEDecoderTests.swift
import XCTest
@testable import LLMProviders

final class SSEDecoderTests: XCTestCase {
    func test_decodesSingleDataEvent() {
        var decoder = SSEDecoder()
        let events = decoder.feed("data: hello\n\n")
        XCTAssertEqual(events, [.data("hello")])
    }

    func test_decodesMultipleEventsAcrossChunks() {
        var decoder = SSEDecoder()
        var events = decoder.feed("data: a\n\n")
        events += decoder.feed("data: b\n\ndata: c")   // c incomplete
        events += decoder.feed("\n\n")
        XCTAssertEqual(events, [.data("a"), .data("b"), .data("c")])
    }

    func test_doneMarker() {
        var decoder = SSEDecoder()
        let events = decoder.feed("data: [DONE]\n\n")
        XCTAssertEqual(events, [.done])
    }

    func test_ignoresCommentsAndUnknownFields() {
        var decoder = SSEDecoder()
        let events = decoder.feed(": heartbeat\n\nevent: update\ndata: x\n\n")
        XCTAssertEqual(events, [.data("x")])
    }

    func test_handlesHappyFixture() throws {
        let url = Bundle.module.url(forResource: "openai_chat_happy", withExtension: "sse",
                                    subdirectory: "Fixtures")
        let data = try Data(contentsOf: XCTUnwrap(url))
        let text = String(data: data, encoding: .utf8)!
        var decoder = SSEDecoder()
        let events = decoder.feed(text)
        let count = events.filter { if case .data = $0 { return true }; return false }.count
        XCTAssertEqual(count, 3)
        XCTAssertEqual(events.last, .done)
    }
}
```

- [ ] **Step 16.3:** Run — fail

- [ ] **Step 16.4:** Implement

```swift
// SliceAIKit/Sources/LLMProviders/SSEDecoder.swift
import Foundation

/// 一个增量的 Server-Sent Events 解码器
/// 输入可来自 URLSession.AsyncBytes.lines（已按行拆分）或字节流（内部自行拆行）
public struct SSEDecoder {
    public enum Event: Equatable, Sendable {
        case data(String)
        case done
    }

    private var buffer = ""
    private var eventDataLines: [String] = []

    public init() {}

    /// 追加输入数据并返回本次产生的完整事件列表
    public mutating func feed(_ chunk: String) -> [Event] {
        buffer += chunk
        var events: [Event] = []

        // 找到所有完整行（以 \n 结尾）
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(..<newlineRange.upperBound)

            if line.isEmpty {
                // 空行 = 事件分隔符
                if !eventDataLines.isEmpty {
                    let joined = eventDataLines.joined(separator: "\n")
                    eventDataLines.removeAll(keepingCapacity: true)
                    if joined == "[DONE]" {
                        events.append(.done)
                    } else {
                        events.append(.data(joined))
                    }
                }
                continue
            }

            if line.hasPrefix(":") { continue }  // 注释/心跳
            if let colonIdx = line.firstIndex(of: ":") {
                let field = String(line[..<colonIdx])
                var value = String(line[line.index(after: colonIdx)...])
                if value.hasPrefix(" ") { value.removeFirst() }
                if field == "data" {
                    eventDataLines.append(value)
                }
                // 其它字段（event/id/retry）在 MVP 中忽略
            }
            // 没有冒号的行按 SSE 规范也可以当作字段名，但对接 OpenAI 兼容协议用不到
        }
        return events
    }
}
```

- [ ] **Step 16.5:** Run — pass

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter SSEDecoderTests
```

- [ ] **Step 16.6:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/LLMProviders/SSEDecoder.swift SliceAIKit/Tests/LLMProvidersTests/
git rm SliceAIKit/Sources/LLMProviders/_ModuleMarker.swift 2>/dev/null || true
git rm SliceAIKit/Tests/LLMProvidersTests/_TestMarker.swift 2>/dev/null || true
git commit -m "feat(providers): add incremental SSE decoder with fixtures"
```

### Task 17: OpenAI DTOs

**Files:**
- Create: `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift`
- Create: `SliceAIKit/Tests/LLMProvidersTests/OpenAIDTOsTests.swift`

- [ ] **Step 17.1:** Failing tests

```swift
// SliceAIKit/Tests/LLMProvidersTests/OpenAIDTOsTests.swift
import XCTest
@testable import LLMProviders

final class OpenAIDTOsTests: XCTestCase {
    func test_decodesDeltaChunk() throws {
        let json = """
        {"id":"c","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.delta.content, "Hi")
        XCTAssertNil(chunk.choices.first?.finishReason)
    }

    func test_decodesFinishChunk() throws {
        let json = """
        {"id":"c","choices":[{"delta":{},"finish_reason":"stop"}]}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.finishReason, "stop")
        XCTAssertNil(chunk.choices.first?.delta.content)
    }
}
```

- [ ] **Step 17.2:** Run — fail

- [ ] **Step 17.3:** Implement

```swift
// SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift
import Foundation

/// OpenAI chat completion stream chunk 的解码结构
struct OpenAIStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
    }
}
```

- [ ] **Step 17.4:** Run — pass

- [ ] **Step 17.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift SliceAIKit/Tests/LLMProvidersTests/OpenAIDTOsTests.swift
git commit -m "feat(providers): add OpenAI stream chunk decoder"
```

### Task 18: OpenAICompatibleProvider + Mock URLProtocol

**Files:**
- Create: `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift`
- Create: `SliceAIKit/Tests/LLMProvidersTests/MockURLProtocol.swift`
- Create: `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift`

- [ ] **Step 18.1:** MockURLProtocol

```swift
// SliceAIKit/Tests/LLMProvidersTests/MockURLProtocol.swift
import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// 用类级字典存 request handler，测试设置后复位
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    static func mocked() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 18.2:** Failing tests

```swift
// SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift
import XCTest
@testable import LLMProviders
@testable import SliceCore

final class OpenAICompatibleProviderTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_stream_happyPath_returnsConcatenatedChunks() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" World"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
            return (resp, sse)
        }

        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-test",
            session: URLSession.mocked()
        )

        let req = ChatRequest(
            model: "gpt-5",
            messages: [ChatMessage(role: .user, content: "hi")]
        )
        var collected = ""
        for try await chunk in try await provider.stream(request: req) {
            collected += chunk.delta
        }
        XCTAssertEqual(collected, "Hello World")
    }

    func test_stream_unauthorized401_throws() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("unauthorized".utf8))
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "bad", session: URLSession.mocked()
        )
        let req = ChatRequest(model: "x", messages: [])

        do {
            let s = try await provider.stream(request: req)
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.unauthorized) {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_stream_serverError500_throws() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.serverError(let code)) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_stream_rateLimited429_includesRetryAfter() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil,
                                       headerFields: ["Retry-After": "12"])!
            return (resp, Data())
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.rateLimited(let after)) {
            XCTAssertEqual(after, 12)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_stream_sendsAuthorizationHeader() async throws {
        final class Capture: @unchecked Sendable { var auth: String? }
        let cap = Capture()
        MockURLProtocol.requestHandler = { req in
            cap.auth = req.value(forHTTPHeaderField: "Authorization")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
            return (resp, Data("data: [DONE]\n\n".utf8))
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-123", session: URLSession.mocked()
        )
        for try await _ in try await provider.stream(request: ChatRequest(model: "x", messages: [])) {}
        XCTAssertEqual(cap.auth, "Bearer sk-123")
    }
}
```

- [ ] **Step 18.3:** Run — fail

- [ ] **Step 18.4:** Implement

```swift
// SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift
import Foundation
import SliceCore

/// OpenAI 兼容协议的 Provider 实现
/// 使用 URLSession.bytes(for:) 流式读取 SSE
public struct OpenAICompatibleProvider: LLMProvider {

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        // 组装 URL：baseURL 通常形如 https://api.openai.com/v1
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var httpReq = URLRequest(url: endpoint)
        httpReq.httpMethod = "POST"
        httpReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        httpReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpReq.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        httpReq.timeoutInterval = 30

        // 追加 stream: true
        var body = try JSONEncoder().encode(request)
        if var dict = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            dict["stream"] = true
            body = try JSONSerialization.data(withJSONObject: dict)
        }
        httpReq.httpBody = body

        let (bytes, response) = try await session.bytes(for: httpReq)
        guard let http = response as? HTTPURLResponse else {
            throw SliceError.provider(.invalidResponse("non-http response"))
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw SliceError.provider(.unauthorized)
        case 429:
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw SliceError.provider(.rateLimited(retryAfter: retry))
        case 500..<600:
            throw SliceError.provider(.serverError(http.statusCode))
        default:
            throw SliceError.provider(.invalidResponse("HTTP \(http.statusCode)"))
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = SSEDecoder()
                do {
                    for try await line in bytes.lines {
                        let events = decoder.feed(line + "\n")
                        for event in events {
                            switch event {
                            case .data(let json):
                                if let chunk = decodeChunk(json: json) {
                                    continuation.yield(chunk)
                                }
                            case .done:
                                continuation.finish()
                                return
                            }
                        }
                    }
                    // stream 正常结束但未收到 [DONE] 也视作完成
                    // 冲洗剩余
                    let rest = decoder.feed("\n\n")
                    for event in rest {
                        if case .data(let json) = event,
                           let chunk = decodeChunk(json: json) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    if (error as? URLError)?.code == .timedOut {
                        continuation.finish(throwing: SliceError.provider(.networkTimeout))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 将一行 SSE data JSON 解码成 ChatChunk；无法识别返回 nil
    private func decodeChunk(json: String) -> ChatChunk? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let parsed = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) else {
            return nil
        }
        let delta = parsed.choices.first?.delta.content ?? ""
        let reason = parsed.choices.first?.finishReason.flatMap(FinishReason.init(rawValue:))
        if delta.isEmpty && reason == nil { return nil }
        return ChatChunk(delta: delta, finishReason: reason)
    }
}
```

- [ ] **Step 18.5:** Run — pass

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter OpenAICompatibleProvider
```

- [ ] **Step 18.6:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift SliceAIKit/Tests/LLMProvidersTests/
git commit -m "feat(providers): add OpenAICompatibleProvider with SSE streaming"
```

### Task 19: LLMProviderFactory concrete

**Files:**
- Create: `SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift`

- [ ] **Step 19.1:** Implement

```swift
// SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift
import Foundation
import SliceCore

/// 生产环境使用的 LLMProviderFactory 实现
public struct OpenAIProviderFactory: LLMProviderFactory {
    public init() {}

    public func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        // MVP v0.1 只有 OpenAI 兼容一种类型；未来可按 provider.id 前缀或新字段分发
        OpenAICompatibleProvider(baseURL: provider.baseURL, apiKey: apiKey)
    }
}
```

- [ ] **Step 19.2:** Build

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
```

- [ ] **Step 19.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift
git commit -m "feat(providers): add OpenAIProviderFactory"
```

**M2 reached:** `SliceCore` + `LLMProviders` feature-complete, tested, coverage ≥ 80%.

---

## Phase 3 — SelectionCapture

### Task 20: SelectionSource protocol + PasteboardProtocol

**Files:**
- Create: `SliceAIKit/Sources/SelectionCapture/SelectionSource.swift`
- Create: `SliceAIKit/Sources/SelectionCapture/PasteboardProtocol.swift`

- [ ] **Step 20.1:** Implement SelectionSource

```swift
// SliceAIKit/Sources/SelectionCapture/SelectionSource.swift
import Foundation
import SliceCore

/// 读取一次选中文字的抽象来源
public protocol SelectionSource: Sendable {
    /// 读取当前选中文字；拿不到返回 nil
    func readSelection() async throws -> SelectionReadResult?
}

/// 读取结果，包含 text 与来源的应用信息
public struct SelectionReadResult: Sendable, Equatable {
    public let text: String
    public let appBundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint
    public let source: SelectionPayload.Source

    public init(text: String, appBundleID: String, appName: String,
                url: URL?, screenPoint: CGPoint, source: SelectionPayload.Source) {
        self.text = text; self.appBundleID = appBundleID; self.appName = appName
        self.url = url; self.screenPoint = screenPoint; self.source = source
    }
}
```

- [ ] **Step 20.2:** Implement PasteboardProtocol

```swift
// SliceAIKit/Sources/SelectionCapture/PasteboardProtocol.swift
import AppKit

/// NSPasteboard 的抽象接口，便于测试注入假实现
public protocol PasteboardProtocol: Sendable {
    var changeCount: Int { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    @discardableResult
    func clearContents() -> Int
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    func pasteboardItems() -> [NSPasteboardItem]?
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

/// 系统 NSPasteboard 的默认适配
public struct SystemPasteboard: PasteboardProtocol {
    private let pb: NSPasteboard
    public init(_ pb: NSPasteboard = .general) { self.pb = pb }

    public var changeCount: Int { pb.changeCount }
    public func string(forType type: NSPasteboard.PasteboardType) -> String? { pb.string(forType: type) }
    @discardableResult public func clearContents() -> Int { pb.clearContents() }
    @discardableResult
    public func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        pb.setString(string, forType: type)
    }
    public func pasteboardItems() -> [NSPasteboardItem]? { pb.pasteboardItems }
    public func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool { pb.writeObjects(objects) }
}
```

- [ ] **Step 20.3:** Build & commit

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SelectionCapture/
git rm SliceAIKit/Sources/SelectionCapture/_ModuleMarker.swift 2>/dev/null || true
git commit -m "feat(selection): add SelectionSource protocol and Pasteboard abstraction"
```

### Task 21: ClipboardSelectionSource

**Files:**
- Create: `SliceAIKit/Sources/SelectionCapture/ClipboardSelectionSource.swift`
- Create: `SliceAIKit/Tests/SelectionCaptureTests/ClipboardSelectionSourceTests.swift`

- [ ] **Step 21.1:** Failing tests with a fake pasteboard

```swift
// SliceAIKit/Tests/SelectionCaptureTests/ClipboardSelectionSourceTests.swift
import XCTest
import AppKit
@testable import SelectionCapture

final class FakePasteboard: PasteboardProtocol, @unchecked Sendable {
    var changeCountValue = 0
    var storedString: String?
    var clearCalls = 0
    var setStringCalls: [(String, NSPasteboard.PasteboardType)] = []
    /// 模拟 "系统发 ⌘C" 回调：设置这个闭包被调用时修改内部状态
    var onExpectingCopy: (() -> Void)?

    var changeCount: Int { changeCountValue }
    func string(forType type: NSPasteboard.PasteboardType) -> String? { storedString }
    func clearContents() -> Int {
        clearCalls += 1
        storedString = nil
        changeCountValue += 1
        return changeCountValue
    }
    func setString(_ s: String, forType t: NSPasteboard.PasteboardType) -> Bool {
        setStringCalls.append((s, t))
        storedString = s
        changeCountValue += 1
        return true
    }
    func pasteboardItems() -> [NSPasteboardItem]? { nil }
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool { true }
}

/// 测试替身：直接给 source 注入"⌘C 后剪贴板里是什么"
final class FakeCopyInvoker: CopyKeystrokeInvoking, @unchecked Sendable {
    let pasteboard: FakePasteboard
    let simulatedText: String?
    init(_ pb: FakePasteboard, simulate: String?) { self.pasteboard = pb; self.simulatedText = simulate }
    func sendCopy() async throws {
        // 模拟系统把选中文字写到剪贴板：如 simulatedText 为 nil，不变
        if let t = simulatedText {
            pasteboard.storedString = t
            pasteboard.changeCountValue += 1
        }
    }
}

final class ClipboardSelectionSourceTests: XCTestCase {

    func test_readSelection_returnsText_andRestoresOriginal() async throws {
        let pb = FakePasteboard()
        pb.storedString = "original"
        pb.changeCountValue = 5

        let source = ClipboardSelectionSource(
            pasteboard: pb,
            copyInvoker: FakeCopyInvoker(pb, simulate: "selected text"),
            focusProvider: { FocusInfo(bundleID: "com.apple.Safari", appName: "Safari",
                                       url: URL(string: "https://example.com"),
                                       screenPoint: CGPoint(x: 10, y: 20)) },
            pollInterval: 0.001,
            timeout: 0.2
        )
        let result = try await source.readSelection()
        XCTAssertEqual(result?.text, "selected text")
        XCTAssertEqual(result?.source, .clipboardFallback)
        XCTAssertEqual(result?.appName, "Safari")
        // 原剪贴板应被恢复
        XCTAssertEqual(pb.storedString, "original")
    }

    func test_readSelection_timeout_returnsNil() async throws {
        let pb = FakePasteboard()
        pb.storedString = "orig"
        pb.changeCountValue = 1

        let source = ClipboardSelectionSource(
            pasteboard: pb,
            copyInvoker: FakeCopyInvoker(pb, simulate: nil),    // 剪贴板不变
            focusProvider: { FocusInfo(bundleID: "x", appName: "x", url: nil, screenPoint: .zero) },
            pollInterval: 0.001,
            timeout: 0.05
        )
        let result = try await source.readSelection()
        XCTAssertNil(result)
        XCTAssertEqual(pb.storedString, "orig")
    }
}
```

- [ ] **Step 21.2:** Run — fail

- [ ] **Step 21.3:** Implement

```swift
// SliceAIKit/Sources/SelectionCapture/ClipboardSelectionSource.swift
import Foundation
import AppKit
import SliceCore

/// 抽象"按下 ⌘C"的能力，便于测试
public protocol CopyKeystrokeInvoking: Sendable {
    func sendCopy() async throws
}

/// 提供前台窗口信息，便于测试
public struct FocusInfo: Sendable {
    public let bundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint

    public init(bundleID: String, appName: String, url: URL?, screenPoint: CGPoint) {
        self.bundleID = bundleID; self.appName = appName; self.url = url
        self.screenPoint = screenPoint
    }
}

/// 基于 "备份剪贴板 + 模拟 ⌘C + 读 + 恢复" 路径的选中文字读取
public final class ClipboardSelectionSource: SelectionSource, @unchecked Sendable {

    private let pasteboard: any PasteboardProtocol
    private let copyInvoker: any CopyKeystrokeInvoking
    private let focusProvider: @Sendable () -> FocusInfo?
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval

    public init(pasteboard: any PasteboardProtocol,
                copyInvoker: any CopyKeystrokeInvoking,
                focusProvider: @escaping @Sendable () -> FocusInfo?,
                pollInterval: TimeInterval = 0.01,
                timeout: TimeInterval = 0.15) {
        self.pasteboard = pasteboard
        self.copyInvoker = copyInvoker
        self.focusProvider = focusProvider
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    public func readSelection() async throws -> SelectionReadResult? {
        // 1. 备份现有剪贴板内容
        let originalChange = pasteboard.changeCount
        let originalString = pasteboard.string(forType: .string)

        // 2. 发 ⌘C
        try await copyInvoker.sendCopy()

        // 3. 轮询等待 changeCount 变化
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != originalChange { break }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        let changed = pasteboard.changeCount != originalChange
        let text = changed ? pasteboard.string(forType: .string) : nil

        // 4. 恢复原剪贴板（只有在真的改变时才恢复）
        if changed {
            pasteboard.clearContents()
            if let originalString {
                _ = pasteboard.setString(originalString, forType: .string)
            }
        }

        guard let text, !text.isEmpty else { return nil }
        guard let focus = focusProvider() else { return nil }
        return SelectionReadResult(
            text: text, appBundleID: focus.bundleID, appName: focus.appName,
            url: focus.url, screenPoint: focus.screenPoint,
            source: .clipboardFallback
        )
    }
}
```

- [ ] **Step 21.4:** Run — pass

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test --filter ClipboardSelectionSourceTests
```

- [ ] **Step 21.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SelectionCapture/ClipboardSelectionSource.swift SliceAIKit/Tests/SelectionCaptureTests/
git rm SliceAIKit/Tests/SelectionCaptureTests/_TestMarker.swift 2>/dev/null || true
git commit -m "feat(selection): add ClipboardSelectionSource with fake pasteboard tests"
```

### Task 22: SystemCopyKeystrokeInvoker (real Cmd+C)

**Files:**
- Create: `SliceAIKit/Sources/SelectionCapture/SystemCopyKeystrokeInvoker.swift`

- [ ] **Step 22.1:** Implement

```swift
// SliceAIKit/Sources/SelectionCapture/SystemCopyKeystrokeInvoker.swift
import AppKit
import CoreGraphics

/// 通过 CGEvent 模拟按下 ⌘C
/// 需要 Accessibility 权限才能正常 post 到前台 app
public struct SystemCopyKeystrokeInvoker: CopyKeystrokeInvoking {

    public init() {}

    public func sendCopy() async throws {
        let src = CGEventSource(stateID: .hidSystemState)
        // C 键的 virtual keycode = 8
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 22.2:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SelectionCapture/SystemCopyKeystrokeInvoker.swift
git commit -m "feat(selection): add SystemCopyKeystrokeInvoker (CGEvent based)"
```

### Task 23: AXSelectionSource

**Files:**
- Create: `SliceAIKit/Sources/SelectionCapture/AXSelectionSource.swift`

No unit tests here — AX requires real accessibility API. Covered by manual smoke tests in Phase 8.

- [ ] **Step 23.1:** Implement

```swift
// SliceAIKit/Sources/SelectionCapture/AXSelectionSource.swift
import AppKit
import ApplicationServices
import SliceCore

/// 基于 Accessibility API 读取当前 focused element 的选中文字
public struct AXSelectionSource: SelectionSource {

    public init() {}

    public func readSelection() async throws -> SelectionReadResult? {
        // 系统级 AX 调用必须在主线程
        await MainActor.run { self.readOnMain() }
    }

    @MainActor
    private func readOnMain() -> SelectionReadResult? {
        let systemWide = AXUIElementCreateSystemWide()

        // 拿到 focused UI element
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        )
        guard err == .success, let focused = focused else { return nil }
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement

        var selected: CFTypeRef?
        let selErr = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected
        )
        guard selErr == .success, let text = selected as? String, !text.isEmpty else {
            return nil
        }

        // 当前前台 app
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return SelectionReadResult(text: text, appBundleID: "", appName: "",
                                       url: nil, screenPoint: NSEvent.mouseLocation,
                                       source: .accessibility)
        }
        // 尝试读取浏览器 URL（用 AX 只对部分浏览器有效；Safari / Chromium 家族支持）
        let url = readURLIfBrowser(appBundleID: frontApp.bundleIdentifier ?? "")

        return SelectionReadResult(
            text: text,
            appBundleID: frontApp.bundleIdentifier ?? "",
            appName: frontApp.localizedName ?? "",
            url: url,
            screenPoint: NSEvent.mouseLocation,     // 屏幕坐标（左下原点）
            source: .accessibility
        )
    }

    /// 对浏览器尝试读取当前 tab URL。失败返回 nil
    @MainActor
    private func readURLIfBrowser(appBundleID: String) -> URL? {
        // 最简版本：只支持 Safari & Chromium 家族。MVP 阶段不激进
        guard appBundleID == "com.apple.Safari"
           || appBundleID.hasPrefix("com.google.Chrome")
           || appBundleID.hasPrefix("com.microsoft.Edge")
           || appBundleID.hasPrefix("com.brave.Browser")
           || appBundleID.hasPrefix("company.thebrowser.Browser") else { return nil }

        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let focusedWindow else { return nil }
        // swiftlint:disable:next force_cast
        let window = focusedWindow as! AXUIElement
        var urlValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXDocument" as CFString, &urlValue) == .success,
           let s = urlValue as? String {
            return URL(string: s)
        }
        return nil
    }
}
```

- [ ] **Step 23.2:** Build

- [ ] **Step 23.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SelectionCapture/AXSelectionSource.swift
git commit -m "feat(selection): add AXSelectionSource reading kAXSelectedTextAttribute"
```

### Task 24: SelectionService (orchestrator)

**Files:**
- Create: `SliceAIKit/Sources/SelectionCapture/SelectionService.swift`
- Create: `SliceAIKit/Tests/SelectionCaptureTests/SelectionServiceTests.swift`

- [ ] **Step 24.1:** Failing tests

```swift
// SliceAIKit/Tests/SelectionCaptureTests/SelectionServiceTests.swift
import XCTest
@testable import SelectionCapture
@testable import SliceCore

private struct YieldingSource: SelectionSource {
    let result: SelectionReadResult?
    let throwsError: Error?
    init(result: SelectionReadResult? = nil, throwsError: Error? = nil) {
        self.result = result; self.throwsError = throwsError
    }
    func readSelection() async throws -> SelectionReadResult? {
        if let e = throwsError { throw e }
        return result
    }
}

final class SelectionServiceTests: XCTestCase {

    private let sample = SelectionReadResult(
        text: "hello", appBundleID: "x", appName: "X",
        url: nil, screenPoint: .zero, source: .accessibility
    )

    func test_prefersPrimarySourceWhenSuccess() async throws {
        let service = SelectionService(
            primary: YieldingSource(result: sample),
            fallback: YieldingSource(result: nil)
        )
        let payload = try await service.capture()
        XCTAssertEqual(payload?.text, "hello")
        XCTAssertEqual(payload?.source, .accessibility)
    }

    func test_fallsBackWhenPrimaryReturnsNil() async throws {
        let fallbackResult = SelectionReadResult(
            text: "fb", appBundleID: "x", appName: "X",
            url: nil, screenPoint: .zero, source: .clipboardFallback
        )
        let service = SelectionService(
            primary: YieldingSource(result: nil),
            fallback: YieldingSource(result: fallbackResult)
        )
        let payload = try await service.capture()
        XCTAssertEqual(payload?.text, "fb")
        XCTAssertEqual(payload?.source, .clipboardFallback)
    }

    func test_returnsNilWhenBothFail() async throws {
        let service = SelectionService(
            primary: YieldingSource(result: nil),
            fallback: YieldingSource(result: nil)
        )
        let payload = try await service.capture()
        XCTAssertNil(payload)
    }

    func test_fallsBackWhenPrimaryThrows() async throws {
        struct X: Error {}
        let service = SelectionService(
            primary: YieldingSource(throwsError: X()),
            fallback: YieldingSource(result: sample)
        )
        let payload = try await service.capture()
        XCTAssertEqual(payload?.text, "hello")
    }
}
```

- [ ] **Step 24.2:** Run — fail

- [ ] **Step 24.3:** Implement

```swift
// SliceAIKit/Sources/SelectionCapture/SelectionService.swift
import Foundation
import SliceCore

/// 组合 primary (AX) 与 fallback (Clipboard)，产出 SelectionPayload
public struct SelectionService: Sendable {

    private let primary: any SelectionSource
    private let fallback: any SelectionSource

    public init(primary: any SelectionSource, fallback: any SelectionSource) {
        self.primary = primary; self.fallback = fallback
    }

    /// 读取当前选区；双路均失败返回 nil
    public func capture() async throws -> SelectionPayload? {
        if let result = try? await primary.readSelection() {
            return result.map { SelectionPayload(from: $0) }
        }
        if let result = try? await fallback.readSelection() {
            return result.map { SelectionPayload(from: $0) }
        }
        return nil
    }
}

private extension SelectionPayload {
    init(from r: SelectionReadResult) {
        self.init(text: r.text, appBundleID: r.appBundleID, appName: r.appName,
                  url: r.url, screenPoint: r.screenPoint, source: r.source,
                  timestamp: Date())
    }
}

private extension Optional {
    func map<T>(_ transform: (Wrapped) -> T) -> T? {
        switch self {
        case .some(let v): return transform(v)
        case .none: return nil
        }
    }
}
```

- [ ] **Step 24.4:** Run — pass

- [ ] **Step 24.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SelectionCapture/SelectionService.swift SliceAIKit/Tests/SelectionCaptureTests/
git commit -m "feat(selection): add SelectionService orchestrating AX + Clipboard"
```

**M3 partial:** SelectionCapture complete, unit-tested where possible.

---

## Phase 4 — HotkeyManager

### Task 25: Hotkey struct + parser

**Files:**
- Create: `SliceAIKit/Sources/HotkeyManager/Hotkey.swift`
- Create: `SliceAIKit/Tests/HotkeyManagerTests/HotkeyTests.swift`

- [ ] **Step 25.1:** Failing tests

```swift
// SliceAIKit/Tests/HotkeyManagerTests/HotkeyTests.swift
import XCTest
@testable import HotkeyManager

final class HotkeyTests: XCTestCase {

    func test_parseOptionSpace() throws {
        let hk = try Hotkey.parse("option+space")
        XCTAssertEqual(hk.keyCode, 49)    // space keycode
        XCTAssertEqual(hk.modifiers, .option)
    }

    func test_parseCmdShiftSpace() throws {
        let hk = try Hotkey.parse("cmd+shift+space")
        XCTAssertEqual(hk.keyCode, 49)
        XCTAssertTrue(hk.modifiers.contains(.command))
        XCTAssertTrue(hk.modifiers.contains(.shift))
    }

    func test_parseCaseInsensitive() throws {
        let hk = try Hotkey.parse("CMD+Space")
        XCTAssertTrue(hk.modifiers.contains(.command))
    }

    func test_parseInvalid_throws() {
        XCTAssertThrowsError(try Hotkey.parse("cmd+nothing"))
        XCTAssertThrowsError(try Hotkey.parse(""))
    }

    func test_descriptionRoundTrip() throws {
        let hk = try Hotkey.parse("option+space")
        XCTAssertEqual(hk.description, "option+space")
    }
}
```

- [ ] **Step 25.2:** Run — fail

- [ ] **Step 25.3:** Implement

```swift
// SliceAIKit/Sources/HotkeyManager/Hotkey.swift
import Foundation
import Carbon
import AppKit

/// 一组快捷键定义，可从字符串解析
public struct Hotkey: Sendable, Equatable, CustomStringConvertible {
    public let keyCode: UInt32
    public let modifiers: Modifiers

    public struct Modifiers: OptionSet, Sendable, Equatable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: UInt32(cmdKey))
        public static let option  = Modifiers(rawValue: UInt32(optionKey))
        public static let shift   = Modifiers(rawValue: UInt32(shiftKey))
        public static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    public enum ParseError: Error { case empty, unknownToken(String) }

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }

    /// 从形如 "option+space" / "cmd+shift+k" 的字符串解析
    public static func parse(_ string: String) throws -> Hotkey {
        let tokens = string.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { throw ParseError.empty }

        var mods: Modifiers = []
        var key: UInt32?

        for token in tokens {
            switch token {
            case "cmd", "command": mods.insert(.command)
            case "opt", "option", "alt": mods.insert(.option)
            case "shift": mods.insert(.shift)
            case "ctrl", "control": mods.insert(.control)
            default:
                if let k = Self.keyCodeMap[token] {
                    key = k
                } else {
                    throw ParseError.unknownToken(token)
                }
            }
        }
        guard let key else { throw ParseError.empty }
        return Hotkey(keyCode: key, modifiers: mods)
    }

    /// 标准化回字符串表示
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option)  { parts.append("option") }
        if modifiers.contains(.shift)   { parts.append("shift") }
        parts.append(Self.nameForKeyCode[keyCode] ?? "key\(keyCode)")
        return parts.joined(separator: "+")
    }

    // MARK: - 常用键 映射（MVP 覆盖：space + A-Z + F1-F12 + 方向键）
    private static let keyCodeMap: [String: UInt32] = [
        "space": 49, "return": 36, "tab": 48, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
        "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
        "w": 13, "x": 7, "y": 16, "z": 6,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25, "0": 29,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]
    private static let nameForKeyCode: [UInt32: String] = Dictionary(
        uniqueKeysWithValues: keyCodeMap.map { ($0.value, $0.key) }
    )
}
```

- [ ] **Step 25.4:** Run — pass

- [ ] **Step 25.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/HotkeyManager/Hotkey.swift SliceAIKit/Tests/HotkeyManagerTests/
git rm SliceAIKit/Sources/HotkeyManager/_ModuleMarker.swift 2>/dev/null || true
git rm SliceAIKit/Tests/HotkeyManagerTests/_TestMarker.swift 2>/dev/null || true
git commit -m "feat(hotkey): add Hotkey struct with string parser"
```

### Task 26: HotkeyRegistrar

**Files:**
- Create: `SliceAIKit/Sources/HotkeyManager/HotkeyRegistrar.swift`

Carbon `RegisterEventHotKey` requires a process-global handler; can't unit test cleanly. Smoke test in Phase 8.

- [ ] **Step 26.1:** Implement

```swift
// SliceAIKit/Sources/HotkeyManager/HotkeyRegistrar.swift
import Foundation
import Carbon
import AppKit

/// 全局快捷键注册 / 注销
/// 用 Carbon RegisterEventHotKey（比 NSEvent.addGlobalMonitor 可在无窗口状态也响应）
public final class HotkeyRegistrar: @unchecked Sendable {

    /// callback 会在主线程触发
    public typealias Callback = @Sendable () -> Void

    private var refByID: [UInt32: EventHotKeyRef] = [:]
    private var callbackByID: [UInt32: Callback] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    public init() { installHandler() }

    deinit {
        for (_, ref) in refByID { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// 注册。返回 id，可用于 unregister
    @discardableResult
    public func register(_ hotkey: Hotkey, callback: @escaping Callback) throws -> UInt32 {
        let id = nextID; nextID += 1
        let hotkeyID = EventHotKeyID(signature: fourCharCode("SLIC"), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers.rawValue,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            throw NSError(domain: "HotkeyRegistrar", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "RegisterEventHotKey failed"])
        }
        refByID[id] = ref
        callbackByID[id] = callback
        return id
    }

    public func unregister(_ id: UInt32) {
        if let ref = refByID.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        callbackByID.removeValue(forKey: id)
    }

    public func unregisterAll() {
        refByID.values.forEach { UnregisterEventHotKey($0) }
        refByID.removeAll(); callbackByID.removeAll()
    }

    // MARK: - 内部

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, evt, ctx in
            guard let evt, let ctx else { return noErr }
            let unmanaged = Unmanaged<HotkeyRegistrar>.fromOpaque(ctx)
            let registrar = unmanaged.takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(evt, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size,
                              nil, &hkID)
            if let cb = registrar.callbackByID[hkID.id] {
                DispatchQueue.main.async { cb() }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func fourCharCode(_ s: String) -> OSType {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) + OSType($1) }
    }
}
```

- [ ] **Step 26.2:** Build

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
```

- [ ] **Step 26.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/HotkeyManager/HotkeyRegistrar.swift
git commit -m "feat(hotkey): add HotkeyRegistrar wrapping Carbon API"
```

**M3 reached:** Input stack complete.

---

## Phase 5 — Windowing

### Task 27: ScreenAwarePositioner

**Files:**
- Create: `SliceAIKit/Sources/Windowing/ScreenAwarePositioner.swift`
- Create: `SliceAIKit/Tests/WindowingTests/ScreenAwarePositionerTests.swift`

- [ ] **Step 27.1:** Failing tests

```swift
// SliceAIKit/Tests/WindowingTests/ScreenAwarePositionerTests.swift
import XCTest
@testable import Windowing

final class ScreenAwarePositionerTests: XCTestCase {

    /// 屏幕 1920x1080（左下 0,0），工具栏尺寸 300x40
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let size = CGSize(width: 300, height: 40)

    func test_placesBelowAnchor() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 800, y: 500),
                                  size: size, screen: screen, offset: 8)
        // 期望：居中横对齐、下方 8 px
        XCTAssertEqual(origin.x, 800 - size.width/2, accuracy: 0.01)
        XCTAssertEqual(origin.y, 500 - 8 - size.height, accuracy: 0.01)
    }

    func test_flipsAboveWhenBottomOutOfScreen() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 800, y: 20),    // 离屏幕底部仅 20
                                  size: size, screen: screen, offset: 8)
        // 应翻到 anchor 上方
        XCTAssertEqual(origin.y, 20 + 8, accuracy: 0.01)
    }

    func test_clampsLeftWhenOffScreen() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 10, y: 500),
                                  size: size, screen: screen, offset: 8)
        XCTAssertGreaterThanOrEqual(origin.x, screen.minX)
    }

    func test_clampsRightWhenOffScreen() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 1910, y: 500),
                                  size: size, screen: screen, offset: 8)
        XCTAssertLessThanOrEqual(origin.x + size.width, screen.maxX)
    }
}
```

- [ ] **Step 27.2:** Run — fail

- [ ] **Step 27.3:** Implement

```swift
// SliceAIKit/Sources/Windowing/ScreenAwarePositioner.swift
import CoreGraphics

/// 计算工具栏等浮窗的屏幕坐标原点，考虑屏幕边界避让
public struct ScreenAwarePositioner: Sendable {

    public init() {}

    /// - Parameters:
    ///   - anchor: 锚点（选区中心或鼠标位置），屏幕坐标（左下原点）
    ///   - size: 窗口大小
    ///   - screen: 窗口所在屏幕的 visibleFrame
    ///   - offset: 锚点与窗口之间的纵向距离
    /// - Returns: 窗口 origin，屏幕坐标（左下原点）
    public func position(anchor: CGPoint, size: CGSize, screen: CGRect, offset: CGFloat) -> CGPoint {
        var x = anchor.x - size.width / 2
        var y = anchor.y - offset - size.height     // 默认放锚点下方

        // 下越界 → 翻到上方
        if y < screen.minY {
            y = anchor.y + offset
        }
        // 上越界（虽罕见）→ 夹紧到屏幕内
        if y + size.height > screen.maxY {
            y = screen.maxY - size.height
        }
        // 左右夹紧
        x = max(screen.minX, min(x, screen.maxX - size.width))
        return CGPoint(x: x, y: y)
    }
}
```

- [ ] **Step 27.4:** Run — pass

- [ ] **Step 27.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/Windowing/ScreenAwarePositioner.swift SliceAIKit/Tests/WindowingTests/
git rm SliceAIKit/Sources/Windowing/_ModuleMarker.swift 2>/dev/null || true
git rm SliceAIKit/Tests/WindowingTests/_TestMarker.swift 2>/dev/null || true
git commit -m "feat(windowing): add ScreenAwarePositioner with edge clamping"
```

### Task 28: PanelStyle (shared styling)

**Files:**
- Create: `SliceAIKit/Sources/Windowing/PanelStyle.swift`

- [ ] **Step 28.1:** Implement

```swift
// SliceAIKit/Sources/Windowing/PanelStyle.swift
import SwiftUI
import AppKit

/// 统一的 NSPanel 外观常量
public enum PanelStyle {
    public static let cornerRadius: CGFloat = 10
    public static let backgroundColor = NSColor(white: 0.12, alpha: 0.95)
    public static let borderColor = NSColor(white: 0.3, alpha: 0.8)
    public static let shadowBlur: CGFloat = 20
    public static let shadowOpacity: Float = 0.4
    public static let toolbarButtonSize = CGSize(width: 30, height: 30)
    public static let toolbarPadding: CGFloat = 6
}

/// SwiftUI 里使用的暗色主题调色板
public enum PanelColors {
    public static let background = Color(nsColor: PanelStyle.backgroundColor)
    public static let button = Color.white.opacity(0.1)
    public static let buttonHover = Color.white.opacity(0.2)
    public static let text = Color.white.opacity(0.95)
    public static let textSecondary = Color.white.opacity(0.6)
    public static let accent = Color.blue
}
```

- [ ] **Step 28.2:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/Windowing/PanelStyle.swift
git commit -m "feat(windowing): add shared PanelStyle constants"
```

### Task 29: FloatingToolbarPanel

**Files:**
- Create: `SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift`

- [ ] **Step 29.1:** Implement

```swift
// SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift
import AppKit
import SwiftUI
import SliceCore

/// 划词后弹出的紧贴选区浮条（A 模式）
@MainActor
public final class FloatingToolbarPanel {

    private var panel: NSPanel?
    private let positioner = ScreenAwarePositioner()
    private var autoDismissTask: Task<Void, Never>?

    public init() {}

    /// 显示浮条
    /// - Parameters:
    ///   - tools: 要展示的工具列表（按顺序）
    ///   - anchor: 选区中心（屏幕坐标）
    ///   - onPick: 用户点击某工具时回调
    public func show(tools: [Tool], anchor: CGPoint, onPick: @escaping (Tool) -> Void) {
        let width = CGFloat(tools.count) * (PanelStyle.toolbarButtonSize.width + 4)
            + PanelStyle.toolbarPadding * 2
        let height = PanelStyle.toolbarButtonSize.height + PanelStyle.toolbarPadding * 2
        let size = CGSize(width: max(width, 120), height: height)

        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.contains(anchor)
        })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let origin = positioner.position(anchor: anchor, size: size, screen: screen, offset: 8)

        let panel = makePanel(size: size, origin: origin)
        let hosting = NSHostingView(rootView: ToolbarContent(tools: tools, onPick: { [weak self] t in
            onPick(t)
            self?.dismiss()
        }))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        // 5s 无交互自动消失
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismiss() }
        }
    }

    public func dismiss() {
        autoDismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(size: CGSize, origin: CGPoint) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        return panel
    }
}

private struct ToolbarContent: View {
    let tools: [Tool]
    let onPick: (Tool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tools) { tool in
                Button { onPick(tool) } label: {
                    Text(tool.icon)
                        .font(.system(size: 16))
                        .frame(width: PanelStyle.toolbarButtonSize.width,
                               height: PanelStyle.toolbarButtonSize.height)
                        .background(PanelColors.button)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(tool.name)
            }
        }
        .padding(PanelStyle.toolbarPadding)
        .background(PanelColors.background)
        .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cornerRadius))
    }
}
```

- [ ] **Step 29.2:** Build

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
```

- [ ] **Step 29.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift
git commit -m "feat(windowing): add FloatingToolbarPanel (NSPanel + SwiftUI)"
```

### Task 30: CommandPalettePanel

**Files:**
- Create: `SliceAIKit/Sources/Windowing/CommandPalettePanel.swift`

- [ ] **Step 30.1:** Implement

```swift
// SliceAIKit/Sources/Windowing/CommandPalettePanel.swift
import AppKit
import SwiftUI
import SliceCore

/// 快捷键 ⌥Space 调出的中央命令面板（C 模式）
@MainActor
public final class CommandPalettePanel {

    private var panel: NSPanel?

    public init() {}

    public func show(tools: [Tool], preview: String?, onPick: @escaping (Tool) -> Void) {
        let size = CGSize(width: 480, height: 360)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2
        )
        let panel = makePanel(size: size, origin: origin)
        let hosting = NSHostingView(rootView: PaletteContent(
            tools: tools,
            preview: preview ?? "",
            onPick: { [weak self] t in
                onPick(t)
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    public func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(size: CGSize, origin: CGPoint) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }
}

private struct PaletteContent: View {
    let tools: [Tool]
    let preview: String
    let onPick: (Tool) -> Void
    let onCancel: () -> Void

    @State private var query: String = ""
    @State private var selection: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(PanelColors.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, 14).padding(.top, 12)
            }
            TextField("Search tools…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(14)
                .foregroundColor(PanelColors.text)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered.enumerated().map({ $0 }), id: \.offset) { idx, tool in
                        Button { onPick(tool) } label: {
                            HStack {
                                Text(tool.icon).font(.system(size: 18))
                                Text(tool.name)
                                    .foregroundColor(PanelColors.text)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(idx == selection ? PanelColors.accent : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
            .onKeyPress(.downArrow) { selection = min(filtered.count - 1, selection + 1); return .handled }
            .onKeyPress(.return) {
                if filtered.indices.contains(selection) { onPick(filtered[selection]) }
                return .handled
            }
            .onKeyPress(.escape) { onCancel(); return .handled }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelColors.background)
        .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cornerRadius))
    }

    private var filtered: [Tool] {
        guard !query.isEmpty else { return tools }
        let q = query.lowercased()
        return tools.filter {
            $0.name.lowercased().contains(q)
            || ($0.description?.lowercased().contains(q) ?? false)
        }
    }
}
```

- [ ] **Step 30.2:** Build & commit

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/Windowing/CommandPalettePanel.swift
git commit -m "feat(windowing): add CommandPalettePanel with keyboard navigation"
```

### Task 31: ResultPanel + StreamingMarkdownView

**Files:**
- Create: `SliceAIKit/Sources/Windowing/ResultPanel.swift`
- Create: `SliceAIKit/Sources/Windowing/StreamingMarkdownView.swift`

- [ ] **Step 31.1:** Implement StreamingMarkdownView

```swift
// SliceAIKit/Sources/Windowing/StreamingMarkdownView.swift
import SwiftUI

/// 流式 Markdown 文本视图
/// MVP 使用 SwiftUI 原生 AttributedString 解析（简单快速；复杂表格/代码块可在 v0.2 替换成 swift-markdown-ui）
public struct StreamingMarkdownView: View {
    public let text: String
    public let isStreaming: Bool

    public init(text: String, isStreaming: Bool) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let attr = try? AttributedString(markdown: text,
                     options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                     )) {
                    Text(attr)
                        .textSelection(.enabled)
                        .foregroundColor(PanelColors.text)
                        .font(.system(size: 14))
                } else {
                    Text(text)
                        .foregroundColor(PanelColors.text)
                        .font(.system(size: 14))
                }
                if isStreaming {
                    BlinkingCursor()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

private struct BlinkingCursor: View {
    @State private var visible = true
    var body: some View {
        Rectangle()
            .frame(width: 7, height: 14)
            .foregroundColor(PanelColors.accent)
            .opacity(visible ? 1 : 0)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    visible.toggle()
                }
            }
    }
}
```

- [ ] **Step 31.2:** Implement ResultPanel

```swift
// SliceAIKit/Sources/Windowing/ResultPanel.swift
import AppKit
import SwiftUI
import SliceCore

/// 独立浮窗，Markdown 流式渲染结果
@MainActor
public final class ResultPanel {

    private var panel: NSPanel?
    private let viewModel = ResultViewModel()

    public init() {}

    public func open(toolName: String, model: String) {
        if panel == nil {
            let size = CGSize(width: 560, height: 400)
            let origin: CGPoint
            if let screen = NSScreen.main?.visibleFrame {
                origin = CGPoint(x: screen.maxX - size.width - 40,
                                 y: screen.maxY - size.height - 40)
            } else {
                origin = CGPoint(x: 100, y: 100)
            }
            let panel = NSPanel(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered, defer: false
            )
            panel.level = .floating
            panel.title = "SliceAI"
            panel.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: ResultContent(viewModel: viewModel))
            hosting.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hosting
            self.panel = panel
        }
        viewModel.reset(toolName: toolName, model: model)
        panel?.makeKeyAndOrderFront(nil)
    }

    public func append(_ delta: String) { viewModel.append(delta) }
    public func finish() { viewModel.finish() }
    public func fail(with error: SliceError) { viewModel.fail(message: error.userMessage) }

    public func close() {
        panel?.orderOut(nil)
    }
}

@MainActor
final class ResultViewModel: ObservableObject {
    @Published var toolName: String = ""
    @Published var model: String = ""
    @Published var text: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?

    func reset(toolName: String, model: String) {
        self.toolName = toolName; self.model = model
        self.text = ""; self.isStreaming = true; self.errorMessage = nil
    }
    func append(_ s: String) { text += s }
    func finish() { isStreaming = false }
    func fail(message: String) { isStreaming = false; errorMessage = message }
}

private struct ResultContent: View {
    @ObservedObject var viewModel: ResultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(viewModel.toolName).font(.system(size: 13, weight: .semibold))
                Text("· \(viewModel.model)").font(.system(size: 11))
                    .foregroundColor(PanelColors.textSecondary)
                Spacer()
            }
            .foregroundColor(PanelColors.text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            if let err = viewModel.errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .padding(14)
            } else {
                StreamingMarkdownView(text: viewModel.text, isStreaming: viewModel.isStreaming)
            }
            Divider()
            HStack(spacing: 8) {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.text, forType: .string)
                }
                Spacer()
            }
            .padding(10)
        }
        .background(PanelColors.background)
        .foregroundColor(PanelColors.text)
    }
}
```

- [ ] **Step 31.3:** Build & commit

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/Windowing/
git commit -m "feat(windowing): add ResultPanel with streaming Markdown"
```

**M4 partial:** Windowing complete.

---

## Phase 6 — Permissions

### Task 32: AccessibilityMonitor

**Files:**
- Create: `SliceAIKit/Sources/Permissions/AccessibilityMonitor.swift`

- [ ] **Step 32.1:** Implement

```swift
// SliceAIKit/Sources/Permissions/AccessibilityMonitor.swift
import Foundation
import ApplicationServices
import AppKit

/// 监控 Accessibility 权限状态
/// AX API 不发通知，用轮询
@MainActor
public final class AccessibilityMonitor: ObservableObject {

    @Published public private(set) var isTrusted: Bool = false
    private var timer: Timer?

    public init() {
        refresh()
    }

    /// 启动轮询（每 1 秒检查一次）
    public func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stopMonitoring() { timer?.invalidate(); timer = nil }

    /// 请求权限并打开系统偏好（非阻塞，用户授予后由 monitor 自动反映）
    public func requestTrust() {
        let options: [CFString: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        // 打开对应系统偏好面板
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refresh() {
        isTrusted = AXIsProcessTrusted()
    }
}
```

- [ ] **Step 32.2:** Build & commit

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/Permissions/AccessibilityMonitor.swift
git rm SliceAIKit/Sources/Permissions/_ModuleMarker.swift 2>/dev/null || true
git commit -m "feat(permissions): add AccessibilityMonitor with polling"
```

### Task 33: OnboardingFlow

**Files:**
- Create: `SliceAIKit/Sources/Permissions/OnboardingFlow.swift`

- [ ] **Step 33.1:** Implement

```swift
// SliceAIKit/Sources/Permissions/OnboardingFlow.swift
import SwiftUI
import SliceCore

/// 首次启动向导，三步：欢迎 → 授予权限 → 录入 API Key
public struct OnboardingFlow: View {

    @ObservedObject var accessibilityMonitor: AccessibilityMonitor
    let onFinish: (_ apiKey: String) -> Void

    @State private var step: Step = .welcome
    @State private var apiKey: String = ""

    public init(accessibilityMonitor: AccessibilityMonitor,
                onFinish: @escaping (String) -> Void) {
        self.accessibilityMonitor = accessibilityMonitor
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch step {
            case .welcome:
                welcomeStep
            case .accessibility:
                accessibilityStep
            case .apiKey:
                apiKeyStep
            }
        }
        .frame(width: 480, height: 340)
        .padding(24)
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 12) {
            Text("欢迎使用 SliceAI").font(.title).bold()
            Text("划词即调用 LLM 的工具栏。3 步开始使用。")
                .foregroundStyle(.secondary)
            Spacer()
            Button("开始") { step = .accessibility }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("第 1 步：辅助功能权限").font(.title2).bold()
            Text("SliceAI 需要辅助功能权限才能读取你选中的文字。点下面的按钮，系统会打开相应设置页面。")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Circle()
                    .fill(accessibilityMonitor.isTrusted ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(accessibilityMonitor.isTrusted ? "已授予" : "未授予").bold()
            }
            Spacer()
            HStack {
                Button("打开辅助功能设置") { accessibilityMonitor.requestTrust() }
                Spacer()
                Button("下一步") { step = .apiKey }
                    .disabled(!accessibilityMonitor.isTrusted)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { accessibilityMonitor.startMonitoring() }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("第 2 步：录入 OpenAI API Key").font(.title2).bold()
            Text("Key 会保存在 macOS Keychain，不会写入磁盘明文。")
                .foregroundStyle(.secondary)
            SecureField("sk-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            Spacer()
            HStack {
                Button("稍后再说") { onFinish("") }
                Spacer()
                Button("完成") { onFinish(apiKey) }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    enum Step { case welcome, accessibility, apiKey }
}
```

- [ ] **Step 33.2:** Build & commit

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/Permissions/OnboardingFlow.swift
git commit -m "feat(permissions): add 3-step OnboardingFlow view"
```

---

## Phase 7 — SettingsUI

### Task 34: KeychainStore (concrete KeychainAccessing)

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/KeychainStore.swift`

- [ ] **Step 34.1:** Implement

```swift
// SliceAIKit/Sources/SettingsUI/KeychainStore.swift
import Foundation
import Security
import SliceCore

/// 基于系统 Keychain 的 KeychainAccessing 实现
public struct KeychainStore: KeychainAccessing {

    private let service: String

    public init(service: String = "com.sliceai.app.providers") {
        self.service = service
    }

    public func readAPIKey(providerId: String) async throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeAPIKey(_ value: String, providerId: String) async throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw NSError(domain: "KeychainStore", code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: "KeychainStore", code: Int(status))
        }
    }

    public func deleteAPIKey(providerId: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: "KeychainStore", code: Int(status))
        }
    }
}
```

- [ ] **Step 34.2:** Build & commit

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SettingsUI/KeychainStore.swift
git rm SliceAIKit/Sources/SettingsUI/_ModuleMarker.swift 2>/dev/null || true
git commit -m "feat(settings): add KeychainStore using Security framework"
```

### Task 35: ConfigurationStore (file IO)

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/ConfigurationStore.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift` (covered in SliceCoreTests to keep module deps simple)

Actually since ConfigurationStore imports SliceCore but lives in SettingsUI, put the test under a new `SettingsUITests` target. Easier: keep ConfigurationStore under SliceCore to make core fully self-contained. **Decision:** move `ConfigurationStore.swift` to `SliceCore/` so it's testable without AppKit.

Adjusted file path:
- Move: `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`

- [ ] **Step 35.1:** Failing tests

```swift
// SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift
import XCTest
@testable import SliceCore

final class ConfigurationStoreTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    func test_save_thenLoad_roundTrip() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileConfigurationStore(fileURL: url)

        let original = DefaultConfiguration.initial()
        try await store.save(original)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, original)
    }

    func test_load_missingFile_returnsDefault() async throws {
        let url = tempFile()
        let store = FileConfigurationStore(fileURL: url)
        let cfg = try await store.load()
        XCTAssertEqual(cfg.schemaVersion, Configuration.currentSchemaVersion)
    }

    func test_load_invalidJSON_throws() async throws {
        let url = tempFile()
        try "not json".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileConfigurationStore(fileURL: url)
        do {
            _ = try await store.load()
            XCTFail("expected throw")
        } catch SliceError.configuration(.invalidJSON) {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_load_schemaVersionTooNew_throws() async throws {
        let url = tempFile()
        let json = """
        { "schemaVersion": 99, "providers": [], "tools": [], "hotkeys": {"toggleCommandPalette":"option+space"},
          "triggers":{"floatingToolbarEnabled":true,"commandPaletteEnabled":true,"minimumSelectionLength":1,"triggerDelayMs":150},
          "telemetry":{"enabled":false}, "appBlocklist":[] }
        """
        try json.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileConfigurationStore(fileURL: url)
        do {
            _ = try await store.load()
            XCTFail("expected throw")
        } catch SliceError.configuration(.schemaVersionTooNew(99)) {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
```

- [ ] **Step 35.2:** Run — fail

- [ ] **Step 35.3:** Implement FileConfigurationStore (in `SliceCore/`)

```swift
// SliceAIKit/Sources/SliceCore/ConfigurationStore.swift
import Foundation

/// 以 JSON 文件为后端的 Configuration 读写
public actor FileConfigurationStore: ConfigurationProviding {

    private let fileURL: URL
    private var cached: Configuration?

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func current() async -> Configuration {
        if let cached { return cached }
        if let c = try? await load() {
            cached = c
            return c
        }
        let fallback = DefaultConfiguration.initial()
        cached = fallback
        return fallback
    }

    public func update(_ configuration: Configuration) async throws {
        try await save(configuration)
        cached = configuration
    }

    /// 从文件加载；文件不存在返回默认配置
    public func load() async throws -> Configuration {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return DefaultConfiguration.initial()
        }
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch { throw SliceError.configuration(.invalidJSON(error.localizedDescription)) }

        let decoder = JSONDecoder()
        let cfg: Configuration
        do { cfg = try decoder.decode(Configuration.self, from: data) }
        catch { throw SliceError.configuration(.invalidJSON(error.localizedDescription)) }

        if cfg.schemaVersion > Configuration.currentSchemaVersion {
            throw SliceError.configuration(.schemaVersionTooNew(cfg.schemaVersion))
        }
        return cfg
    }

    /// 保存到文件（pretty-printed）
    public func save(_ configuration: Configuration) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        // 确保父目录存在
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 返回 config.json 标准路径
    public static func standardFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("config.json")
    }
}
```

- [ ] **Step 35.4:** Run — pass

- [ ] **Step 35.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SliceCore/ConfigurationStore.swift SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift
git commit -m "feat(core): add FileConfigurationStore with schema version guard"
```

### Task 36: SettingsScene + editors

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
- Create: `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`
- Create: `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift`
- Create: `SliceAIKit/Sources/SettingsUI/HotkeyEditorView.swift`
- Create: `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`

Due to size, we combine multiple implementations. Each file should stay ≤ 300 lines.

- [ ] **Step 36.1:** SettingsViewModel

```swift
// SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift
import Foundation
import SliceCore
import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {

    @Published public var configuration: Configuration

    private let store: any ConfigurationProviding
    private let keychain: any KeychainAccessing

    public init(store: any ConfigurationProviding, keychain: any KeychainAccessing) {
        self.store = store
        self.keychain = keychain
        self.configuration = DefaultConfiguration.initial()
        Task { await self.reload() }
    }

    public func reload() async {
        let cfg = await store.current()
        self.configuration = cfg
    }

    public func save() async throws {
        try await store.update(configuration)
    }

    public func setAPIKey(_ key: String, for providerId: String) async throws {
        try await keychain.writeAPIKey(key, providerId: providerId)
    }

    public func readAPIKey(for providerId: String) async throws -> String? {
        try await keychain.readAPIKey(providerId: providerId)
    }
}
```

- [ ] **Step 36.2:** ToolEditorView

```swift
// SliceAIKit/Sources/SettingsUI/ToolEditorView.swift
import SwiftUI
import SliceCore

public struct ToolEditorView: View {
    @Binding public var tool: Tool
    public let providers: [Provider]

    public init(tool: Binding<Tool>, providers: [Provider]) {
        self._tool = tool; self.providers = providers
    }

    public var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $tool.name)
                TextField("Icon", text: $tool.icon)
                TextField("Description", text: .init(
                    get: { tool.description ?? "" },
                    set: { tool.description = $0.isEmpty ? nil : $0 }
                ))
            }
            Section("Prompt") {
                TextField("System", text: .init(
                    get: { tool.systemPrompt ?? "" },
                    set: { tool.systemPrompt = $0.isEmpty ? nil : $0 }
                ), axis: .vertical).lineLimit(2...5)
                TextField("User", text: $tool.userPrompt, axis: .vertical).lineLimit(3...8)
                Text("可用变量: {{selection}} {{app}} {{url}} {{language}}")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Provider") {
                Picker("Provider", selection: $tool.providerId) {
                    ForEach(providers) { p in Text(p.name).tag(p.id) }
                }
                TextField("Model override", text: .init(
                    get: { tool.modelId ?? "" },
                    set: { tool.modelId = $0.isEmpty ? nil : $0 }
                ))
                HStack {
                    Text("Temperature")
                    Slider(value: .init(
                        get: { tool.temperature ?? 0.3 },
                        set: { tool.temperature = $0 }
                    ), in: 0...2)
                    Text(String(format: "%.2f", tool.temperature ?? 0.3))
                        .frame(width: 48, alignment: .trailing)
                }
            }
            Section("Variables") {
                ForEach(Array(tool.variables.keys.sorted()), id: \.self) { key in
                    TextField(key, text: .init(
                        get: { tool.variables[key] ?? "" },
                        set: { tool.variables[key] = $0 }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 36.3:** ProviderEditorView

```swift
// SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift
import SwiftUI
import SliceCore

public struct ProviderEditorView: View {
    @Binding public var provider: Provider
    @State private var apiKey: String = ""
    let onSaveKey: (String) async -> Void
    let onLoadKey: () async -> String?

    public init(provider: Binding<Provider>,
                onSaveKey: @escaping (String) async -> Void,
                onLoadKey: @escaping () async -> String?) {
        self._provider = provider
        self.onSaveKey = onSaveKey
        self.onLoadKey = onLoadKey
    }

    public var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $provider.name)
                TextField("Base URL", text: .init(
                    get: { provider.baseURL.absoluteString },
                    set: { if let url = URL(string: $0) { provider.baseURL = url } }
                ))
                TextField("Default Model", text: $provider.defaultModel)
            }
            Section("API Key") {
                SecureField("sk-…", text: $apiKey)
                HStack {
                    Button("Save key") {
                        Task { await onSaveKey(apiKey) }
                    }.disabled(apiKey.isEmpty)
                    Spacer()
                    Text("Stored in macOS Keychain")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            if let existing = await onLoadKey() { apiKey = existing }
        }
    }
}
```

- [ ] **Step 36.4:** HotkeyEditorView

```swift
// SliceAIKit/Sources/SettingsUI/HotkeyEditorView.swift
import SwiftUI
import SliceCore

public struct HotkeyEditorView: View {
    @Binding public var binding: String
    @State private var error: String?

    public init(binding: Binding<String>) { self._binding = binding }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Command Palette").frame(width: 140, alignment: .leading)
                TextField("option+space", text: $binding)
                    .onSubmit { validate() }
            }
            if let error {
                Text(error).foregroundColor(.red).font(.caption)
            }
            Text("支持: cmd / option / shift / ctrl / space / a–z / 0–9 / f1–f12 / 方向键 / return / esc")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private func validate() {
        // 这里仅做弱校验：空串或能被 Hotkey.parse 识别即可。真正的冲突检测由 HotkeyRegistrar 做。
        if binding.isEmpty { error = "不能为空"; return }
        error = nil
    }
}
```

- [ ] **Step 36.5:** SettingsScene (tabs)

```swift
// SliceAIKit/Sources/SettingsUI/SettingsScene.swift
import SwiftUI
import SliceCore

public struct SettingsScene: View {

    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedToolID: String?
    @State private var selectedProviderID: String?

    public init(viewModel: SettingsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        TabView {
            toolsTab.tabItem { Label("Tools", systemImage: "hammer") }
            providersTab.tabItem { Label("Providers", systemImage: "network") }
            hotkeyTab.tabItem { Label("Hotkeys", systemImage: "keyboard") }
            triggersTab.tabItem { Label("Triggers", systemImage: "cursorarrow.click") }
        }
        .frame(width: 720, height: 480)
    }

    // MARK: - Tabs

    private var toolsTab: some View {
        HSplitView {
            List(selection: $selectedToolID) {
                ForEach($viewModel.configuration.tools) { $tool in
                    HStack {
                        Text(tool.icon); Text(tool.name)
                    }.tag(tool.id as String?)
                }
                .onDelete { offsets in
                    viewModel.configuration.tools.remove(atOffsets: offsets)
                }
            }
            .frame(minWidth: 200)
            if let id = selectedToolID,
               let idx = viewModel.configuration.tools.firstIndex(where: { $0.id == id }) {
                ToolEditorView(tool: $viewModel.configuration.tools[idx],
                               providers: viewModel.configuration.providers)
            } else {
                Text("Select a tool").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            Button {
                let new = Tool(id: UUID().uuidString, name: "New Tool", icon: "⚡",
                               description: nil, systemPrompt: nil,
                               userPrompt: "{{selection}}",
                               providerId: viewModel.configuration.providers.first?.id ?? "",
                               modelId: nil, temperature: 0.3, displayMode: .window,
                               variables: [:])
                viewModel.configuration.tools.append(new)
                selectedToolID = new.id
            } label: { Image(systemName: "plus") }
            Button { Task { try? await viewModel.save() } } label: { Image(systemName: "square.and.arrow.down") }
        }
    }

    private var providersTab: some View {
        HSplitView {
            List(selection: $selectedProviderID) {
                ForEach($viewModel.configuration.providers) { $p in
                    Text(p.name).tag(p.id as String?)
                }
            }
            .frame(minWidth: 200)
            if let id = selectedProviderID,
               let idx = viewModel.configuration.providers.firstIndex(where: { $0.id == id }) {
                ProviderEditorView(
                    provider: $viewModel.configuration.providers[idx],
                    onSaveKey: { key in
                        try? await viewModel.setAPIKey(key, for: id)
                    },
                    onLoadKey: {
                        (try? await viewModel.readAPIKey(for: id)) ?? nil
                    }
                )
            } else {
                Text("Select a provider").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var hotkeyTab: some View {
        HotkeyEditorView(binding: $viewModel.configuration.hotkeys.toggleCommandPalette)
    }

    private var triggersTab: some View {
        Form {
            Toggle("Floating Toolbar 启用", isOn: $viewModel.configuration.triggers.floatingToolbarEnabled)
            Toggle("Command Palette 启用", isOn: $viewModel.configuration.triggers.commandPaletteEnabled)
            Stepper("最小选中长度: \(viewModel.configuration.triggers.minimumSelectionLength)",
                    value: $viewModel.configuration.triggers.minimumSelectionLength,
                    in: 1...100)
            Stepper("触发延迟: \(viewModel.configuration.triggers.triggerDelayMs) ms",
                    value: $viewModel.configuration.triggers.triggerDelayMs,
                    in: 0...2000, step: 50)
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 36.6:** Build & commit

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift build
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Sources/SettingsUI/
git commit -m "feat(settings): add SettingsScene with tools/providers/hotkeys/triggers tabs"
```

**M4 reached:** SettingsUI complete, entire `SliceAIKit` feature complete.

---

## Phase 8 — App Shell (Xcode project)

This phase requires **manual Xcode interaction** (create project UI + drop files). Document each step precisely.

### Task 37: Create Xcode App target

**Files:**
- Create: `SliceAI.xcodeproj/` (via Xcode GUI)
- Create: `SliceAIApp/SliceAIApp.swift`
- Create: `SliceAIApp/Info.plist`
- Create: `SliceAIApp/Assets.xcassets/` (via Xcode)
- Create: `SliceAIApp/SliceAI.entitlements`

- [ ] **Step 37.1:** Open Xcode → File → New → Project

  - Template: **macOS → App**
  - Click Next
  - Product Name: **SliceAI**
  - Team: **None** (unsigned for MVP)
  - Organization Identifier: `com.sliceai`
  - Bundle Identifier (auto): `com.sliceai.SliceAI`
  - Interface: **SwiftUI**
  - Language: **Swift**
  - Uncheck: Core Data, Tests
  - Click Next
  - Save to: `/Users/majiajun/workspace/SliceAI/` → **Uncheck "Create Git repository"** (we already have one)
  - Xcode will create `SliceAI.xcodeproj/` and a `SliceAI/` source folder

- [ ] **Step 37.2:** Rename source folder to `SliceAIApp`

  - In Finder: rename `/Users/majiajun/workspace/SliceAI/SliceAI/` → `SliceAIApp/`
  - In Xcode: right-click yellow folder named "SliceAI" in navigator → Rename → "SliceAIApp"
  - In Xcode: click on "SliceAIApp" target → Build Settings → search `INFOPLIST_FILE` → update path if needed

- [ ] **Step 37.3:** Remove the auto-generated `SliceAIApp.swift` and `ContentView.swift`

  - These will be replaced with our own @main in Task 38

- [ ] **Step 37.4:** Set macOS deployment target to 14.0

  - Target → General → Minimum Deployments → macOS 14.0

- [ ] **Step 37.5:** Add local Swift Package dependency

  - File → Add Package Dependencies → Click "Add Local..."
  - Navigate to `/Users/majiajun/workspace/SliceAI/SliceAIKit/`
  - Add "SliceAIKit"
  - Target: `SliceAI` (the app target)
  - Add all 7 library products

- [ ] **Step 37.6:** Commit Xcode project files

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAI.xcodeproj/ SliceAIApp/
git commit -m "chore: create Xcode app project and link SliceAIKit local package"
```

### Task 38: @main SliceAIApp

**Files:**
- Create: `SliceAIApp/SliceAIApp.swift`
- Create: `SliceAIApp/AppDelegate.swift`
- Create: `SliceAIApp/AppContainer.swift`

- [ ] **Step 38.1:** AppContainer (DI root)

```swift
// SliceAIApp/AppContainer.swift
import Foundation
import AppKit
import SliceCore
import LLMProviders
import SelectionCapture
import HotkeyManager
import Windowing
import Permissions
import SettingsUI

/// 应用的 DI 组合根：一次创建，在 AppDelegate 中持有
@MainActor
final class AppContainer {

    let configStore: FileConfigurationStore
    let keychain: KeychainStore
    let selectionService: SelectionService
    let hotkeyRegistrar: HotkeyRegistrar
    let toolExecutor: ToolExecutor
    let floatingToolbar: FloatingToolbarPanel
    let commandPalette: CommandPalettePanel
    let resultPanel: ResultPanel
    let accessibilityMonitor: AccessibilityMonitor
    let settingsViewModel: SettingsViewModel

    init() {
        configStore = FileConfigurationStore(fileURL: FileConfigurationStore.standardFileURL())
        keychain = KeychainStore()
        selectionService = SelectionService(
            primary: AXSelectionSource(),
            fallback: ClipboardSelectionSource(
                pasteboard: SystemPasteboard(),
                copyInvoker: SystemCopyKeystrokeInvoker(),
                focusProvider: {
                    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
                    return FocusInfo(
                        bundleID: app.bundleIdentifier ?? "",
                        appName: app.localizedName ?? "",
                        url: nil,
                        screenPoint: NSEvent.mouseLocation
                    )
                }
            )
        )
        hotkeyRegistrar = HotkeyRegistrar()
        toolExecutor = ToolExecutor(
            configurationProvider: configStore,
            providerFactory: OpenAIProviderFactory(),
            keychain: keychain
        )
        floatingToolbar = FloatingToolbarPanel()
        commandPalette = CommandPalettePanel()
        resultPanel = ResultPanel()
        accessibilityMonitor = AccessibilityMonitor()
        settingsViewModel = SettingsViewModel(store: configStore, keychain: keychain)
    }
}
```

- [ ] **Step 38.2:** AppDelegate

```swift
// SliceAIApp/AppDelegate.swift
import AppKit
import SwiftUI
import SliceCore
import SelectionCapture
import HotkeyManager

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let container: AppContainer
    private var globalMouseMonitor: Any?
    private var debounceTask: Task<Void, Never>?
    private var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    override init() {
        self.container = AppContainer()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏图标
        menuBarController = MenuBarController(container: container, delegate: self)

        // 权限监控
        container.accessibilityMonitor.startMonitoring()
        if !container.accessibilityMonitor.isTrusted {
            showOnboarding()
        } else {
            wireRuntime()
        }
    }

    // MARK: - 运行时接线

    func wireRuntime() {
        registerHotkey()
        installMouseMonitor()
    }

    private func registerHotkey() {
        Task { [self] in
            let cfg = await container.configStore.current()
            guard cfg.triggers.commandPaletteEnabled else { return }
            do {
                let hk = try Hotkey.parse(cfg.hotkeys.toggleCommandPalette)
                _ = try container.hotkeyRegistrar.register(hk) { [weak self] in
                    Task { @MainActor in self?.showCommandPalette() }
                }
            } catch {
                NSLog("Hotkey register failed: \(error)")
            }
        }
    }

    private func installMouseMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.onMouseUp()
        }
    }

    private func onMouseUp() {
        Task { @MainActor in
            let cfg = await container.configStore.current()
            guard cfg.triggers.floatingToolbarEnabled else { return }
            debounceTask?.cancel()
            let delay = cfg.triggers.triggerDelayMs
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                if Task.isCancelled { return }
                await self.tryCaptureAndShowToolbar(cfg)
            }
        }
    }

    private func tryCaptureAndShowToolbar(_ cfg: Configuration) async {
        guard let payload = try? await container.selectionService.capture() else { return }
        // 过滤黑名单应用
        if cfg.appBlocklist.contains(payload.appBundleID) { return }
        guard payload.text.count >= cfg.triggers.minimumSelectionLength else { return }
        container.floatingToolbar.show(tools: cfg.tools, anchor: payload.screenPoint) { [weak self] tool in
            self?.execute(tool: tool, payload: payload)
        }
    }

    // MARK: - Command Palette

    func showCommandPalette() {
        Task { @MainActor in
            let cfg = await container.configStore.current()
            let payload = (try? await container.selectionService.capture())
            container.commandPalette.show(
                tools: cfg.tools,
                preview: payload?.text
            ) { [weak self] tool in
                guard let self else { return }
                if let payload {
                    self.execute(tool: tool, payload: payload)
                }
            }
        }
    }

    // MARK: - 执行工具

    func execute(tool: SliceCore.Tool, payload: SelectionPayload) {
        container.resultPanel.open(toolName: tool.name,
                                   model: tool.modelId ?? "default")
        Task { @MainActor in
            do {
                let stream = try await container.toolExecutor.execute(tool: tool, payload: payload)
                for try await chunk in stream {
                    container.resultPanel.append(chunk.delta)
                }
                container.resultPanel.finish()
            } catch let err as SliceError {
                container.resultPanel.fail(with: err)
            } catch {
                container.resultPanel.fail(with: .provider(.invalidResponse(String(describing: error))))
            }
        }
    }

    // MARK: - Windows

    func showSettings() {
        if let win = settingsWindow { win.makeKeyAndOrderFront(nil); return }
        let hosting = NSHostingController(rootView: SettingsScene(viewModel: container.settingsViewModel))
        let win = NSWindow(contentViewController: hosting)
        win.title = "SliceAI Settings"
        win.styleMask = [.titled, .closable, .resizable]
        win.setContentSize(NSSize(width: 720, height: 480))
        win.isReleasedWhenClosed = false
        win.center()
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        let view = OnboardingFlow(
            accessibilityMonitor: container.accessibilityMonitor,
            onFinish: { [weak self] apiKey in
                Task { @MainActor in
                    guard let self else { return }
                    if !apiKey.isEmpty {
                        try? await self.container.keychain.writeAPIKey(apiKey,
                                                                       providerId: "openai-official")
                    }
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                    self.wireRuntime()
                }
            }
        )
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Welcome to SliceAI"
        win.styleMask = [.titled]
        win.setContentSize(NSSize(width: 480, height: 340))
        win.isReleasedWhenClosed = false
        win.center()
        onboardingWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 38.3:** MenuBarController

```swift
// SliceAIApp/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController {

    weak var delegate: AppDelegate?
    private let statusItem: NSStatusItem

    init(container: AppContainer, delegate: AppDelegate) {
        self.delegate = delegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SliceAI")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "SliceAI", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings),
                                keyEquivalent: ",").withTarget(self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    @objc private func openSettings() { delegate?.showSettings() }
}

private extension NSMenuItem {
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
```

- [ ] **Step 38.4:** @main

```swift
// SliceAIApp/SliceAIApp.swift
import SwiftUI
import AppKit

@main
struct SliceAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 空 Settings scene：真正的 Settings 窗口由 AppDelegate.showSettings 触发
        // 保留一个 no-op scene 来满足 SwiftUI App 协议
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 38.5:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIApp/
git commit -m "feat(app): add @main app, AppDelegate, MenuBarController, AppContainer DI"
```

### Task 39: Info.plist entitlements

**Files:**
- Modify: `SliceAIApp/Info.plist`
- Create: `SliceAIApp/SliceAI.entitlements`

- [ ] **Step 39.1:** Update Info.plist

In Xcode, open `Info.plist`:
- Add `LSUIElement` = YES (隐藏 Dock 图标，menu bar only)
- Add `NSAccessibilityUsageDescription` = "SliceAI 需要辅助功能权限来读取你在其他应用中选中的文字。"
- Add `NSAppleEventsUsageDescription` = "SliceAI 使用 Apple 事件转发选中文字请求。"

Alternatively, open Info.plist in text editor:

```xml
<key>LSUIElement</key>
<true/>
<key>NSAccessibilityUsageDescription</key>
<string>SliceAI 需要辅助功能权限来读取你在其他应用中选中的文字。</string>
```

- [ ] **Step 39.2:** Entitlements file

Xcode: target → Signing & Capabilities → add capability "Hardened Runtime". Xcode will generate `SliceAI.entitlements`.

Open `SliceAI.entitlements` and ensure it looks like:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <false/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
```

**Note:** App sandbox MUST be OFF — we need global event monitor + AX API + Carbon hotkeys. Mac App Store is not a target (per spec §1.3).

- [ ] **Step 39.3:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIApp/Info.plist SliceAIApp/SliceAI.entitlements SliceAI.xcodeproj/
git commit -m "feat(app): add Info.plist usage descriptions and entitlements (non-sandboxed)"
```

### Task 40: Smoke test — run app end-to-end

- [ ] **Step 40.1:** Build & Run in Xcode (⌘R)
- [ ] **Step 40.2:** Verify onboarding flow appears on first run
- [ ] **Step 40.3:** Click "打开辅助功能设置" → system opens Accessibility pane
- [ ] **Step 40.4:** Add SliceAI.app to allowed list → toggle on
- [ ] **Step 40.5:** Onboarding shows "已授予"; proceed; enter API key; finish
- [ ] **Step 40.6:** Open Safari, select 5 Chinese chars → floating toolbar should appear within 200ms
- [ ] **Step 40.7:** Click Translate → ResultPanel opens, Markdown streams in
- [ ] **Step 40.8:** Press ⌥Space → CommandPalettePanel shows; arrow keys navigate; Enter triggers tool; Esc closes

If any step fails, debug and fix before proceeding. Common issues:
- Panel doesn't appear → check `panel.level = .statusBar` and `canJoinAllSpaces`
- AX returns nil on Electron apps → expected; Cmd+C fallback should kick in
- Hotkey doesn't fire → check `hotkeyRegistrar.register()` throws status; Carbon sometimes fails if another app already owns the combo

- [ ] **Step 40.9:** Commit any fixes

```bash
cd /Users/majiajun/workspace/SliceAI
git add -A
git commit -m "fix(app): address issues found during first smoke run"
```

**M5 reached:** Full MVP running end-to-end on dev machine.

---

## Phase 9 — Release

### Task 41: build-dmg.sh script

**Files:**
- Create: `scripts/build-dmg.sh`

- [ ] **Step 41.1:** Write script

```bash
#!/usr/bin/env bash
# scripts/build-dmg.sh
# 用法: scripts/build-dmg.sh 0.1.0
# 产物: build/SliceAI-<version>.dmg
set -euo pipefail

VERSION="${1:-0.1.0}"
SCHEME="SliceAI"
PROJECT="SliceAI.xcodeproj"
BUILD_DIR="build"
EXPORT_DIR="$BUILD_DIR/export"
DMG_STAGING="$BUILD_DIR/dmg-staging"

rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR" "$DMG_STAGING"

# 归档（unsigned）
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$BUILD_DIR/SliceAI.xcarchive" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  archive

# 从 archive 中取出 .app
cp -R "$BUILD_DIR/SliceAI.xcarchive/Products/Applications/SliceAI.app" "$DMG_STAGING/"

# 创建 Applications 软链
ln -s /Applications "$DMG_STAGING/Applications"

# 打包 dmg
DMG_PATH="$BUILD_DIR/SliceAI-$VERSION.dmg"
hdiutil create -volname "SliceAI $VERSION" \
  -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

echo "Built: $DMG_PATH"
```

- [ ] **Step 41.2:** Make executable

```bash
chmod +x /Users/majiajun/workspace/SliceAI/scripts/build-dmg.sh
```

- [ ] **Step 41.3:** Test locally

```bash
cd /Users/majiajun/workspace/SliceAI
scripts/build-dmg.sh 0.1.0-test
```

Expected: `build/SliceAI-0.1.0-test.dmg` created; mount it to verify app runs.

- [ ] **Step 41.4:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add scripts/build-dmg.sh
git commit -m "build: add unsigned DMG build script"
```

### Task 42: release.yml workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 42.1:** Write workflow

```yaml
name: Release
on:
  push:
    tags: ["v*"]

jobs:
  build:
    runs-on: macos-15
    timeout-minutes: 45
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode 16
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Extract version
        id: ver
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Build DMG
        run: scripts/build-dmg.sh "${{ steps.ver.outputs.version }}"

      - name: Upload DMG artifact
        uses: actions/upload-artifact@v4
        with:
          name: SliceAI-${{ steps.ver.outputs.version }}.dmg
          path: build/SliceAI-${{ steps.ver.outputs.version }}.dmg

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/SliceAI-${{ steps.ver.outputs.version }}.dmg
          draft: true
          generate_release_notes: true
          body: |
            ## SliceAI ${{ steps.ver.outputs.version }}

            **Unsigned DMG.** Installation steps:
            1. Mount the DMG and drag `SliceAI.app` to `/Applications`
            2. First launch: Right-click → Open (because unsigned)
               Or run: `xattr -d com.apple.quarantine /Applications/SliceAI.app`
            3. Grant Accessibility permission when prompted
            4. Enter your OpenAI API key (or any OpenAI-compatible base URL + key)
```

- [ ] **Step 42.2:** Commit

```bash
cd /Users/majiajun/workspace/SliceAI
git add .github/workflows/release.yml
git commit -m "ci: add release workflow that builds DMG on tag push"
```

### Task 43: Tag v0.1.0

- [ ] **Step 43.1:** Final checks

```bash
cd /Users/majiajun/workspace/SliceAI/SliceAIKit && swift test
cd /Users/majiajun/workspace/SliceAI && scripts/build-dmg.sh 0.1.0-preflight
```

Both must succeed.

- [ ] **Step 43.2:** Install DMG on a fresh Mac user account or second Mac to validate unsigned-install flow

- [ ] **Step 43.3:** Push main + tag

```bash
cd /Users/majiajun/workspace/SliceAI
# Push to GitHub origin (user configures remote separately)
git push origin main
git tag v0.1.0 -m "Release v0.1.0: MVP"
git push origin v0.1.0
```

- [ ] **Step 43.4:** Wait for release.yml workflow to succeed, verify DMG uploaded to GitHub Releases

- [ ] **Step 43.5:** Manually publish the draft release after checking notes

**M6 reached:** `SliceAI-0.1.0.dmg` is public. Ship.

---

## Self-Review — Coverage Check

| Spec section | Implementing task(s) |
|---|---|
| §1.4 Success criteria | Tasks 40 (smoke), Task 15 (coverage) |
| §2 Architecture (7 modules) | Tasks 6-36 |
| §3.3 Timing (150ms debounce) | Task 38.2 (`onMouseUp` debounce) |
| §4.1 SelectionPayload | Task 6 |
| §4.2 Tool/Provider/DisplayMode | Task 8 |
| §4.3 LLMProvider protocol | Task 12 |
| §4.4 ToolExecutor | Task 14 |
| §4.5 PromptTemplate | Task 10 |
| §5.1 Onboarding | Tasks 32, 33, 38 |
| §5.2 FloatingToolbar flow | Tasks 29, 38.2 |
| §5.3 CommandPalette flow | Tasks 30, 38 `showCommandPalette` |
| §5.4 Tool execution | Tasks 14, 18, 38 `execute` |
| §6 Configuration JSON | Tasks 9, 35 |
| §6.3 Keychain | Task 34 |
| §6.4 Default config | Task 13 |
| §7 SliceError hierarchy + degradation | Task 11, Task 18 (status code mapping), Task 24 (fallback) |
| §8 Testing | Tasks 6-27 TDD pattern + Task 15 (coverage) |
| §9 Project structure & CI | Tasks 1-5, 41-43 |
| §10 Roadmap v0.1 scope | Entire plan |

**Gaps found during self-review and fixed:**
- Added Task 19 (`OpenAIProviderFactory`) — spec implied but not a listed component
- Moved `ConfigurationStore` from `SettingsUI` module to `SliceCore` so it's testable without AppKit; noted in Task 35
- Clarified app sandbox must be OFF in Task 39.2 (not in spec, but necessary due to global event monitor)

**Known residual risks (from spec Appendix B):**
- AX availability: verify in Task 40 smoke across Safari / VSCode / Figma / Slack
- SSE format variance: Task 20 fixtures cover OpenAI; add DeepSeek / Moonshot fixtures in v0.1.x if user reports
- `SliceAI` name duplication on GitHub: grep before pushing to origin
- Accessibility permission polling: implemented in Task 32 as 1s timer (acceptable for MVP)

---

_End of plan. Refer to spec `docs/superpowers/specs/2026-04-20-sliceai-design.md` for design rationale._


