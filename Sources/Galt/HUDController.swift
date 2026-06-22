import AppKit
import SwiftUI

/// 处理态的细分阶段：转写（STT）与润色（LLM）串行，分别给出独立文案，
/// 让用户在长录音时清楚卡在哪一步，而非笼统的「处理中」。
enum ProcessingStage: Equatable {
    case transcribing
    case polishing
}

enum HUDPhase: Equatable {
    case idle
    /// 麦克风唤醒中：按下到引擎真正开始采集之间的过渡态（仅在启动较慢时经防抖后呈现）
    case starting(mode: DictationMode)
    case recording(locked: Bool, editing: Bool, mode: DictationMode)
    case processing(ProcessingStage)
    case success(String)
    case error(String)
    /// 可重试的失败（转写/润色出错）——保留本次音频，HUD 提供「重试」按钮
    case failure(String)
    /// 录音过短或未捕获到语音——非错误，仅做一次轻量提示后淡出
    case empty
    /// 中性轻量提示（如「已学习某词」），无按钮，短暂展示后淡出
    case info(String)
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
    /// 处理态进度，0...1。由 DictationController 用预测进度驱动，阶段完成时补满。
    @Published var processingProgress: CGFloat = 0

    /// 录音剩余秒数；临近时长上限时由 RecordingPill 呈现 mm:ss 倒计时，nil 表示不显示
    @Published var remainingSeconds: Int?

    /// 新手教学提示（如「按住说话…」）；非 nil 时在录音胶囊下方短暂呈现，nil 表示不显示
    @Published var recordingHint: String?

    /// 阶段变化回调（HUDController 用来按需开启鼠标交互；避免引入 Combine）
    var onPhaseChange: ((HUDPhase) -> Void)?

    /// 各阶段对应的 VoiceOver 播报文案（idle 不播报）
    static func announcement(for phase: HUDPhase) -> String? {
        switch phase {
        case .idle: return nil
        case .starting: return "正在唤醒麦克风"
        case .recording: return "开始听写"
        case .processing(.transcribing): return "正在转写"
        case .processing(.polishing): return "正在润色"
        case .success(let text): return Self.displaySuccessText(text)
        case .error(let text): return text
        case .failure(let text): return "\(text)。可点击重试"
        case .empty: return "未捕获到语音"
        case .info(let text): return text
        }
    }

    static func displaySuccessText(_ text: String) -> String {
        text.hasPrefix("已") ? text : "已插入文本"
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
    /// 面板最小高度：宽度按内容自适应，高度则不低于此值。短内容（status 态约 38px）若让面板紧贴，
    /// 会失去原固定 64px 面板的上下安全边距、并贴近屏幕底边显得被切。保留最小高度 + 胶囊居中，
    /// 既补回呼吸空间，也把胶囊抬离屏幕底边。与改造前的面板高度一致。
    private static let minPanelHeight: CGFloat = 64

    let state = HUDState()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<HUDView>?
    private var hideWorkItem: DispatchWorkItem?
    /// 面板当前贴合的内容尺寸，用于避免重复改窗（同尺寸不再动画）
    private var currentContentSize: NSSize = .zero

    /// 用户点击 HUD 上的「确认 ✓」按钮：结束并转写本次听写
    var onStopRequested: (() -> Void)?
    /// 用户点击 HUD 上的「取消 ✕」按钮：丢弃本次录音，不转写
    var onCancelRequested: (() -> Void)?
    /// 用户点击失败态「重试」按钮：用保留的音频重跑
    var onRetryRequested: (() -> Void)?
    /// 用户点击失败态「关闭 ✕」按钮：放弃重试
    var onDismissRequested: (() -> Void)?
    /// 相位变化对外通知（DictationController 据此按需挂载/卸载 ESC 监听）
    var onPhaseChanged: ((HUDPhase) -> Void)?

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init() {
        state.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            self.updateInteractivity(for: phase)
            self.onPhaseChanged?(phase)
            // phase 变化即按新内容贴合面板。fittingSize 在切换后同步即为正确最终值（已无尺寸动画），
            // 同步先量一次让改窗与内容切换同帧；异步再校正一次兜底。
            self.resizeToContent()
            DispatchQueue.main.async { self.resizeToContent() }
        }
    }

