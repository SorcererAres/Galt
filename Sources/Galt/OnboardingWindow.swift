import AppKit
import SwiftUI

/// 引导专用窗口：独立、固定尺寸、不可缩放 / 最小化的一次性流程窗口。
///
/// 与控制台窗口完全解耦——引导的尺寸、chrome、圆角自成一体，互不牵连。
/// 用普通**不透明**标题栏窗口，四角(含底部)由系统自动圆角，无需手动裁切。
/// 完成后关闭自身并打开控制台概览。
/// 安全区归零的 hosting view：让 SwiftUI 在完整 contentView 内布局，
/// 而不被透明标题栏的安全区挤出底部一条白边。
private final class FullBleedHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
}

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            // 不含 .resizable / .miniaturizable：引导窗口固定尺寸、不可缩放
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: GaltDesign.Onboarding.windowSize),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            w.title = "欢迎使用 Galt"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            // 只保留关闭按钮，隐藏最小化 / 缩放
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            // 用全幅 hosting view（safeAreaInsets 归零）：否则 NSHostingView 会把透明标题栏那段
            // 算作安全区，SwiftUI 只在 contentLayoutRect（≈568pt）里布局，底部露出约一个标题栏的白底。
            w.contentView = FullBleedHostingView(rootView: OnboardingView { [weak self] in
                self?.complete()
            })
            // SwiftUI 内容固定为 480×600。.fullSizeContentView 会把 contentView 铺满**整个窗口 frame**，
            // 而初始化器把 contentRect 当成内容区、又额外加了一个标题栏厚度，导致窗口实际 ≈628pt。
            // 这里直接把整窗 frame 强制设为引导窗尺寸，使 contentView 与内容等高。
            w.setFrame(NSRect(origin: .zero, size: GaltDesign.Onboarding.windowSize), display: false)
            window = w
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 完成引导：落库标记 → 关闭引导窗 → 打开控制台概览
    private func complete() {
        SettingsStore.shared.hasCompletedOnboarding = true
        SettingsStore.shared.onboardingVersion = OnboardingView.currentVersion
        window?.close()
        window = nil
        ConsoleWindowController.shared.show(route: .primary(.overview))
    }
}
