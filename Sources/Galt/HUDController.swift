import AppKit
import SwiftUI

enum HUDPhase: Equatable {
    case idle
    case recording(locked: Bool, editing: Bool, mode: DictationMode)
    case processing
    case success(String)
    case error(String)
}

final class HUDState: ObservableObject {
    @Published var phase: HUDPhase = .idle {
        didSet {
            // HUD 是视觉状态，盲人用户感知不到——状态变化时向 VoiceOver 播报
            if let message = Self.announcement(for: phase),
               message != Self.announcement(for: oldValue) {
                Self.postAnnouncement(message)
            }
        }
    }
    @Published var level: Float = 0

    /// 各阶段对应的 VoiceOver 播报文案（idle 不播报）
    static func announcement(for phase: HUDPhase) -> String? {
        switch phase {
        case .idle: return nil
        case .recording: return "开始听写"
        case .processing: return "正在转写润色"
        case .success: return "已插入文本"
        case .error(let text): return text
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

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            content
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(HUDMaterial())
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: state.phase)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .recording(let locked, let editing, let mode):
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor(editing: editing, mode: mode))
                    .frame(width: 8, height: 8)
                LevelBars(level: state.level)
                Text(recordingHint(locked: locked, editing: editing, mode: mode))
            }
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
        }
    }

    private func dotColor(editing: Bool, mode: DictationMode) -> Color {
        if editing { return .orange }
        switch mode {
        case .dictation: return .red
        case .translate: return .teal
        case .ask: return .blue
        }
    }

    private func recordingHint(locked: Bool, editing: Bool, mode: DictationMode) -> String {
        if editing {
            return locked ? "语音编辑（锁定）· 点按热键执行" : "语音编辑 · 说出修改指令"
        }
        let base: String
        switch mode {
        case .dictation: base = "正在聆听"
        case .translate: base = "翻译听写"
        case .ask: base = "随便问"
        }
        return locked ? "\(base)（锁定）· 点按热键结束" : "\(base) · 松开热键结束"
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

/// 实时滚动声波：新采样自右侧进入、向左流动，逐条独立平滑衰减，颜色随外观自适应
struct LevelBars: View {
    var level: Float

    private static let count = 24
    @State private var samples = [CGFloat](repeating: 0, count: LevelBars.count)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.count, id: \.self) { i in
                Capsule()
                    .fill(.secondary)
                    // 中心对齐：振幅越大越向上下两侧延展，读作声波而非进度
                    .frame(width: 3, height: 4 + samples[i] * 18)
                    .opacity(0.3 + Double(samples[i]) * 0.7)
            }
        }
        .frame(height: 22)
        .onChange(of: level, perform: advance)
    }

    /// 推入一个新采样，整条缓冲区左移一格
    private func advance(to raw: Float) {
        let normalized = CGFloat(min(max(raw * 22, 0), 1))
        var next = samples
        next.removeFirst()
        next.append(normalized)
        if reduceMotion {
            samples = next
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                samples = next
            }
        }
    }
}
