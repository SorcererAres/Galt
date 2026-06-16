import AppKit

/// 听写触发模式：普通听写 / 翻译听写 / 随便问
enum DictationMode: Equatable {
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
    var displayCaps: [String] { keys.map(\.displayName) }
    var accessibilityText: String { isEmpty ? "未绑定" : keys.map(\.displayName).joined(separator: " + ") }
}

extension Notification.Name {
    /// 快捷键绑定发生变化（设置面板修改后发出）
    static let galtHotkeysChanged = Notification.Name("galtHotkeysChanged")
}

/// 全局热键监听：按下开始、松开结束（hold-to-talk），支持三种模式各绑一个「组合键」。
/// 精确按 keyCode 跟踪当前按住的修饰键集合，整组完全匹配某绑定时触发，组合被破坏时结束。
final class HotkeyManager {
    var onDown: ((DictationMode) -> Void)?
    var onUp: ((DictationMode) -> Void)?

    private var bindings: [(combo: HotkeyCombo, mode: DictationMode)] = []
    private var pressedCodes: Set<UInt16> = []
    private var activeModes: Set<DictationMode> = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        reload()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
        NotificationCenter.default.addObserver(
            forName: .galtHotkeysChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    /// 从设置重建绑定表（绑定变更时复位按压/激活态，避免卡在 active）
    func reload() {
        let settings = SettingsStore.shared
        let all: [(HotkeyCombo, DictationMode)] = [
            (HotkeyCombo(rawValue: settings.dictationHotkey), .dictation),
            (HotkeyCombo(rawValue: settings.translateHotkey), .translate),
            (HotkeyCombo(rawValue: settings.askHotkey), .ask),
        ]
        bindings = all.filter { !$0.0.isEmpty }
        pressedCodes.removeAll()
        for mode in activeModes { onUp?(mode) }
        activeModes.removeAll()
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard let key = HotkeyKey.from(keyCode: event.keyCode) else { return }
        // 每个修饰键 down/up 各产生一次 flagsChanged，按 keyCode 翻转按压态（精确区分左右）
        if pressedCodes.contains(event.keyCode) {
            pressedCodes.remove(event.keyCode)
        } else {
            pressedCodes.insert(event.keyCode)
        }
        // 用 modifierFlags 兜底纠偏：对应 flag 已消失的修饰键一律视为松开（防止漏事件卡住）
        _ = key
        pressedCodes = pressedCodes.filter {
            guard let k = HotkeyKey.from(keyCode: $0) else { return false }
            return event.modifierFlags.contains(k.flag)
        }
        updateActive()
    }

    /// 当前按住集合完全等于某绑定组合时进入 active，破坏时退出（begin/end 只在边沿触发）
    private func updateActive() {
        for (combo, mode) in bindings where !combo.isEmpty {
            let isActive = pressedCodes == combo.keyCodes
            let wasActive = activeModes.contains(mode)
            if isActive && !wasActive {
                activeModes.insert(mode)
                onDown?(mode)
            } else if !isActive && wasActive {
                activeModes.remove(mode)
                onUp?(mode)
            }
        }
    }
}
