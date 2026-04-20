// swift-tools-version:6.0
// SliceAIKit - SliceAI 核心功能包，7 个 target 承载领域层、LLM 调用、划词捕获、快捷键、窗口、权限、设置界面
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // 启用 Swift 6 严格并发检查，所有类型强制 Sendable
    // 注：InferSendableFromCaptures 在 Swift 6 已默认启用，无需显式声明
    .enableUpcomingFeature("ExistentialAny"),
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
