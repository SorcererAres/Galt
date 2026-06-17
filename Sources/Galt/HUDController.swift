import AppKit
import SwiftUI

enum HUDPhase: Equatable {
    case idle
    case recording(locked: Bool, editing: Bool, mode: DictationMode)
    case processing
    case success(String)
    case error(String)
    /// 录音过短或未捕获到语音——非错误，仅做一次轻量提示后淡出
    case empty
}

final class HUDState: ObservableObject {
    @Published var phase: HUDPhase = .idle {
        didSet {
            // HUD 是视觉状态，盲人用户感知不到——状态变化时向 VoiceOver 播报
            if let message = Self.announcement(for: phase),
               message != Self.announcement(for: oldValue) {
                Self.postAnnouncement(message)
            }
            onPhaseChange?(phase)
        }
    }
    @Published var level: Float = 0

    /// 阶段变化回调（HUDController 用来按需开启鼠标交互；避免引入 Combine）
    var onPhaseChange: ((HUDPhase) -> Void)?

    /// 各阶段对应的 VoiceOver 播报文案（idle 不播报）
    static func announcement(for phase: HUDPhase) -> String? {
        switch phase {
        case .idle: return nil
        case .recording: return "开始听写"
        case .processing: return "正在转写润色"
        case .success: return "已插入文本"
        case .error(let text): return text
        case .empty: return "未捕获到语音"
        }
    }

    static func postAnnouncement(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

/// 屏幕底部居中的悬浮状态胶囊（系统材质，随浅色/深色模式自适应）
final class HUDController {
    let state = HUDState()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    /// 用户点击 HUD 上的「确认 ✓」按钮：结束并转写本次听写
    var onStopRequested: (() -> Void)?
    /// 用户点击 HUD 上的「取消 ✕」按钮：丢弃本次录音，不转写
    var onCancelRequested: (() -> Void)?

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init() {
        state.onPhaseChange = { [weak self] phase in
            self?.updateInteractivity(for: phase)
        }
    }

    /// 仅在「锁定听写」时让 HUD 接收鼠标事件——保证其它阶段点击穿透到下方应用
    private func updateInteractivity(for phase: HUDPhase) {
        guard let panel else { return }
        if case .recording(let locked, _, _) = phase, locked {
            panel.ignoresMouseEvents = false
        } else {
            panel.ignoresMouseEvents = true
        }
    }

    func show() {
        hideWorkItem?.cancel()
        if panel == nil { panel = makePanel() }
        position()
        guard let panel else { return }
        // 已在屏上则只更新位置，避免重复入场动画
        guard !panel.isVisible else { return }

        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        // 淡入 + 自下方 8px 上滑，呼应系统 HUD 的轻量出场
        let target = panel.frame.origin
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - 8))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(target)
        }
    }

    func hide(after delay: TimeInterval = 0) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func dismiss() {
        guard let panel, panel.isVisible else {
            state.phase = .idle
            return
        }
        if reduceMotion {
            panel.orderOut(nil)
            state.phase = .idle
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            self?.state.phase = .idle
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(
            state: state,
            onStop: { [weak self] in self?.onStopRequested?() },
            onCancel: { [weak self] in self?.onCancelRequested?() }
        ))
        // 创建时按当前 phase 同步一次交互态，避免首次锁定前回调未触发
        updateInteractivity(for: state.phase)
        return panel
    }

    private func position() {
        guard let screen = NSScreen.main, let panel else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 32))
    }
}

/// 系统材质背景（毛玻璃，blendingMode 取窗口后方内容）
private struct HUDMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct HUDView: View {
    @ObservedObject var state: HUDState
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            phaseView
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: state.phase)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// 录音态使用独立的深色胶囊（对齐 Figma），其余态沿用系统材质胶囊
    @ViewBuilder
    private var phaseView: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .recording(let locked, let editing, let mode):
            RecordingPill(
                level: state.level,
                locked: locked,
                editing: editing,
                mode: mode,
                onStop: onStop,
                onCancel: onCancel
            )
        default:
            statusCapsule
        }
    }

    /// 处理 / 成功 / 错误 / 空结果——轻量系统材质胶囊
    @ViewBuilder
    private var statusCapsule: some View {
        statusContent
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(HUDMaterial())
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state.phase {
        case .processing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在转写润色…").foregroundStyle(.secondary)
            }
        case .success(let text):
            HStack(spacing: 8) {
                SuccessIcon()
                Text(text).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: 400)
        case .error(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                Text(message).lineLimit(2).frame(maxWidth: 400)
            }
        case .empty:
            HStack(spacing: 8) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.secondary)
                Text("未捕获到语音").foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
}

