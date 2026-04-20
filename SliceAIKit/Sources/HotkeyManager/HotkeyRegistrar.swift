import AppKit
import Carbon
import Foundation

/// 全局快捷键注册 / 注销封装，基于 Carbon `RegisterEventHotKey`
///
/// 选用 Carbon 的原因：`NSEvent.addGlobalMonitor` 仅能观察，无法拦截事件，
/// 且在无激活窗口时表现不稳定；Carbon HotKey 由系统级调度，无窗口也可响应。
///
/// 线程与并发说明：
/// - Carbon 事件处理器运行在主 RunLoop 所在线程（通常即主线程），因此 `refByID` 与
///   `callbackByID` 的读/写在实际运行时均串行发生在同一线程；类被标记为
///   `@unchecked Sendable`，依赖该不变量而非语言层的静态检查。
/// - `register` / `unregister` 预期由调用方在主线程调用。
/// - 回调会通过 `DispatchQueue.main.async` 派发，回调内部可直接进行 UI 操作。
///
/// 生命周期约束：
/// - 调用方 **必须** 持有 `HotkeyRegistrar` 实例至所有注册都不再需要为止。
///   一旦实例释放，`deinit` 会先 `RemoveEventHandler` 再 `UnregisterEventHotKey`，
///   之后若 Carbon 仍回调已释放的 `self` 会立即崩溃。
/// - 我们通过 `Unmanaged.passUnretained(self)` 将 `self` 指针传给 C handler，
///   不持有强引用，避免循环引用，但也因此要求调用方显式管理生命周期。
public final class HotkeyRegistrar: @unchecked Sendable {

    /// 快捷键触发回调；保证在主线程调用
    public typealias Callback = @Sendable () -> Void

    /// 已注册 HotKey 的原生句柄，key 为内部递增 id
    private var refByID: [UInt32: EventHotKeyRef] = [:]
    /// id 对应的用户回调
    private var callbackByID: [UInt32: Callback] = [:]
    /// 下一次 `register` 将分配的 id，单调递增
    private var nextID: UInt32 = 1
    /// Carbon 事件处理器句柄，`deinit` 时需要移除
    private var handler: EventHandlerRef?

    /// 构造即安装事件处理器，保证后续任何 `register` 都能收到 `kEventHotKeyPressed`
    public init() {
        installHandler()
    }

    /// 释放时先移除事件处理器，再注销所有已注册的 HotKey
    ///
    /// 顺序很关键：先 `RemoveEventHandler` 可以确保 Carbon 不会再触发回调到
    /// 即将销毁的 `self`；之后逐一 `UnregisterEventHotKey` 以释放系统侧的注册。
    deinit {
        if let handler {
            RemoveEventHandler(handler)
        }
        for (_, ref) in refByID {
            UnregisterEventHotKey(ref)
        }
    }

    /// 注册一个全局快捷键
    /// - Parameters:
    ///   - hotkey: 已解析好的 `Hotkey`（keyCode + 修饰键位掩码）
    ///   - callback: 快捷键触发时执行的闭包，将在主线程派发
    /// - Returns: 分配给该注册的 id，可传入 `unregister` 以单独注销
    /// - Throws: 当 `RegisterEventHotKey` 返回非 `noErr` 时，抛出包含 OSStatus 的 `NSError`
    @discardableResult
    public func register(_ hotkey: Hotkey, callback: @escaping Callback) throws -> UInt32 {
        // 分配一个新 id；signature 固定为 "SLIC" 便于日后在系统日志中筛选本应用的 HotKey
        let id = nextID
        nextID += 1
        let hotkeyID = EventHotKeyID(signature: fourCharCode("SLIC"), id: id)

        // 调用 Carbon API 真正向系统注册；`ref` 为 inout 返回的不透明句柄
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers.rawValue,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        // 校验注册结果：常见失败原因是组合已被其他进程占用（status = -9878 / eventHotKeyExistsErr）
        guard status == noErr, let ref else {
            throw NSError(
                domain: "HotkeyRegistrar",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "RegisterEventHotKey failed (OSStatus=\(status))"]
            )
        }

        // 注册成功后记录映射，后续事件分发与注销都依赖这两张表
        refByID[id] = ref
        callbackByID[id] = callback
        return id
    }

    /// 注销指定 id 的快捷键；若 id 不存在则静默忽略
    public func unregister(_ id: UInt32) {
        if let ref = refByID.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        callbackByID.removeValue(forKey: id)
    }

    /// 注销所有已注册的快捷键，常用于应用退出或设置变更前的重置
    public func unregisterAll() {
        // 先遍历 values 逐一调用 Carbon 注销，再清空本地映射，避免回调中访问到陈旧句柄
        for ref in refByID.values {
            UnregisterEventHotKey(ref)
        }
        refByID.removeAll()
        callbackByID.removeAll()
    }

    // MARK: - 内部实现

    /// 安装 Carbon 事件处理器，仅订阅 `kEventHotKeyPressed`
    ///
    /// C 回调不能捕获 Swift 上下文，因此将 `self` 通过 `Unmanaged` 以 `void*`
    /// 形式透传；回调中再恢复为 `HotkeyRegistrar` 并查表派发到具体 callback。
    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // C handler：签名必须匹配 EventHandlerUPP；不捕获任何 Swift 变量
        let callback: EventHandlerUPP = { _, event, userData in
            // 事件与 userData 任一缺失都直接返回 noErr，避免崩溃
            guard let event, let userData else { return noErr }

            // 通过 Unmanaged 恢复出注册器实例（未持有强引用，依赖外部管理生命周期）
            let registrar = Unmanaged<HotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()

            // 从事件参数中抽取 HotKeyID，用它在 callbackByID 中定位回调
            var hotkeyID = EventHotKeyID()
            let paramStatus = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            guard paramStatus == noErr else { return noErr }

            // 读到回调后派发到主线程；即便 Carbon 本就在主线程，这里 `async` 也能
            // 解耦 callback 内耗时操作与事件分发链路，避免阻塞后续事件
            if let cb = registrar.callbackByID[hotkeyID.id] {
                DispatchQueue.main.async { cb() }
            }
            return noErr
        }

        // 真正安装 handler；`Unmanaged.passUnretained(self)` 不增加引用计数
        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    /// 将字符串左 4 字节拼成一个 `OSType`（FourCharCode），用于 HotKey signature
    ///
    /// 不足 4 字节会在高位补 0；Carbon 只用它做来源标签，不参与匹配，可接受。
    private func fourCharCode(_ s: String) -> OSType {
        s.utf8.prefix(4).reduce(OSType(0)) { acc, byte in
            (acc << 8) + OSType(byte)
        }
    }
}
