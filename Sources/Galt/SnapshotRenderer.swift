#if DEBUG
import AppKit
import SwiftUI

/// 离屏 UI 快照：用真实 NSHostingView 承载视图、置于离屏 NSWindow，再 cacheDisplay 抓取
/// 真实 AppKit 视图树（含 grouped Form、Picker、自定义录制器、毛玻璃材质），
/// 供开发期做 Apple UI 验收，不依赖屏幕录制权限、不读写用户真实数据。
/// 触发：环境变量 GALT_SNAPSHOT=1 启动，渲染后立即退出。
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["GALT_SNAPSHOT"] == "1" else { return }
        let outDir = URL(fileURLWithPath: "/tmp/galt-snapshots")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for scheme in [ColorScheme.light, ColorScheme.dark] {
            let tag = scheme == .dark ? "dark" : "light"
            capture(SettingsView(layout: .tabbed), name: "settings-\(tag)", width: 580, fixedHeight: 600, scheme: scheme, dir: outDir)
            capture(SettingsView(layout: .grouped), name: "settings-all-\(tag)", width: 580, fixedHeight: 600, scheme: scheme, dir: outDir)
            captureLiveWindow(SettingsView(layout: .sidebar, initialSelection: .voiceEngine), name: "settings-voice-engine-\(tag)", size: NSSize(width: 1200, height: 800), scheme: scheme, dir: outDir)
            captureLiveWindow(SettingsView(layout: .sidebar, initialSelection: .modelLibrary), name: "settings-model-library-\(tag)", size: NSSize(width: 1200, height: 800), scheme: scheme, dir: outDir)
            captureLiveWindow(ConsoleView(navigation: ConsoleNavigation()) { _ in }, name: "console-\(tag)", size: NSSize(width: 1200, height: 800), scheme: scheme, dir: outDir)
            capture(OverviewPage(), name: "overview-\(tag)", width: 760, fixedHeight: 600, scheme: scheme, dir: outDir)
            capture(HistoryPage(), name: "history-\(tag)", width: 952, fixedHeight: 600, scheme: scheme, dir: outDir)
            capture(DictionaryPage(), name: "dictionary-\(tag)", width: 952, fixedHeight: 600, scheme: scheme, dir: outDir)
            capture(DictionaryPage(seedTerms: ["AI coding IF", "SwiftUI", "Figma", "whisper.cpp", "Groq", "DashScope", "Keychain", "Galt"]), name: "dictionary-filled-\(tag)", width: 952, fixedHeight: 600, scheme: scheme, dir: outDir)
            capture(hud(.recording(locked: false, editing: false, mode: .dictation), level: 0.05),
                    name: "hud-recording-\(tag)", width: 560, fixedHeight: 80, scheme: scheme, dir: outDir)
            capture(hud(.success("已插入到光标处的成稿文本"), level: 0),
                    name: "hud-success-\(tag)", width: 560, fixedHeight: 80, scheme: scheme, dir: outDir)
            captureWaveformLive(name: "hud-waveform-live-\(tag)", scheme: scheme, dir: outDir)
            captureRecorder(recording: false, name: "recorder-idle-\(tag)", scheme: scheme, dir: outDir)
            captureRecorder(recording: true, name: "recorder-focused-\(tag)", scheme: scheme, dir: outDir)
        }
        runChecks()
        NSLog("Galt: 快照已写入 \(outDir.path)")
        exit(0)
    }

    /// 向真实 HUDState.level 连续灌入变化值，逐帧推进 runloop，
    /// 走真实 onChange→advance→samples 代码路径，证明波形会随电平起伏（而非静态等高）。
    private static func captureWaveformLive(name: String, scheme: ColorScheme, dir: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let bgColor = scheme == .dark ? Color(white: 0.12) : Color(white: 0.96)
        let state = HUDState()
        state.phase = .recording(locked: false, editing: false, mode: .dictation)
        let view = HUDView(state: state).environment(\.colorScheme, scheme).background(bgColor)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.appearance = appearance
        let size = NSSize(width: 560, height: 80)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting

        // 模拟一段真实语音电平（确定性，不依赖随机数）
        for i in 0..<48 {
            let l = 0.012 + 0.05 * abs(sin(Double(i) * 0.55)) + 0.02 * abs(sin(Double(i) * 1.7))
            state.level = Float(l)
            RunLoop.current.run(until: Date().addingTimeInterval(0.016))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2)) // 让 spring 收敛

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// 直接渲染录制器 NSView 的静止态 / 焦点录制态，验证焦点环与提示文案。
    private static func captureRecorder(recording: Bool, name: String, scheme: ColorScheme, dir: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 64))
        container.appearance = appearance
        container.wantsLayer = true
        container.layer?.backgroundColor = (scheme == .dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
        let recorder = HotkeyRecorderView(frame: NSRect(x: 22, y: 18, width: 196, height: 28))
        recorder.allowNone = true
        recorder.current = HotkeyCombo(keys: [.fn, .rightShift])
        container.addSubview(recorder)
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = container
        if recording { window.makeFirstResponder(recorder) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return }
        container.cacheDisplay(in: container.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// 程序化校验：VoiceOver 暴露值 + 快捷键 keyCode 映射往返。结果写入日志。
    private static func runChecks() {
        let r = HotkeyRecorderView(frame: .zero)
        r.current = HotkeyCombo(keys: [.fn])
        NSLog("✓ A11y role=\(r.accessibilityRole()?.rawValue ?? "nil") label=\(r.accessibilityLabel() ?? "nil") value=\(String(describing: r.accessibilityValue())) help=\(r.accessibilityHelp() ?? "nil")")

        var ok = true
        for key in HotkeyKey.allCases {
            let round = HotkeyKey.from(keyCode: key.keyCode)
            let raw = HotkeyKey(rawValue: key.rawValue)
            if round != key || raw != key { ok = false; NSLog("✗ 映射失败：\(key.rawValue)") }
        }
        NSLog(ok ? "✓ 全部 \(HotkeyKey.allCases.count) 个触发键 keyCode↔枚举↔rawValue 往返一致" : "✗ 键映射存在问题")

        // HUD 各阶段的 VoiceOver 播报文案
        let hudCases: [(HUDPhase, String?)] = [
            (.idle, nil),
            (.recording(locked: false, editing: false, mode: .dictation), "开始听写"),
            (.processing, "正在转写润色"),
            (.success("x"), "已插入文本"),
            (.error("网络错误"), "网络错误"),
        ]
        let hudOk = hudCases.allSatisfy { HUDState.announcement(for: $0.0) == $0.1 }
        NSLog(hudOk ? "✓ HUD 全部阶段 VoiceOver 播报文案正确" : "✗ HUD 播报文案有误")
    }

    /// 渲染单个视图：离屏窗口承载 → 等布局 → cacheDisplay 抓位图 → 写 PNG
    private static func capture<V: View>(_ view: V, name: String, width: CGFloat, fixedHeight: CGFloat, scheme: ColorScheme, dir: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.appearance = appearance

        // 先按固定宽度求自然高度，再据此定最终尺寸
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: fixedHeight)
        let fitting = hosting.fittingSize
        let height = max(fixedHeight, min(fitting.height, 2000))
        let size = NSSize(width: width, height: height)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // 让 SwiftUI 完成异步布局与控件实例化
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// 把窗口真正显示在屏幕外并设为 key，逼 NavigationSplitView/List 等需要真实窗口的组件完整渲染。
    private static func captureLiveWindow<V: View>(_ view: V, name: String, size: NSSize, scheme: ColorScheme, dir: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -9000, y: -9000), size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        window.orderFrontRegardless()
        window.makeKey()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    private static func hud(_ phase: HUDPhase, level: Float) -> some View {
        let state = HUDState()
        state.phase = phase
        state.level = level
        return HUDView(state: state).frame(width: 520, height: 64)
    }
}
#endif