    /// 在「锁定听写」「失败态（重试）」时让 HUD 接收鼠标事件——其它阶段点击穿透到下方应用
    private func updateInteractivity(for phase: HUDPhase) {
        guard let panel else { return }
        switch phase {
        case .recording(let locked, _, _) where locked:
            panel.ignoresMouseEvents = false
        case .failure:
            panel.ignoresMouseEvents = false
        default:
            panel.ignoresMouseEvents = true
        }
    }

    /// 取消已排期的自动淡出（失败态等待用户操作期间，重试重新开始时调用）
    func cancelScheduledHide() {
        hideWorkItem?.cancel()
    }

    func show() {
        hideWorkItem?.cancel()
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        // 入场前先按当前内容量好尺寸并居中，让滑入动画用的是正确的目标 frame
        let size = measuredContentSize()
        if size.width > 0, size.height > 0 {
            currentContentSize = size
            positionPanel(size: size)
        }
        // 已在屏上则只更新位置（尺寸由 onPhaseChange → resizeToContent 跟随），避免重复入场动画
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
            // 初始尺寸仅占位，show() 入场播种 + onPhaseChange→resizeToContent 会按内容贴合
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
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
        let hosting = NSHostingView(rootView: HUDView(
            state: state,
            onStop: { [weak self] in self?.onStopRequested?() },
            onCancel: { [weak self] in self?.onCancelRequested?() },
            onRetry: { [weak self] in self?.onRetryRequested?() },
            onDismiss: { [weak self] in self?.onDismissRequested?() }
        ))
        panel.contentView = hosting
        hostingView = hosting
        // 创建时按当前 phase 同步一次交互态，避免首次锁定前回调未触发
        updateInteractivity(for: state.phase)
        return panel
    }

    /// 同步量出当前 SwiftUI 内容的贴合尺寸（强制一次布局，确保 phase 刚切换也拿到新值）。
    /// 宽度按内容自适应；高度夹住最小值（见 minPanelHeight），胶囊由居中 frame 在面板内居中。
    private func measuredContentSize() -> NSSize {
        guard let hostingView else { return currentContentSize }
        hostingView.layoutSubtreeIfNeeded()
        let fit = hostingView.fittingSize
        return NSSize(width: ceil(fit.width), height: max(ceil(fit.height), Self.minPanelHeight))
    }

    /// phase 变化后按内容贴合面板并重新居中（即时定位，不做尺寸动画）
    private func resizeToContent() {
        guard panel != nil else { return }
        let target = measuredContentSize()
        guard target.width > 0, target.height > 0, target != currentContentSize else { return }
        currentContentSize = target
        positionPanel(size: target)
    }

