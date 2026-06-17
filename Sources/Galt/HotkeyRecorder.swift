import AppKit
import SwiftUI

/// 快捷键录制器（对标系统设置→键盘的录制控件）：
/// 点按进入录制态，按下任一受支持的修饰键即完成绑定；Esc 取消、Delete 清除。
/// 仅接受修饰键 / fn —— 普通字符键按住会向目标应用输入文本，不适用于「按住说话」。
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyRaw: String
    var allowNone: Bool
    /// VoiceOver 朗读出的功能名，例如「语音输入快捷键」。每个录制框必须传入，否则会读默认占位。
    var accessibilityLabel: String = "快捷键"
    var reservedRawValues: Set<String> = []
    var takenRawValues: Set<String> = []

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.allowNone = allowNone
        view.accessibilityLabelText = accessibilityLabel
        view.reservedRawValues = reservedRawValues
        view.takenRawValues = takenRawValues
        view.current = HotkeyCombo(rawValue: keyRaw)
        view.syncIdleState()
        view.onChange = { combo in
            keyRaw = combo.rawValue
            NotificationCenter.default.post(name: .galtHotkeysChanged, object: nil)
        }
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.allowNone = allowNone
        view.accessibilityLabelText = accessibilityLabel
        view.reservedRawValues = reservedRawValues
        view.takenRawValues = takenRawValues
        if !view.isRecording {
            view.current = HotkeyCombo(rawValue: keyRaw)
            view.syncIdleState()
            view.needsDisplay = true
        }
    }
}

private enum ShortcutRecorderState: Equatable {
    case idle
    case hover
    case recording
    case error(String)
    case completed

    var isCapturing: Bool {
        switch self {
        case .recording, .error:
            return true
        case .idle, .hover, .completed:
            return false
        }
    }

    var errorMessage: String? {
        if case let .error(message) = self { return message }
        return nil
    }
}

final class HotkeyRecorderView: NSView {
    var current = HotkeyCombo(keys: [])
    var allowNone = false
    var accessibilityLabelText: String = "快捷键"
    var reservedRawValues: Set<String> = []
    var takenRawValues: Set<String> = []
    var onChange: ((HotkeyCombo) -> Void)?
    /// 录制中累积按住的键（顺序用于展示）与当前实际按住的 keyCode 集合
    private var capturedKeys: [HotkeyKey] = []
    private var recordingCodes: Set<UInt16> = []
    private var recordingEventMonitor: Any?
    private var valueBeforeRecording = HotkeyCombo(keys: [])
    private var recorderState = ShortcutRecorderState.idle {
        didSet {
            guard recorderState != oldValue else { return }
            needsDisplay = true
            if recorderState.isCapturing != oldValue.isCapturing {
                NotificationCenter.default.post(name: .galtHotkeyRecordingChanged, object: recorderState.isCapturing)
            }
            // 进入/退出录制即时反馈（不做淡入，避免点按后的延迟感）；悬停仍走平滑过渡
            updateChrome(animated: false)
        }
    }
    private(set) var isRecording: Bool {
        get { recorderState.isCapturing }
        set { recorderState = newValue ? .recording : (current.isEmpty ? .idle : .completed) }
    }
    private var hovering = false {
        didSet {
            guard hovering != oldValue, !recorderState.isCapturing else { return }
            recorderState = hovering ? .hover : (current.isEmpty ? .idle : .completed)
            updateChrome(animated: true)
        }
    }
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    deinit {
        removeRecordingEventMonitor()
        if isRecording {
            NotificationCenter.default.post(name: .galtHotkeyRecordingChanged, object: false)
        }
    }
    /// 窗口不是 key window 时也直接响应第一次点击，避免「首次单击无反应、第二次才进录制」
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 无障碍（VoiceOver）

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { accessibilityLabelText }
    override func accessibilityValue() -> Any? {
        if let message = recorderState.errorMessage { return message }
        return isRecording ? "正在录制，请按住要绑定的快捷键" : current.accessibilityText
    }
    override func accessibilityHelp() -> String? { "点按后按住要绑定的修饰键（可多个组合）；Esc 取消，Delete 清除" }
    override func accessibilityPerformPress() -> Bool {
        beginRecording()
        return true
    }

    override func becomeFirstResponder() -> Bool { true }

    override func resignFirstResponder() -> Bool { true }

    private func beginRecording() {
        window?.makeKey()
        _ = window?.makeFirstResponder(self)
        startRecordingSession()
    }

    private func endRecording() {
        stopRecordingSession()
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    private func startRecordingSession() {
        guard !isRecording else { return }
        valueBeforeRecording = current
        capturedKeys = []
        recordingCodes = []
        installRecordingEventMonitor()
        recorderState = .recording
    }

    private func stopRecordingSession() {
        removeRecordingEventMonitor()
        capturedKeys = []
        recordingCodes = []
        recorderState = current.isEmpty ? .idle : .completed
    }

    private func installRecordingEventMonitor() {
        removeRecordingEventMonitor()
        recordingEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, isRecording else { return event }
            switch event.type {
            case .flagsChanged:
                handleFlagsChanged(event)
                return nil
            case .keyDown:
                handleKeyDown(event)
                return nil
            case .leftMouseDown, .rightMouseDown:
                if event.window === window {
                    let point = convert(event.locationInWindow, from: nil)
                    if bounds.contains(point) { return event }
                }
                endRecording()
                return event
            default:
                return event
            }
        }
    }

