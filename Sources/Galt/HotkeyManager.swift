import AppKit
import Carbon.HIToolbox

/// 听写触发模式：普通听写 / 翻译听写 / 随便问
enum DictationMode: Hashable {
    case dictation
    case translate
    case ask
}

/// 可绑定的触发键。限定为修饰键 / fn —— 按住说话期间天然不会向目标应用输入字符。
/// rawValue 与历史设置保持兼容（fn / rcmd / ropt / ctrl 沿用旧值）。
enum HotkeyKey: String, CaseIterable, Identifiable {
    case fn
    case leftCommand = "lcmd"
    case rightCommand = "rcmd"
    case leftOption = "lopt"
    case rightOption = "ropt"
    case leftControl = "ctrl"
    case rightControl = "rctrl"
    case rightShift = "rshift"

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .leftCommand: return 55
        case .rightCommand: return 54
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftControl: return 59
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .leftCommand, .rightCommand: return .command
        case .leftOption, .rightOption: return .option
        case .leftControl, .rightControl: return .control
        case .rightShift: return .shift
        }
    }

    var cgFlag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .leftCommand, .rightCommand: return .maskCommand
        case .leftOption, .rightOption: return .maskAlternate
        case .leftControl, .rightControl: return .maskControl
        case .rightShift: return .maskShift
        }
    }

    /// 录制器中展示的键帽文案（符号 + 左右位置）
    var displayName: String {
        switch self {
        case .fn: return "fn"
        case .leftCommand: return "⌘ 左"
        case .rightCommand: return "⌘ 右"
        case .leftOption: return "⌥ 左"
        case .rightOption: return "⌥ 右"
        case .leftControl: return "⌃ 左"
        case .rightControl: return "⌃ 右"
        case .rightShift: return "⇧ 右"
        }
    }

    /// 由 flagsChanged 事件的 keyCode 反查，用于快捷键录制
    static func from(keyCode: UInt16) -> HotkeyKey? {
        allCases.first { $0.keyCode == keyCode }
    }
}

/// 组合触发键：一个或多个修饰键，需「全部按住」才触发（hold-to-talk）。
/// rawValue 以 "+" 连接各键（如 "fn+rshift"）；"none"/空表示未绑定，兼容旧单键值。
struct HotkeyCombo: Equatable {
    /// 录制顺序（仅用于展示）；匹配时按集合比较
    var keys: [HotkeyKey]

    init(keys: [HotkeyKey]) { self.keys = keys }

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard trimmed != "none", !trimmed.isEmpty else { keys = []; return }
        keys = trimmed.split(separator: "+").compactMap { HotkeyKey(rawValue: String($0)) }
    }

    var isEmpty: Bool { keys.isEmpty }
    var keyCodes: Set<UInt16> { Set(keys.map(\.keyCode)) }
    var rawValue: String { isEmpty ? "none" : keys.map(\.rawValue).joined(separator: "+") }
    var canonicalRawValue: String {
        guard !isEmpty else { return "none" }
        let order = Dictionary(uniqueKeysWithValues: HotkeyKey.allCases.enumerated().map { ($1, $0) })
        let sortedKeys = keys.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
        return sortedKeys.map(\.rawValue).joined(separator: "+")
    }
    var displayCaps: [String] { keys.map(\.displayName) }
    var accessibilityText: String { isEmpty ? "未绑定" : keys.map(\.displayName).joined(separator: " + ") }

    func matches(rawValue: String) -> Bool {
        canonicalRawValue == HotkeyCombo(rawValue: rawValue).canonicalRawValue
    }
}

extension Notification.Name {
    /// 快捷键绑定发生变化（设置面板修改后发出）
    static let galtHotkeysChanged = Notification.Name("galtHotkeysChanged")
    /// 快捷键录制控件进入/退出录制态；录制期间全局热键监听让出事件。
    static let galtHotkeyRecordingChanged = Notification.Name("galtHotkeyRecordingChanged")
}

