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
        case .success: return "已插入文本"
        case .error(let text): return text
        case .failure(let text): return "\(text)。可点击重试"
        case .empty: return "未捕获到语音"
        case .info(let text): return text
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
    /// 用户点击成功态「撤销」按钮：删除刚插入的文本（语音编辑则恢复原文）
    var onUndoRequested: (() -> Void)?
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

    /// 在「锁定听写」「成功态（撤销）」「失败态（重试）」时让 HUD 接收鼠标事件——其它阶段点击穿透到下方应用
    private func updateInteractivity(for phase: HUDPhase) {
        guard let panel else { return }
        switch phase {
        case .recording(let locked, _, _) where locked:
            panel.ignoresMouseEvents = false
        case .success, .failure:
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
            onDismiss: { [weak self] in self?.onDismissRequested?() },
            onUndo: { [weak self] in self?.onUndoRequested?() }
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
    static let fill = Color(hex: 0x1B1B1B)
    static let stroke = Color(hex: 0x2D2D2D)
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
    var onUndo: () -> Void = {}

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

    /// 录音态使用独立的深色胶囊（对齐 Figma），其余态沿用系统材质胶囊
    @ViewBuilder
    private var phaseView: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .starting(let mode):
            StartingPill(mode: mode)
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
            SuccessCapsule(text: text, onUndo: onUndo)
        case .failure(let message):
            FailureCapsule(message: message, onRetry: onRetry, onDismiss: onDismiss)
        default:
            statusCapsule
        }
    }

    /// 处理 / 成功 / 错误 / 空结果——统一深色浮层胶囊（与录音态同底）
    /// 强制 .dark 环境：ProgressView、.secondary 文字、Palette 语义色在深底自动取浅色值
    @ViewBuilder
    private var statusCapsule: some View {
        statusContent
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(HUDStyle.fill)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(HUDStyle.stroke, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state.phase {
        case .processing(let stage):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(stage == .transcribing ? "正在转写…" : "正在润色…").foregroundStyle(.secondary)
            }
        case .error(let message):
            HStack(spacing: GaltDesign.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                Text(message).lineLimit(2).frame(maxWidth: 400)
            }
        case .empty:
            HStack(spacing: GaltDesign.Spacing.sm) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.secondary)
                Text("未捕获到语音").foregroundStyle(.secondary)
            }
        case .info(let message):
            HStack(spacing: GaltDesign.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
                Text(message).lineLimit(2).frame(maxWidth: 400)
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
    /// 录音剩余秒数；临近上限（≤ countdownWarnSeconds）才呈现倒计时
    var remainingSeconds: Int?
    var onStop: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.xxs) {
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
            LevelBars(level: level, tint: Color(hex: 0xEAEAEA))
            if let countdown {
                Text(countdown)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isCritical ? Palette.warning : Color(hex: 0x9A9A9A))
                    .accessibilityLabel("剩余 \(countdown)")
            }
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
        .padding(.horizontal, GaltDesign.Spacing.sm)
        .frame(height: 36)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(HUDStyle.stroke, lineWidth: 1))
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
              TimeInterval(remaining) <= SettingsStore.shared.countdownWarnSeconds else { return nil }
        let clamped = max(0, remaining)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// 最后 10 秒转告警色
    private var isCritical: Bool {
        guard let remaining = remainingSeconds else { return false }
        return remaining <= 10
    }
}

/// 唤醒麦克风过渡胶囊：与录音态同底深色，内部一道左右扫光表示「正在准备」
/// （对齐 Typeless 的 loadingMove）。尊重减弱动态效果时退化为静态三点。
private struct StartingPill: View {
    var mode: DictationMode

    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackWidth: CGFloat = 96

    var body: some View {
        ZStack {
            // 与 LevelBars 等宽的轨道，避免唤醒→录音切换时胶囊宽度跳变
            Capsule()
                .fill(Color(hex: 0x3A3635))
                .frame(width: Self.trackWidth, height: 4)
            if reduceMotion {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(sweepColor).frame(width: 5, height: 5)
                    }
                }
            } else {
                Capsule()
                    .fill(sweepColor)
                    .frame(width: 26, height: 4)
                    .offset(x: animating ? (Self.trackWidth - 26) / 2 : -(Self.trackWidth - 26) / 2)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animating)
            }
        }
        .frame(width: Self.trackWidth, height: 36)
        .padding(.horizontal, GaltDesign.Spacing.sm)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(HUDStyle.stroke, lineWidth: 1))
        .onAppear { animating = true }
        .accessibilityElement()
        .accessibilityLabel("正在唤醒麦克风")
    }

    /// 扫光颜色按模式取色，与录音态红点/青/蓝呼应；默认听写用近白以保证对比
    private var sweepColor: Color {
        switch mode {
        case .dictation: return Color(hex: 0xEAEAEA)
        case .translate: return .teal
        case .ask: return .blue
        }
    }
}

/// 浅底深字的小胶囊文字按钮（失败态「重试」、成功态「撤销」共用）
private struct PillTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1B1B1B))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(hex: 0xEAEAEA))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 成功胶囊：对勾 + 成稿预览 + 「撤销」按钮（短暂可交互，过后自动淡出）
private struct SuccessCapsule: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            SuccessIcon()
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320)
            PillTextButton(title: "撤销", action: onUndo)
                .help("删除刚插入的文本")
                .accessibilityLabel("撤销插入")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(HUDStyle.stroke, lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }
}