    /// 按给定尺寸把面板摆到「鼠标所在屏」底部居中（borderless 下 frame == content）
    private func positionPanel(size: NSSize) {
        guard let panel else { return }
        // Galt 常驻后台、自身无 key window，NSScreen.main 会指向「含 key window 的屏」，
        // 多屏时会把 HUD 弹到非当前屏。改用鼠标所在屏，贴合用户正在操作的位置。
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 32)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// HUD 浮层统一深色样式（恒为浮层深色控件，不随系统亮暗变化，对齐 Figma 录音胶囊）
private enum HUDStyle {
    static let fill = Color.black
    static let elevatedFill = Color(hex: 0x2A292D)
    static let secondaryText = Color(hex: 0x9A9A9A)
    static let iconText = Color(hex: 0xC8C8C8)
    static let stopRed = Color(hex: 0xFA3532)
    static let shadow = Color.black.opacity(0.25)
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
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        // 面板尺寸由 HUDController 在 phase 变化时用 fittingSize 量定（见 measuredContentSize）。
        // 这里刻意「不」做两件事，都是踩过的坑：
        //   1) 不对 phase 之间做尺寸动画——否则改窗会追着插值中的尺寸跑，真机上表现为切换时窗口飘移；
        //   2) 不用 GeometryReader 上报尺寸——success/error 带 frame(maxWidth:400) 是横向弹性的，
        //      GeometryReader 上报值取决于被提议的窗口宽度，会和「按上报值改窗」构成反馈环、卡在错误尺寸。
        // fittingSize 不依赖被提议宽度，量值稳定且正确。胶囊内部动画（红点、声波）各自独立不受影响。
        // 胶囊 + 其下方的新手教学提示纵向堆叠；hint 仅在录音/唤醒态出现，淡入且不挤占胶囊本身。
        VStack(spacing: 6) {
            phaseView
            if let hint = state.recordingHint, isRecordingLike {
                Text(hint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: state.recordingHint)
        .fixedSize(horizontal: false, vertical: true)
        // 居中兜底：万一面板尺寸比内容大（尺寸更新滞后一帧、或 ceil 取整留缝），让胶囊在面板内
        // 居中而非左上对齐——否则无 maxWidth 的窄状态（processing/empty）会明显偏左。
        // fittingSize 对 maxWidth:.infinity 取的是内容固有尺寸，测量不受影响（已实测验证）。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 录音 / 唤醒态——这两态下方才挂教学提示
    private var isRecordingLike: Bool {
        switch state.phase {
        case .starting, .recording: return true
        default: return false
        }
    }

    /// 录音态使用独立的深色胶囊（对齐 Figma），其余状态走各自的 36pt 深色状态胶囊
    @ViewBuilder
    private var phaseView: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .starting:
            StartingPill()
        case .recording(let locked, let editing, let mode):
            RecordingPill(
                level: state.level,
                locked: locked,
                editing: editing,
                mode: mode,
                remainingSeconds: state.remainingSeconds,
                onStop: onStop,
                onCancel: onCancel
            )
        case .success(let text):
            let displayText = HUDState.displaySuccessText(text)
            MessageCapsule(icon: successIcon(for: displayText), text: displayText)
        case .failure(let message):
            FailureCapsule(message: message, onRetry: onRetry, onDismiss: onDismiss)
        default:
            statusCapsule
        }
    }

    /// 处理 / 错误 / 空结果 / 信息——统一深色状态胶囊
    /// 强制 .dark 环境：ProgressView、.secondary 文字、Palette 语义色在深底自动取浅色值
    @ViewBuilder
    private var statusCapsule: some View {
        switch state.phase {
        case .processing(let stage):
            ProcessingPill(
                text: stage == .transcribing ? "转写中…" : "润色中…",
                progress: state.processingProgress
            )
        case .error(let message):
            MessageCapsule(icon: "exclamationmark.triangle", text: message, iconColor: Palette.warning)
        case .empty:
            MessageCapsule(icon: "mic.slash", text: "未捕获到语音")
        case .info(let message):
            MessageCapsule(icon: "sparkles", text: message)
        default:
            EmptyView()
        }
    }

    private func successIcon(for text: String) -> String {
        switch text {
        case "已复制到剪贴板": return "doc.on.doc"
        case "已取消": return "xmark.square"
        default: return "text.cursor"
        }
    }
}

/// 正在录音的深色胶囊：红点 + 实时声波 + 取消（✕）/ 停止按钮（对齐 Figma 690:594）
private struct RecordingPill: View {
    var level: Float
    var locked: Bool
    var editing: Bool
    var mode: DictationMode
    /// 录音剩余秒数；临近上限（≤ countdownWarnSeconds）才呈现倒计时
    var remainingSeconds: Int?
    var onStop: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            // 红点跟随音量轻微膨胀 + 弱光晕，作为整体「活气」的视觉锚点
            ZStack {
                Circle()
                    .fill(dotColor)
                    .opacity(reduceMotion ? 0 : min(Double(level) * 0.6, 0.55))
                    .frame(width: 18, height: 18)
                    .blur(radius: 3)
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(reduceMotion ? 1.0 : 1.0 + min(CGFloat(level) * 0.5, 0.42))
            }
            .frame(width: 8, height: 8)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.62), value: level)
            LevelBars(level: level, tint: Color(hex: 0xFFFEFD))
            if let countdown {
                Text(countdown)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isCritical ? Palette.warning : Color(hex: 0x9A9A9A))
                    .accessibilityLabel("剩余 \(countdown)")
            }
            PillCircleButton(
                systemName: "xmark",
                background: HUDStyle.elevatedFill,
                foreground: Color(hex: 0xEAEAEA),
                border: nil,
                action: onCancel
            )
            .help("取消听写")
            .accessibilityLabel("取消听写")
            PillStopButton(action: onStop)
            .help("完成听写")
            .accessibilityLabel("完成听写")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .shadow(color: HUDStyle.shadow, radius: 6.8, x: 0, y: 3.4)
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

    /// 剩余时间 mm:ss；仅在临近上限时返回，平时为 nil（不占位）
    private var countdown: String? {
        guard let remaining = remainingSeconds,
              TimeInterval(remaining) <= Tuning.Session.countdownWarnSeconds else { return nil }
        let clamped = max(0, remaining)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// 最后 10 秒转告警色
    private var isCritical: Bool {
        guard let remaining = remainingSeconds else { return false }
        return remaining <= 10
    }
}

