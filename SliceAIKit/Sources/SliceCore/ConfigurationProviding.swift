import Foundation

/// 提供当前 Configuration 的协议。SettingsUI 持有并发布 updates
public protocol ConfigurationProviding: Sendable {
    func current() async -> Configuration
    func update(_ configuration: Configuration) async throws
}