/// 可重试的失败胶囊：警示文案 + 「重试」+ 「关闭 ✕」（与录音/状态胶囊同底深色）
private struct FailureCapsule: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: 280)
            PillTextButton(title: "重试", action: onRetry)
                .help("用刚才的录音重试")
                .accessibilityLabel("重试")
            PillCircleButton(
                systemName: "xmark",
                background: Color(hex: 0x3A3635),
                foreground: Color(hex: 0xEAEAEA),
                border: Color(hex: 0x696564),
                action: onDismiss
            )
            .help("关闭")
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(HUDStyle.fill)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(HUDStyle.stroke, lineWidth: 1))
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

/// 实时录音声波：借鉴 Typeless 的「中心扩散」等化器——音量脉冲在中心附近注入，
/// 向两侧逐格荡开并随机老化衰减，配自适应噪声底，读作有机的呼吸波而非左滚动条。
/// 默认尺寸对齐 Figma 录音胶垫（96×36），`tint` 控制条色（深底用浅色）。
struct LevelBars: View {
    var level: Float
    var tint: Color = .secondary

    /// 可调参数集中于此，便于实机调手感
    private enum K {
        static let count = 24                       // 竖条数（宽 96 / (2+2)）
        static let minH: CGFloat = 3                // 最小（静止）高度
        static let maxH: CGFloat = 24               // 满音量高度
        static let frameW: CGFloat = 96
        static let frameH: CGFloat = 36
        // 中心扩散
        static let propagate: CGFloat = 0.45        // 每帧向外传播的混合比例
        static let propDecay: CGFloat = 0.86        // 传播时的衰减
        static let selfDecay: ClosedRange<CGFloat> = 0.90...0.97 // 每条独立随机老化
        static let centerJitter = 2                 // 注入点相对中心的随机偏移
        // 触发 / 响应
        static let trigger: Float = 0.04            // 减底噪后超过此值才注入脉冲
        static let exponent: Float = 0.5            // 响应曲线（抬高小值）
        static let idleShimmer: Float = 0.06        // 静默时偶发微动的概率
        // 自适应噪声底（随环境跟随）
        static let floorFast: Float = 0.06          // 安静时快速下移
        static let floorSlow: Float = 0.002         // 有声时缓慢上移
        static let floorMargin: Float = 0.01
        static let floorMax: Float = 0.35
        static let visualMargin: Float = 0.006
    }

    @State private var vols = [CGFloat](repeating: K.minH, count: K.count)
    @State private var floor: Float = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 时钟每帧驱动一次扩散步进；减弱动态效果时暂停（静态最小条）
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            HStack(spacing: GaltDesign.Spacing.xxxs) {
                ForEach(0..<K.count, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 2, height: vols[i])
                        .opacity(0.4 + Double((vols[i] - K.minH) / (K.maxH - K.minH)) * 0.6)
                }
            }
            .frame(width: K.frameW, height: K.frameH)
            .onChange(of: context.date) { _, _ in step() }
        }
    }

    /// 一帧扩散步进：自适应底噪 → 中心向两侧传播 → 独立老化 → 触发新脉冲
    private func step() {
        // 自适应噪声底：安静时快速跟随、有声时缓慢上移，只显示「超过环境噪声」的部分
        let f: Float = level <= floor + K.floorMargin ? K.floorFast : K.floorSlow
        floor = min(K.floorMax, max(0, floor * (1 - f) + level * f))
        let norm = max(0, level - floor - K.visualMargin)

        let half = K.count / 2
        var next = vols

        // ① 中心向两侧传播：每条吸收靠中心一侧邻居的衰减值，形成由内向外的流动
        for i in 0..<K.count {
            let inner = i < half ? min(i + 1, K.count - 1) : max(i - 1, 0)
            let propagated = vols[inner] * K.propDecay * CGFloat.random(in: 0.9...1.1)
            next[i] = max(K.minH, vols[i] * (1 - K.propagate) + propagated * K.propagate)
        }
        // ② 每条独立随机老化衰减——避免等高死板
        for i in 0..<K.count {
            next[i] = max(K.minH, next[i] * CGFloat.random(in: K.selfDecay))
        }
        // ③ 触发：音量过阈值则按概率在中心附近注入新脉冲；静默时偶发极小微动保持「活气」
        if norm > K.trigger, Float.random(in: 0...1) < min(0.85, norm * 4) {
            let c = clampIndex(half + Int.random(in: -K.centerJitter...K.centerJitter))
            let shaped = pow(min(1, norm), K.exponent)
            let target = K.minH + (K.maxH - K.minH) * CGFloat(shaped) * CGFloat.random(in: 0.9...1.1)
            next[c] = max(next[c], min(K.maxH, target))
        } else if norm <= K.trigger, Float.random(in: 0...1) < K.idleShimmer {
            let c = clampIndex(half + Int.random(in: -1...1))
            next[c] = max(next[c], K.minH + (K.maxH - K.minH) * CGFloat.random(in: 0.05...0.14))
        }

        // 每条高度用 80ms 缓动过渡（对齐 Typeless 的 transition），跳变被磨平
        withAnimation(.easeOut(duration: 0.08)) {
            vols = next
        }
    }

    private func clampIndex(_ i: Int) -> Int {
        min(max(i, 0), K.count - 1)
    }
}