/// 唤醒麦克风过渡胶囊（Figma 738:931）
private struct StartingPill: View {
    var body: some View {
        Text("等待麦克风…")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(HUDStyle.secondaryText)
            .padding(.leading, 12)
            .frame(width: 96, height: 36, alignment: .leading)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .shadow(color: HUDStyle.shadow, radius: 6.8, x: 0, y: 3.4)
        .accessibilityElement()
        .accessibilityLabel("正在唤醒麦克风")
    }
}

private struct ProcessingPill: View {
    let text: String
    let progress: CGFloat

    private var clampedProgress: CGFloat {
        min(1, max(0, progress))
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(HUDStyle.secondaryText)
            .padding(.leading, 12)
            .frame(width: 96, height: 36, alignment: .leading)
            .background(alignment: .leading) {
                Rectangle()
                    .fill(HUDStyle.elevatedFill)
                    .frame(width: 96 * clampedProgress, height: 36)
            }
            .background(HUDStyle.fill)
            .clipShape(Capsule())
            .shadow(color: HUDStyle.shadow, radius: 6.8, x: 0, y: 3.4)
            .animation(.linear(duration: 0.08), value: clampedProgress)
    }
}

private struct MessageCapsule: View {
    let icon: String
    let text: String
    var iconColor: Color = HUDStyle.iconText

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(HUDStyle.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .shadow(color: HUDStyle.shadow, radius: 6.8, x: 0, y: 3.4)
        .environment(\.colorScheme, .dark)
    }
}

/// 可重试的失败胶囊：警示文案 + 「重试」+ 「关闭 ✕」（与录音/状态胶囊同底深色）
private struct FailureCapsule: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.warning)
                .frame(width: 24, height: 24)
            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(HUDStyle.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: 280, alignment: .leading)
            Button(action: onRetry) {
                Text("重试")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(HUDStyle.stopRed)
                    .frame(width: 40, height: 24)
                    .background(Color(hex: 0x1D1011))
                    .clipShape(Capsule())
            }
                .buttonStyle(PressableButtonStyle())
                .help("用刚才的录音重试")
                .accessibilityLabel("重试")
            PillCircleButton(
                systemName: "xmark",
                background: Color(hex: 0x2C2C2D),
                foreground: Color(hex: 0xEAEAEA),
                border: nil,
                action: onDismiss
            )
            .help("关闭")
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, GaltDesign.Spacing.sm)
        .frame(height: 36)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .shadow(color: HUDStyle.shadow, radius: 6.8, x: 0, y: 3.4)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
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
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
    }
}

private struct PillStopButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 1)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(HUDStyle.stopRed)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 24, height: 24)
            .opacity(hovering ? 0.82 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
    }
}

/// 实时录音声波：复刻 Typeless floating-bar 的中心扩散模型，并适配 96px 宽 HUD 区域。
/// 24 根柱使用 2px 宽 + 2px gap，总宽 94px，左右各留 1px。
/// 音量先在中心附近触发，再带微随机延迟向两侧扩散，旧柱按 age 衰减回 2px。
struct LevelBars: View {
    var level: Float
    var tint: Color = .secondary

    private enum K {
        static let count = 24
        static let barW: CGFloat = 2
        static let gap: CGFloat = 2
        static let minH: CGFloat = 2
        static let maxH: CGFloat = 18
        static let frameW: CGFloat = 96
        static let frameH: CGFloat = 24
        static let updateInterval: TimeInterval = 0.05
        static let diffusionDelay: TimeInterval = 0.08
        static let triggerThreshold: CGFloat = 0.07
        static let maxTriggerProbability: CGFloat = 0.8
        static let centerOffsetRatio: CGFloat = 0.15
        static let maxCenterOffset: CGFloat = 3
        static let decayBase: CGFloat = 0.65
        static let decayRandom: CGFloat = 0.08
        static let minDecay: CGFloat = 0.12
        static let blending: ClosedRange<CGFloat> = 0.65...0.75
        static let randomDelay: TimeInterval = 0.015
        static let minEffectiveDecay: CGFloat = 0.95
        static let positionFactor: CGFloat = 0.3
    }

