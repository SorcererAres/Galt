import AppKit
import SwiftUI

/// 「随便问」结果卡片的可观察状态
final class ResultCardState: ObservableObject {
    @Published var text = ""
    @Published var streaming = false
    @Published var failed = false
    /// 卡片标题（如「回答」「翻译」）
    @Published var title = "回答"
}

/// 浮动结果卡片：ask/翻译这类「不一定要落到光标」的结果在此呈现，
/// 流式填字、可复制/插入到光标/关闭。用不抢焦点的 NSPanel，使「插入」能粘回原应用。
final class ResultCardController {
    static let shared = ResultCardController()

    let state = ResultCardState()
    private var panel: NSPanel?
    /// 卡片出现时记录的前台应用，「插入」前先把焦点还回去再粘贴
    private var targetApp: NSRunningApplication?

    private init() {}

    /// 开始一次结果展示：记录目标应用、清空并进入流式态
    func begin(title: String) {
        targetApp = NSWorkspace.shared.frontmostApplication
        state.title = title
        state.text = ""
        state.streaming = true
        state.failed = false
        show()
    }

    func append(_ piece: String) {
        state.text += piece
    }

    /// 流式结束：定格最终文本
    func finish(_ finalText: String) {
        state.text = finalText
        state.streaming = false
    }

    func fail(_ message: String) {
        state.text = message
        state.streaming = false
        state.failed = true
        show()
    }

    func close() {
        panel?.orderOut(nil)
    }

    // MARK: 动作

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(state.text, forType: .string)
    }

    /// 把答案插入回原应用光标处：先激活记录的目标应用，再走剪贴板粘贴
    private func insertIntoTarget() {
        let text = state.text
        close()
        targetApp?.activate(options: [])
        // 等待目标应用拿回焦点再粘贴，避免粘到卡片自身
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            TextInjector.inject(text)
        }
    }

    // MARK: 面板

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ResultCardView(
            state: state,
            onCopy: { [weak self] in self?.copyToPasteboard() },
            onInsert: { [weak self] in self?.insertIntoTarget() },
            onClose: { [weak self] in self?.close() }
        ))
        return panel
    }

    /// 摆到鼠标所在屏幕的中上位置
    private func positionPanel(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.midY + visible.height * 0.12)
        panel.setFrameOrigin(origin)
    }
}

private struct ResultCardView: View {
    @ObservedObject var state: ResultCardState
    var onCopy: () -> Void
    var onInsert: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.md) {
            HStack {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if state.streaming {
                    ProgressView().controlSize(.small)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(state.text.isEmpty ? "…" : state.text)
                    .font(.system(size: 14))
                    .foregroundStyle(state.failed ? Palette.warning : Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)

            if !state.streaming && !state.failed {
                HStack(spacing: GaltDesign.Spacing.sm) {
                    Spacer()
                    Button("复制", action: onCopy)
                    Button("插入到光标", action: onInsert)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(GaltDesign.Spacing.lg)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.borderSubtle, lineWidth: 1)
        )
    }
}