/// 正在录音的深色胶囊：红点 + 实时声波 + 取消（✕）/ 确认（✓）按钮（对齐 Figma 690:594）
private struct RecordingPill: View {
    var level: Float
    var locked: Bool
    var editing: Bool
    var mode: DictationMode
    var onStop: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Figma 固定深色样式（不随系统亮暗变化，恒为浮层深色控件）
    private static let fill = Color(hex: 0x1B1B1B)
    private static let stroke = Color(hex: 0x2D2D2D)

    var body: some View {
        HStack(spacing: 4) {
            // 红点跟随音量轻微膨胀 + 弱光晕，作为整体「活气」的视觉锚点
            ZStack {
                Circle()
                    .fill(dotColor)
                    .opacity(reduceMotion ? 0 : min(Double(level) * 2.6, 0.55))
                    .frame(width: 18, height: 18)
                    .blur(radius: 3)
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(reduceMotion ? 1.0 : 1.0 + min(CGFloat(level) * 1.3, 0.42))
            }
            .frame(width: 8, height: 8)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.62), value: level)
            LevelBars(level: level, tint: Color(hex: 0xEAEAEA))
            PillCircleButton(
                systemName: "xmark",
                background: Color(hex: 0x3A3635),
                foreground: Color(hex: 0xEAEAEA),
                border: Color(hex: 0x696564),
                action: onCancel
            )
            .help("取消听写")
            .accessibilityLabel("取消听写")
            PillCircleButton(
                systemName: "checkmark",
                background: Color(hex: 0xEAEAEA),
                foreground: Color(hex: 0x1B1B1B),
                border: nil,
                action: onStop
            )
            .help("完成听写")
            .accessibilityLabel("完成听写")
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(Self.fill)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Self.stroke, lineWidth: 1))
        // 非锁定（按住说话）时只读展示：鼠标事件由 HUDController 在锁定时才放行
        .accessibilityElement(children: .contain)
    }

    private var dotColor: Color {
        if editing { return .orange }
        switch mode {
        case .dictation: return Color(hex: 0xFE3032)
        case .translate: return .teal
        case .ask: return .blue
        }
    }
}

/// 录音胶囊内的圆形操作按钮（24pt，对齐 Figma）
private struct PillCircleButton: View {
    let systemName: String
    let background: Color
    let foreground: Color
    let border: Color?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(background)
                if let border {
                    Circle().strokeBorder(border, lineWidth: 0.6)
                }
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(foreground)
            }
            .frame(width: 24, height: 24)
            .opacity(hovering ? 0.82 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 成功对勾：完成瞬间轻量弹入，强化「已出字」的确认感（尊重减弱动态效果）
private struct SuccessIcon: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Palette.success)
            .scaleEffect(shown || reduceMotion ? 1 : 0.5)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.56)) { shown = true }
            }
    }
}

/// 实时滚动声波：新采样自右侧进入、向左流动，逐条独立平滑衰减
/// 默认尺寸对齐 Figma 录音胶垫（96×36），`tint` 控制条色（深底用浅色）
struct LevelBars: View {
    var level: Float
    var tint: Color = .secondary

    private static let count = 24
    @State private var samples = [CGFloat](repeating: 0, count: LevelBars.count)
    @State private var birth = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // TimelineView 每帧重绘：让「呼吸基线」即使没说话也持续微动
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(birth)
            HStack(spacing: 2) {
                ForEach(0..<Self.count, id: \.self) { i in
                    let amp = combinedAmplitude(at: i, time: elapsed)
                    Capsule()
                        .fill(tint)
                        // 中心对齐：振幅越大越向上下两侧延展，读作声波而非进度
                        .frame(width: 2, height: 3 + amp * 20)
                        .opacity(0.4 + Double(amp) * 0.6)
                }
            }
            .frame(width: 96, height: 36)
            .onChange(of: level, perform: advance)
        }
    }

    /// 实采样 + 每条独立相位的低频呼吸基线——静默时仍有微动；说话越大、呼吸越被压制
    private func combinedAmplitude(at index: Int, time: TimeInterval) -> CGFloat {
        let sample = samples[index]
        if reduceMotion { return sample }
        let phase = Double(index) * 0.42        // 24 条覆盖约 1.6 个完整正弦周期，形成横向涟漪
        let breathing = (sin(time * 2.4 + phase) + 1) * 0.5 * 0.18 // 0..0.18，基线天花板
        return max(sample, CGFloat(breathing) * (1 - sample))      // 与实采样取较大，平滑过渡
    }

    /// 推入一个新采样，整条缓冲区左移一格
    /// pow(0.55) 把语音的小振幅大幅抬高，避免「常态平直、偶尔暴顶」的死区
    private func advance(to raw: Float) {
        let scaled: Float = min(max(raw * 1.6, 0), 1)
        let curved = pow(scaled, Float(0.55))
        var next = samples
        next.removeFirst()
        next.append(CGFloat(curved))
        if reduceMotion {
            samples = next
        } else {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.66)) {
                samples = next
            }
        }
    }
}
