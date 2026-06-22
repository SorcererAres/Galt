import AppKit
import SwiftUI

/// 「问答」模式的浮动结果卡片：答案不进光标，改流式填进屏幕下方一张卡片，
/// 读完点 ✕ 关闭（或落定一段时间后自动收起）。单例，生命周期由 DictationController 的
/// ask 流程驱动：begin（开卡）→ append*（流式追加）→ finish（落定全文）/ close（中途收起）。
@MainActor
final class ResultCardController {
    static let shared = ResultCardController()

    /// 落定后自动收起的延时（给足阅读时间；中途点 ✕ 可随时关闭）
    private static let autoDismissDelay: TimeInterval = 18

    private let state = ResultCardState()
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    private init() {}

    // MARK: - 对外（DictationController ask 流程）

    /// 开卡：清空内容、设标题、进入流式态并呈现卡片
    func begin(title: String) {
        dismissWork?.cancel()
        state.title = title
        state.body = ""
        state.streaming = true
        if panel == nil { panel = makePanel() }
        showPanel()
    }

    /// 流式追加答案片段
    func append(_ piece: String) {
        state.body += piece
    }

    /// 落定最终全文，结束流式态，安排超时自动收起
    func finish(_ text: String) {
        state.body = text
        state.streaming = false
        scheduleAutoDismiss()
    }

    /// 立即关闭并清空（ask 转写为空、失败、或用户点 ✕ 时）
    func close() {
        dismissWork?.cancel()
        state.streaming = false
        guard let panel else { return }
        panel.orderOut(nil)
    }

    // MARK: - 面板

    private func scheduleAutoDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: work)
    }

    private func showPanel() {
        guard let panel else { return }
        positionPanel()
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        // 卡片需要滚动与点击 ✕/复制，故接收鼠标事件（nonactivating 不抢用户当前 App 焦点）
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ResultCardView(
            state: state,
            onClose: { [weak self] in self?.close() }
        ))
        return panel
    }

    /// 摆到「鼠标所在屏」底部居中，略高于 HUD 胶囊，避免相互遮挡
    private func positionPanel() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 120)
        panel.setFrameOrigin(origin)
    }
}

/// 卡片内容状态
final class ResultCardState: ObservableObject {
    @Published var title: String = ""
    @Published var body: String = ""
    /// 是否仍在流式生成（控制「生成中…」指示）
    @Published var streaming: Bool = false
}

/// 系统材质背景（毛玻璃）
private struct CardMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ResultCardView: View {
    @ObservedObject var state: ResultCardState
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(state.title.isEmpty ? "回答" : state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if state.streaming {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                Spacer()
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制回答")
                .disabled(state.body.isEmpty)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            ScrollView {
                Text(state.body.isEmpty && state.streaming ? "生成中…" : state.body)
                    .font(.system(size: 13))
                    .foregroundStyle(state.body.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(width: 380, height: 280, alignment: .topLeading)
        .background(CardMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func copy() {
        guard !state.body.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.body, forType: .string)
    }
}