/// 全局热键监听：按下开始、松开结束（hold-to-talk），支持三种模式各绑一个「组合键」。
///
/// 设计要点：
///   1. **真值对账**：不维护边沿翻转，每次评估直接读 `CGEventSource.keyState` 物理按键状态。
///      丢事件 → 下一次事件或看门狗自动自愈，从根上消除「松手了麦克风还在录」的卡键。
///   2. **CGEvent tap 拦截**：在 active 期间吞 `.flagsChanged`，避免按住的修饰键被前台 App /
///      系统副作用响应（如按 fn 弹出 globe 菜单）。tap 创建失败回退 NSEvent 监听。
///   3. **看门狗 5Hz**：仅在 active 时跑，兜底"松开瞬间事件丢失"的极端情况。
///   4. **生命周期 reconcile**：唤醒、前后台切换强制重新对账，杜绝休眠/切换间漏事件。
///   5. **权限校验**：启动 `AXIsProcessTrusted` 校验，运行中检测撤销并回调 `onPermissionLost`。
final class HotkeyManager {
    var onDown: ((DictationMode) -> Void)?
    var onUp: ((DictationMode) -> Void)?
    /// 「辅助功能」授权被撤销时回调（已自动停止监听，上层应引导用户重新授权）
    var onPermissionLost: (() -> Void)?

    private var bindings: [(combo: HotkeyCombo, mode: DictationMode)] = []
    private var activeModes: Set<DictationMode> = []

    // 主路径：CGEvent tap（拦截 .flagsChanged）
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // 回退路径：NSEvent 全局/本地监听（仅观察，不拦截）
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // 无辅助功能授权的稳定路径：Carbon RegisterEventHotKey（组合键，不支持纯修饰键/fn）
    private var carbonHotKeys: [EventHotKeyRef] = []
    private var carbonEventHandler: EventHandlerRef?
    private var carbonFallbackEnabled = false

    // 看门狗 / 生命周期 / 设置变更 observers
    private var watchdog: Timer?
    private var ncObservers: [NSObjectProtocol] = []
    private var wncObservers: [NSObjectProtocol] = []
    private var hotkeyChangeObserver: NSObjectProtocol?
    private var hotkeyRecordingObserver: NSObjectProtocol?
    private var isRecordingHotkey = false
    private let debugLogging = ProcessInfo.processInfo.environment["GALT_HOTKEY_DEBUG"] == "1"
    private var requiresAccessibility = false