    private func removeRecordingEventMonitor() {
        if let recordingEventMonitor {
            NSEvent.removeMonitor(recordingEventMonitor)
            self.recordingEventMonitor = nil
        }
    }

    // MARK: 图层承载的录制框（边框/底色可平滑过渡，悬停有反馈）

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 10
        toolTip = current.isEmpty ? "绑定快捷键" : "更改快捷键"
        updateChrome(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // 动态色的 cgColor 不会自动随外观刷新，需重设
        updateChrome(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    /// 更新录制框边框/底色，可带 0.15s 过渡（尊重「减弱动态效果」）
    private func updateChrome(animated: Bool) {
        guard let layer else { return }
        let border: NSColor
        if recorderState.errorMessage != nil {
            border = danger
        } else if isRecording {
            border = primary
        } else {
            border = hovering ? hoverBorder : fieldBorder
        }
        let bg = (hovering && !isRecording) ? hoverBg : fieldBg
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || reduceMotion)
        CATransaction.setAnimationDuration(0.15)
        layer.borderWidth = (isRecording || recorderState.errorMessage != nil) ? 2 : 1
        // 动态色的 cgColor 必须在视图外观上下文中解析，否则会取错亮/暗
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.borderColor = border.cgColor
            layer.backgroundColor = bg.cgColor
        }
        CATransaction.commit()
    }