    private struct Bar: Equatable {
        var volume: CGFloat = K.minH
        var age: Int = 0
        var recording: Bool = false
    }

    private struct Pulse: Equatable {
        let volume: CGFloat
        let timestamp: TimeInterval
    }

    private struct ScheduledUpdate: Equatable {
        let index: Int
        let volume: CGFloat
        let timestamp: TimeInterval
    }

    @State private var bars = Array(repeating: Bar(), count: K.count)
    @State private var pendingPulses: [Pulse] = []
    @State private var scheduledUpdates: [ScheduledUpdate] = []
    @State private var smoothedVolume: CGFloat = K.minH
    @State private var lastTick: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            barStack(staticBars)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                barStack(bars)
                    .onAppear { resetIfNeeded() }
                    .onChange(of: context.date) { _, date in step(at: date) }
            }
        }
    }

    private var staticBars: [Bar] {
        let raw = max(0, min(1, CGFloat(level)))
        let h = K.minH + (K.maxH - K.minH) * raw
        return Array(repeating: Bar(volume: h, age: 0, recording: raw > 0.04), count: K.count)
    }

    private func barStack(_ source: [Bar]) -> some View {
        HStack(spacing: K.gap) {
            ForEach(0..<K.count, id: \.self) { i in
                let bar = i < source.count ? source[i] : Bar()
                Capsule()
                    .fill(bar.recording ? tint : Color(hex: 0x808080))
                    .frame(width: K.barW, height: max(K.minH, min(K.maxH, bar.volume)))
                    .opacity(bar.recording ? 1 : 0.5)
            }
        }
        .frame(width: K.frameW, height: K.frameH)
    }

    private func resetIfNeeded() {
        guard bars.count != K.count else { return }
        bars = Array(repeating: Bar(), count: K.count)
        pendingPulses.removeAll()
        scheduledUpdates.removeAll()
        smoothedVolume = K.minH
        lastTick = 0
    }

    private func step(at date: Date) {
        let now = date.timeIntervalSinceReferenceDate
        processScheduledUpdates(at: now)
        guard now - lastTick >= K.updateInterval else { return }
        lastTick = now

        let input = shapedLevel()
        let target = K.minH + (K.maxH - K.minH) * input
        smoothedVolume = smoothedVolume * 0.15 + target * 0.85

        if shouldTriggerPulse(input: input) {
            pendingPulses.append(Pulse(volume: jittered(smoothedVolume, range: 0.9...1.1), timestamp: now))
        }
        processPendingPulses(at: now)
        decayBars()
    }

    private func shapedLevel() -> CGFloat {
        let raw = max(0, min(1, CGFloat(level)))
        switch raw {
        case ..<0.03:
            return min(1, 0.12 + raw / 0.03 * 0.18 + CGFloat.random(in: 0...0.03))
        case ..<0.1:
            let t = (raw - 0.03) / 0.07
            return max(0.31, min(0.79, 0.36 + t * 0.42 + CGFloat.random(in: -0.1...0.1)))
        default:
            let t = min(1, (raw - 0.1) / 0.9)
            var boosted = pow(t, 0.25)
            boosted = max(0, min(1, boosted + CGFloat.random(in: -0.25...0.25) * max(0.15, 0.25 * t)))
            if t > 0.4 {
                boosted = min(1, boosted * CGFloat.random(in: 1.2...1.6))
            }
            return max(0.45, min(1, 0.55 + 0.4 * boosted + CGFloat.random(in: -0.1...0.1)))
        }
    }

    private func shouldTriggerPulse(input: CGFloat) -> Bool {
        guard input > K.triggerThreshold else { return false }
        let probability = min(K.maxTriggerProbability, input * 2)
        return CGFloat.random(in: 0...1) < probability
    }

    private func processPendingPulses(at now: TimeInterval) {
        while let pulse = pendingPulses.first, now - pulse.timestamp >= K.diffusionDelay {
            pendingPulses.removeFirst()
            applyPulse(pulse, at: now)
        }
    }

    private func applyPulse(_ pulse: Pulse, at now: TimeInterval) {
        let center = K.count / 2
        let maxOffset = min(CGFloat(K.count) * K.centerOffsetRatio, K.maxCenterOffset)
        let offset = Int((CGFloat.random(in: -0.5...0.5) * maxOffset).rounded(.down))
        let centerIndex = max(0, min(K.count - 1, center + offset))
        bars[centerIndex] = Bar(volume: jittered(pulse.volume, range: 0.95...1.05), age: 0, recording: true)

        let leftDistance = centerIndex
        let rightDistance = K.count - 1 - centerIndex
        let maxDistance = max(leftDistance, rightDistance)
        guard maxDistance > 0 else { return }

        for distance in 1...maxDistance {
            let leftIndex = centerIndex - distance
            let rightIndex = centerIndex + distance
            let leftDecay = max(
                K.minDecay,
                1 - CGFloat(distance) / CGFloat(max(leftDistance, 1)) * (K.decayBase + CGFloat.random(in: 0...K.decayRandom))
            )
            let rightDecay = max(
                K.minDecay,
                1 - CGFloat(distance) / CGFloat(max(rightDistance, 1)) * (K.decayBase + CGFloat.random(in: 0...K.decayRandom))
            )
            let leftVolume = max(K.minH, jittered(pulse.volume * leftDecay, range: 0.9...1.1))
            let rightVolume = max(K.minH, jittered(pulse.volume * rightDecay, range: 0.9...1.1))
            let baseDelay = Double(distance) * K.diffusionDelay * Double(CGFloat.random(in: 0.15...0.2))
            if leftIndex >= 0 {
                scheduledUpdates.append(ScheduledUpdate(
                    index: leftIndex,
                    volume: leftVolume,
                    timestamp: now + baseDelay + Double.random(in: 0...K.randomDelay)
                ))
            }
            if rightIndex < K.count {
                scheduledUpdates.append(ScheduledUpdate(
                    index: rightIndex,
                    volume: rightVolume,
                    timestamp: now + baseDelay + Double.random(in: 0...K.randomDelay)
                ))
            }
        }
    }

    private func processScheduledUpdates(at now: TimeInterval) {
        guard !scheduledUpdates.isEmpty else { return }
        var remaining: [ScheduledUpdate] = []
        for update in scheduledUpdates {
            guard update.timestamp <= now else {
                remaining.append(update)
                continue
            }
            guard bars.indices.contains(update.index) else { continue }
            let blend = CGFloat.random(in: K.blending)
            let current = bars[update.index].volume
            let volume = max(update.volume, current * (1 - blend) + update.volume * blend)
            bars[update.index] = Bar(volume: volume, age: Int.random(in: 0...1), recording: true)
        }
        scheduledUpdates = remaining
    }

    private func decayBars() {
        let center = K.count / 2
        for index in bars.indices where bars[index].recording {
            let ageStep: Int
            let roll = CGFloat.random(in: 0...1)
            if roll > 0.95 {
                ageStep = 0
            } else if roll > 0.7 {
                ageStep = 2
            } else {
                ageStep = 1
            }
            let nextAge = bars[index].age + ageStep
            let maxAge = 50 + Int.random(in: 0..<15)
            let baseDecay = CGFloat.random(in: 0.98...0.995)
            let positionScale = 1 + abs(CGFloat(index - center)) / CGFloat(K.count) * K.positionFactor
            let effectiveDecay = max(K.minEffectiveDecay, baseDecay / positionScale)
            let decayed = bars[index].volume * pow(effectiveDecay, CGFloat(nextAge) / 12)
            let volume = max(K.minH, jittered(decayed, range: 0.95...1.05))
            if nextAge > maxAge || volume <= K.minH + 0.2 {
                bars[index] = Bar()
            } else {
                bars[index] = Bar(volume: volume, age: nextAge, recording: true)
            }
        }
    }

    private func jittered(_ value: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        max(K.minH, min(K.maxH, value * CGFloat.random(in: range)))
    }
}
