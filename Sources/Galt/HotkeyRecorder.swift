import AppKit
import SwiftUI

/// 快捷键录制器（对标系统设置→键盘的录制控件）：
/// 点按进入录制态，按下任一受支持的修饰键即完成绑定；Esc 取消、Delete 清除。
/// 仅接受修饰键 / fn —— 普通字符键按住会向目标应用输入文本，不适用于「按住说话」。
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyRaw: String
    var allowNone: Bool

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.allowNone = allowNone
        view.current = HotkeyCombo(rawValue: keyRaw)
        view.onChange = { combo in
            keyRaw = combo.rawValue
            NotificationCenter.default.post(name: .galtHotkeysChanged, object: nil)
        }
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.allowNone = allowNone
        if !view.isRecording {
            view.current = HotkeyCombo(rawValue: keyRaw)
            view.needsDisplay = true
        }
    }
}

final class HotkeyRecorderView: NSView {
    var current = HotkeyCombo(keys: [])
    var allowNone = false
    var onChange: ((HotkeyCombo) -> Void)?
    /// 录制中累积按住的键（顺序用于展示）与当前实际按住的 keyCode 集合
    private var capturedKeys: [HotkeyKey] = []
    private var recordingCodes: Set<UInt16> = []
    private(set) var isRecording = false {
        didSet {
            needsDisplay = true
            // 进入/退出录制即时反馈（不做淡入，避免点按后的延迟感）；悬停仍走平滑过渡
            updateChrome(animated: false)
        }
    }
    private var hovering = false {
        didSet { if hovering != oldValue { updateChrome(animated: true) } }
    }
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    // MARK: 无障碍（VoiceOver）

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "听写触发键" }
    override func accessibilityValue() -> Any? {
        isRecording ? "正在录制，请按住要绑定的组合键" : current.accessibilityText
    }
    override func accessibilityHelp() -> String? { "点按后按住要绑定的修饰键（可多个组合）；Esc 取消，Delete 清除" }
    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        return true
    }

    override func becomeFirstResponder() -> Bool {
        capturedKeys = []
        recordingCodes = []
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    // MARK: 图层承载的录制框（边框/底色可平滑过渡，悬停有反馈）

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 8
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
        let border = isRecording ? primary : (hovering ? hoverBorder : fieldBorder)
        let bg = (hovering && !isRecording) ? hoverBg : fieldBg
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || reduceMotion)
        CATransaction.setAnimationDuration(0.15)
        layer.borderWidth = isRecording ? 2 : 1
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
            window?.makeFirstResponder(nil)
            return
        }
        // 点击右侧 × 清除当前绑定
        if allowNone, !current.isEmpty {
            let point = convert(event.locationInWindow, from: nil)
            if clearButtonRect.contains(point) {
                current = HotkeyCombo(keys: [])
                onChange?(current)
                needsDisplay = true
                return
            }
        }
        window?.makeFirstResponder(self)
    }

    /// 录制：按下即实时绑定（无延迟），可继续按住叠加成组合；松开任一键收起录制
    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        guard let key = HotkeyKey.from(keyCode: event.keyCode) else { return }
        if recordingCodes.contains(event.keyCode) {
            // 松开任一键 → 结束录制（绑定已在按下时即时写入）
            recordingCodes.remove(event.keyCode)
            window?.makeFirstResponder(nil)
        } else {
            // 按下 → 加入组合并「即时」提交，立刻可见可用
            recordingCodes.insert(event.keyCode)
            if !capturedKeys.contains(key) { capturedKeys.append(key) }
            current = HotkeyCombo(keys: capturedKeys)
            onChange?(current)
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 53: // Esc 取消
            window?.makeFirstResponder(nil)
        case 51, 117: // Delete / Forward-Delete 清除
            if allowNone {
                current = HotkeyCombo(keys: [])
                onChange?(current)
            }
            window?.makeFirstResponder(nil)
        default:
            NSSound.beep() // 普通键无效
        }
    }

    // 动态色（适配亮/暗）
    private func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
    private var fieldBg: NSColor { dyn(0xF0F0F0, 0x2A2A2A) }     // track
    private var fieldBorder: NSColor { dyn(0xE2E2E2, 0x383838) } // border-default
    private var hoverBg: NSColor { dyn(0xE8E8E8, 0x333333) }     // 悬停略提对比
    private var hoverBorder: NSColor { dyn(0xCFCFCF, 0x4A4A4A) }
    private var capBg: NSColor { dyn(0xFFFFFF, 0x303030) }       // surface-card / raised
    private var capBorder: NSColor { dyn(0xE2E2E2, 0x383838) }
    private var capText: NSColor { dyn(0x212121, 0xF4F4F4) }     // text-primary
    private var primary: NSColor { dyn(0x212121, 0xF4F4F4) } // 录制态高亮：品牌主色（单色，非青绿）

    override func draw(_ dirtyRect: NSRect) {
        // 外框（底色/边框）由图层承载并做过渡，这里只画内容
        if isRecording {
            // 实时显示已按住的组合；尚未按键时给提示
            if capturedKeys.isEmpty {
                drawCenteredText("请按住要绑定的键…", color: primary)
            } else {
                drawCaps(capturedKeys.map(\.displayName))
            }
            return
        }
        if current.isEmpty {
            drawCenteredText("点按录制", color: .secondaryLabelColor)
            return
        }
        // 多键帽（左对齐，间距 5）+ 右侧 × 清除
        drawCaps(current.displayCaps)
        if allowNone { drawClearButton() }
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
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    /// 键帽：白底描边圆角，高 28，文字 13，左右内边距 6；返回右边缘 x
    @discardableResult
    private func drawKeyCap(_ text: String, at x: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
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