    /// 返回 false 表示所有热键监听路径都无法安装；未授权时会自动退到 Carbon + NSEvent fallback。
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil, globalMonitor == nil, carbonHotKeys.isEmpty else { return true } // 幂等
        reload()
        if AXIsProcessTrusted() {
            requiresAccessibility = true
            carbonFallbackEnabled = false
            if !installEventTap() {
                requiresAccessibility = false
                installFallbackMonitors()
            }
        } else {
            requiresAccessibility = false
            carbonFallbackEnabled = true
            installFallbackMonitors()
            installCarbonHotkeys()
        }
        installLifecycleObservers()
        installHotkeyChangeObserver()
        installHotkeyRecordingObserver()
        log("started, ax=\(AXIsProcessTrusted()), tap=\(eventTap != nil), carbon=\(!carbonHotKeys.isEmpty), fallback=\(globalMonitor != nil), bindings=\(bindings.map { "\($0.mode):\($0.combo.rawValue)" })")
        return eventTap != nil || globalMonitor != nil || !carbonHotKeys.isEmpty
    }

    func stop() {
        uninstallEventTap()
        uninstallFallbackMonitors()
        uninstallCarbonHotkeys()
        stopWatchdog()
        uninstallLifecycleObservers()
        if let obs = hotkeyChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            hotkeyChangeObserver = nil
        }
        if let obs = hotkeyRecordingObserver {
            NotificationCenter.default.removeObserver(obs)
            hotkeyRecordingObserver = nil
        }
        isRecordingHotkey = false
        requiresAccessibility = false
        carbonFallbackEnabled = false
        endIfActive()
    }

    /// 从设置重建绑定表；绑定变更后立即对账一次，同步真实按键状态
    func reload() {
        let settings = SettingsStore.shared
        let all: [(HotkeyCombo, DictationMode)] = [
            (HotkeyCombo(rawValue: settings.dictationHotkey), .dictation),
            (HotkeyCombo(rawValue: settings.translateHotkey), .translate),
            (HotkeyCombo(rawValue: settings.askHotkey), .ask),
        ]
        bindings = all.filter { !$0.0.isEmpty }
        endIfActive() // 绑定变更收尾，防止卡 active
        if carbonFallbackEnabled {
            installCarbonHotkeys()
        }
        if !isRecordingHotkey {
            evaluate()    // 立即按真值同步
        }
    }

    // MARK: - 真值对账（核心）

    /// 读物理按键真值，对账 activeModes，触发 onDown/onUp 边沿。
    /// 返回 active 是否非空 —— tap 回调据此决定是否吞事件。
    @discardableResult
    private func evaluate(
        cgFlags: CGEventFlags = CGEventSource.flagsState(.combinedSessionState),
        eventKeyCode: UInt16? = nil
    ) -> Bool {
        if isRecordingHotkey {
            endIfActive()
            return false
        }
        // 检测权限被中途撤销（如用户在「系统设置」里关掉了 Galt 的辅助功能）
        if requiresAccessibility && !AXIsProcessTrusted() {
            log("evaluate detected AX revoked, stopping")
            stopForAccessibilityLoss()
            return false
        }
        for (combo, mode) in bindings where !combo.isEmpty {
            let isHeld = combo.keyCodes.allSatisfy {
                isKeyHeld($0, cgFlags: cgFlags, eventKeyCode: eventKeyCode)
            }
            let wasActive = activeModes.contains(mode)
            if isHeld && !wasActive {
                activeModes.insert(mode)
                log("onDown \(mode) combo=\(combo.rawValue)")
                DispatchQueue.main.async { [weak self] in self?.onDown?(mode) }
            } else if !isHeld && wasActive {
                activeModes.remove(mode)
                log("onUp \(mode) combo=\(combo.rawValue)")
                DispatchQueue.main.async { [weak self] in self?.onUp?(mode) }
            }
        }
        if activeModes.isEmpty {
            stopWatchdog()
        } else {
            startWatchdogIfNeeded()
        }
        return !activeModes.isEmpty
    }

    /// 当前事件优先使用 event.flags，避免 head-insert tap 里全局 keyState 尚未更新导致漏触发。
    /// 非当前事件按虚拟键码读 keyState，以保留左右修饰键区分能力。
    private func isKeyHeld(_ keyCode: UInt16, cgFlags: CGEventFlags, eventKeyCode: UInt16?) -> Bool {
        if keyCode == 63 { // kVK_Function
            return cgFlags.contains(.maskSecondaryFn)
        }
        if eventKeyCode == keyCode, let key = HotkeyKey.from(keyCode: keyCode) {
            return cgFlags.contains(key.cgFlag)
        }
        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }

    private func stopForAccessibilityLoss() {
        uninstallEventTap()
        requiresAccessibility = false
        carbonFallbackEnabled = true
        installFallbackMonitors()
        installCarbonHotkeys()
        DispatchQueue.main.async { [weak self] in self?.onPermissionLost?() }
    }

    private func endIfActive() {
        guard !activeModes.isEmpty else { return }
        let modes = activeModes
        activeModes.removeAll()
        DispatchQueue.main.async { [weak self] in
            for mode in modes { self?.onUp?(mode) }
        }
        stopWatchdog()
    }

    // MARK: - 看门狗（仅 active 时 5Hz 轮询）

    private func startWatchdogIfNeeded() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        // 加入 common modes，使滚动/拖拽期间也能跑
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    // MARK: - 生命周期 reconcile（休眠唤醒 / 前后台切换）

    private func installLifecycleObservers() {
        let nc = NotificationCenter.default
        let wnc = NSWorkspace.shared.notificationCenter
        let reconcile: (Notification) -> Void = { [weak self] _ in self?.evaluate() }
        wncObservers.append(wnc.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reconcile))
        ncObservers.append(nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: reconcile))
        ncObservers.append(nc.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: reconcile))
    }

    private func uninstallLifecycleObservers() {
        let nc = NotificationCenter.default
        let wnc = NSWorkspace.shared.notificationCenter
        for obs in ncObservers { nc.removeObserver(obs) }
        for obs in wncObservers { wnc.removeObserver(obs) }
        ncObservers.removeAll()
        wncObservers.removeAll()
    }

    private func installHotkeyChangeObserver() {
        hotkeyChangeObserver = NotificationCenter.default.addObserver(
            forName: .galtHotkeysChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    private func installHotkeyRecordingObserver() {
        hotkeyRecordingObserver = NotificationCenter.default.addObserver(
            forName: .galtHotkeyRecordingChanged, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            isRecordingHotkey = (notification.object as? Bool) ?? false
            if isRecordingHotkey {
                endIfActive()
            }
        }
    }

    // MARK: - CGEvent tap（拦截 .flagsChanged）

    /// 创建 .flagsChanged 事件 tap 并挂到 main RunLoop；失败返回 false（通常是「辅助功能」未授权）
    private func installEventTap() -> Bool {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleTap(type: type, event: event)
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            log("CGEvent tap create failed, falling back to NSEvent monitors")
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func uninstallEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// tap 回调：用当前 event 的 flags/keyCode 做本次对账，避免全局 keyState 滞后。
    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        if isRecordingHotkey { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        log("tap flagsChanged keyCode=\(keyCode) flags=\(event.flags.rawValue)")
        return evaluate(cgFlags: event.flags, eventKeyCode: keyCode) ? nil : Unmanaged.passUnretained(event)
    }

    // MARK: - 回退：NSEvent 监听（无法拦截，仅观察）

    private func installFallbackMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, !isRecordingHotkey else { return }
            evaluate(
                cgFlags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                eventKeyCode: event.keyCode
            )
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, !isRecordingHotkey else { return event }
            evaluate(
                cgFlags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                eventKeyCode: event.keyCode
            )
            return event // 必须原样返回，否则会吞掉应用内其它地方的修饰键
        }
    }

    private func uninstallFallbackMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    // MARK: - Carbon fallback（无辅助功能授权稳定组合键）

    private struct CarbonFallback {
        let mode: DictationMode
        let keyCode: UInt32
        let modifiers: UInt32
        let id: UInt32
    }

    private var carbonFallbacks: [CarbonFallback] {
        let fallbackModifiers = UInt32(controlKey | optionKey | cmdKey)
        return [
            CarbonFallback(mode: .dictation, keyCode: UInt32(kVK_Space), modifiers: fallbackModifiers, id: 1),
            CarbonFallback(mode: .translate, keyCode: UInt32(kVK_ANSI_T), modifiers: fallbackModifiers, id: 2),
            CarbonFallback(mode: .ask, keyCode: UInt32(kVK_ANSI_A), modifiers: fallbackModifiers, id: 3),
        ]
    }

    private func installCarbonHotkeys() {
        uninstallCarbonHotkeys()
        guard carbonFallbackEnabled else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleCarbonHotkey(event)
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &carbonEventHandler
        )
        guard status == noErr else {
            log("Carbon event handler install failed status=\(status)")
            return
        }

        let enabledModes = Set(bindings.map(\.mode))
        for fallback in carbonFallbacks where enabledModes.contains(fallback.mode) {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x47616c74), id: fallback.id) // "Galt"
            let status = RegisterEventHotKey(
                fallback.keyCode,
                fallback.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                carbonHotKeys.append(hotKeyRef)
                log("Carbon fallback registered mode=\(fallback.mode) id=\(fallback.id)")
            } else {
                log("Carbon fallback register failed mode=\(fallback.mode) status=\(status)")
            }
        }
    }

    private func uninstallCarbonHotkeys() {
        for hotKey in carbonHotKeys {
            UnregisterEventHotKey(hotKey)
        }
        carbonHotKeys.removeAll()
        if let carbonEventHandler {
            RemoveEventHandler(carbonEventHandler)
            self.carbonEventHandler = nil
        }
    }

    private func handleCarbonHotkey(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              let fallback = carbonFallbacks.first(where: { $0.id == hotKeyID.id }) else {
            return noErr
        }
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            log("Carbon onDown \(fallback.mode)")
            DispatchQueue.main.async { [weak self] in self?.onDown?(fallback.mode) }
        case UInt32(kEventHotKeyReleased):
            log("Carbon onUp \(fallback.mode)")
            DispatchQueue.main.async { [weak self] in self?.onUp?(fallback.mode) }
        default:
            break
        }
        return noErr
    }

    private func log(_ message: String) {
        guard debugLogging else { return }
        NSLog("Galt[Hotkey]: \(message)")
    }
}