    /// × 清除按钮命中区（右侧 24×24）
    private var clearButtonRect: NSRect {
        NSRect(x: bounds.width - 6 - 24, y: (bounds.height - 24) / 2, width: 24, height: 24)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            endRecording()
            return
        }
        // 点击右侧 × 清除当前绑定
        if allowNone, !current.isEmpty {
            let point = convert(event.locationInWindow, from: nil)
            if clearButtonRect.contains(point) {
                current = HotkeyCombo(keys: [])
                onChange?(current)
                syncIdleState()
                needsDisplay = true
                return
            }
        }
        beginRecording()
    }

    /// 录制：按下叠加显示，松开「全部」键时一次性提交累积组合。
    /// 录制过程中实时校验冲突（红字 + beep），但不会收起，允许继续叠加或松开重试。
    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        handleFlagsChanged(event)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let key = HotkeyKey.from(keyCode: event.keyCode) else { return }
        if recordingCodes.contains(event.keyCode) {
            // 松开：仍有键按住 → 继续等；全部松开 → 用累积的组合提交
            recordingCodes.remove(event.keyCode)
            guard recordingCodes.isEmpty else { return }
            if capturedKeys.isEmpty {
                endRecording()
            } else {
                commitIfValid(HotkeyCombo(keys: capturedKeys))
            }
        } else {
            // 按下：上一轮失败后再次开始 → 清空累积
            if recorderState.errorMessage != nil, recordingCodes.isEmpty {
                capturedKeys = []
            }
            recordingCodes.insert(event.keyCode)
            if !capturedKeys.contains(key) { capturedKeys.append(key) }
            // 实时校验：冲突显示红字（不收起），有效则恢复 .recording
            let combo = HotkeyCombo(keys: capturedKeys)
            if let message = validationMessage(for: combo) {
                recorderState = .error(message)
                NSSound.beep()
            } else {
                recorderState = .recording
            }
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        handleKeyDown(event)
    }

    private func handleKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc 取消
            current = valueBeforeRecording
            endRecording()
        case 51, 117: // Delete / Forward-Delete 清除
            if allowNone {
                current = HotkeyCombo(keys: [])
                onChange?(current)
            }
            endRecording()
        default:
            recorderState = .error("仅支持修饰键（含 fn）的组合")
            NSSound.beep()
        }
    }

    private func commitIfValid(_ combo: HotkeyCombo) {
        if let message = validationMessage(for: combo) {
            recorderState = .error(message)
            NSSound.beep()
            return
        }
        current = combo
        toolTip = "更改快捷键"
        onChange?(current)
        needsDisplay = true
        endRecording()
    }

    private func validationMessage(for combo: HotkeyCombo) -> String? {
        if combo.isEmpty, !allowNone { return "请为此功能设置一个快捷键" }
        let canonicalRaw = combo.canonicalRawValue
        if reservedRawValues.contains(where: { combo.matches(rawValue: $0) }) {
            return "此组合已被系统保留"
        }
        if takenRawValues.contains(where: { combo.matches(rawValue: $0) }) {
            return "此组合已被其他功能占用"
        }
        if canonicalRaw == "none" { return nil }
        return nil
    }

    func syncIdleState() {
        guard !recorderState.isCapturing else { return }
        recorderState = hovering ? .hover : (current.isEmpty ? .idle : .completed)
        toolTip = current.isEmpty ? "绑定快捷键" : "更改快捷键"
    }

    // 动态色（适配亮/暗）
    private func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
    // 全部对齐 Design.md v2.0 token；组件内不再出现游离 hex
    private var fieldBg: NSColor { dyn(0xF5F5F5, 0x1E1E1E) }     // surface-panel
    private var fieldBorder: NSColor { dyn(0xE2E2E2, 0x383838) } // border-default
    private var hoverBg: NSColor { dyn(0xFFFFFF, 0x262626) }     // 亮：提到 surface-card；暗：提到 surface-card
    private var hoverBorder: NSColor { dyn(0xCFCFCF, 0x424242) } // neutral-300 / neutral-700（border-default 提一档）
    private var capBg: NSColor { dyn(0xFFFFFF, 0x303030) }       // surface-card / surface-raised
    private var capBorder: NSColor { dyn(0xE2E2E2, 0x383838) }   // border-default
    private var capText: NSColor { dyn(0x212121, 0xF4F4F4) }     // text-primary
    private var primary: NSColor { dyn(0x212121, 0xF4F4F4) }     // primary（录制态边框 / 提示文字）
    private var placeholderText: NSColor { dyn(0x9E9E9E, 0x7A7A7A) } // text-tertiary
    private var danger: NSColor { dyn(0xE5484D, 0xF0595E) }      // danger

    override func draw(_ dirtyRect: NSRect) {
        // 外框（底色/边框）由图层承载并做过渡，这里只画内容
        if let message = recorderState.errorMessage {
            // 高度够（≥56）：占位 + 下方红字；否则单行直接显示错误，避免错误信息被裁掉
            if bounds.height >= 56 {
                drawLeftText("绑定快捷键", color: placeholderText)
                drawErrorText(message)
            } else {
                drawInlineError(message)
            }
            return
        }
        if isRecording {
            // 实时显示已按住的组合；尚未按键时给提示
            if capturedKeys.isEmpty {
                drawLeftText("按住要绑定的快捷键…", color: primary)
            } else {
                drawCaps(capturedKeys.map(\.displayName))
            }
            return
        }
        if current.isEmpty {
            drawLeftText("绑定快捷键", color: placeholderText)
            return
        }
        // 多键帽（左对齐，间距 5）+ hover 时右侧出现「更改快捷键」+ 右端 × 清除
        drawCaps(current.displayCaps)
        if hovering { drawChangeHint() }
        if allowNone { drawClearButton() }
    }

    /// hover 已绑定态：在 × 左侧绘制 "更改快捷键" 次要色提示，避免依赖系统 toolTip（延迟 ~1s）
    private func drawChangeHint() {
        let text = "更改快捷键"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: placeholderText,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        // 右边预留：× 命中区（24+右 padding 6）+ 提示与 × 间距 8；无 × 时只留 8
        let trailingReserved: CGFloat = allowNone ? (6 + 24 + 8) : 8
        let rect = NSRect(
            x: bounds.width - trailingReserved - size.width,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    /// 顺序绘制多个键帽，起始 x=6，键帽间距 5
    private func drawCaps(_ caps: [String]) {
        var x: CGFloat = 6
        for cap in caps {
            x = drawKeyCap(cap, at: x) + 5
        }
    }

    private func drawCenteredText(_ text: String, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func drawLeftText(_ text: String, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: 12, y: (min(bounds.height, 36) - size.height) / 2, width: max(0, bounds.width - 24), height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func drawErrorText(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: danger,
        ]
        let rect = NSRect(x: 2, y: 42, width: bounds.width - 4, height: 16)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    /// 高度不足以容纳两行（占位 + 红字）时，错误信息直接在框内单行显示
    private func drawInlineError(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: danger,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(
            x: 12,
            y: (bounds.height - size.height) / 2,
            width: max(0, bounds.width - 24),
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    /// 键帽：白底描边圆角，高 28，文字 13，左右内边距 6；返回右边缘 x
    @discardableResult
    private func drawKeyCap(_ text: String, at x: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: capText,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let capWidth = max(28, textSize.width + 12)
        let capRect = NSRect(x: x, y: (bounds.height - 28) / 2, width: capWidth, height: 28)
        let capPath = NSBezierPath(roundedRect: capRect, xRadius: 6, yRadius: 6)
        capBg.setFill()
        capPath.fill()
        capBorder.setStroke()
        capPath.lineWidth = 1
        capPath.stroke()
        let textRect = NSRect(
            x: capRect.minX + (capWidth - textSize.width) / 2,
            y: capRect.minY + (28 - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
        return capRect.maxX
    }

    private func drawClearButton() {
        let r = clearButtonRect
        let glyph = "✕"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = (glyph as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height)
        (glyph as NSString).draw(in: rect, withAttributes: attrs)
    }
}
