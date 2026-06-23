import ApplicationServices
import AVFoundation
import AppKit
import SwiftUI

/// 权限与麦克风自检窗口：一眼看清麦克风/辅助功能授权，并用实时电平条确认麦克风真的在拾音。
/// 视觉对齐 Figma（744:436）：无原生标题栏，内容自带标题 + 关闭 ✕，扁平的「左标签右取值」列表。
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "权限与麦克风自检"
            w.isReleasedWhenClosed = false
            // 隐藏原生标题栏与红绿灯，改由内容里的自定义标题 + ✕（对齐设计稿的干净面板）
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.standardWindowButton(.closeButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.contentView = NSHostingView(
                rootView: DiagnosticsView(onClose: { [weak self] in self?.window?.close() })
            )
            window = w
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct DiagnosticsView: View {
    var onClose: () -> Void = {}

    @StateObject private var monitor = MicMonitor()
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axTrusted = AXIsProcessTrusted()
    /// 定时复检权限（用户可能在系统设置里授权后切回来）
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题（设计稿 y=32：顶部内距 24 + 8）
            Text("权限与麦克风自检")
                .font(.system(size: GaltDesign.FontSize.title, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, GaltDesign.Spacing.xl)

            // 麦克风（仅小节标题下有分隔线）
            headerRow("麦克风", trailing: micStatusText)
            rowDivider
            valueRow("录音权限") { micActionTrailing }
            valueRow("输入电平") {
                SegmentedLevelMeter(level: monitor.level, active: monitor.running)
            }

            Spacer().frame(height: GaltDesign.Spacing.xl)

            // 辅助功能（自动出字所需）
            headerRow("辅助功能")
            rowDivider
            valueRow("辅助功能权限") {
                Text(axTrusted ? "已授权" : "未授权，无法自动粘贴")
                    .font(.system(size: GaltDesign.FontSize.caption))
                    .foregroundStyle(axTrusted ? Palette.success : Palette.textSecondary)
            }
            HStack(spacing: GaltDesign.Spacing.sm) {
                outlineButton("打开系统设置–辅助功能") { openSettings("Privacy_Accessibility") }
                dangerOutlineButton("重置授权") { resetAccessibility() }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)

            Spacer(minLength: GaltDesign.Spacing.xl)

            // 刷新：整行深色主按钮
            Button(action: refresh) {
                Text("刷新")
                    .font(.system(size: GaltDesign.FontSize.body, weight: .medium))
                    .foregroundStyle(Palette.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(FilledButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surfaceCard)
        // 关闭 ✕：右上角，设计稿 (x=468, y=24)——略高于标题
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconButtonStyle())
            .help("关闭")
            .padding(.top, 24)
            .padding(.trailing, 28)
        }
        // fullSizeContentView 会把内容下移到透明标题栏的安全区之下，留出一截空白；
        // 忽略顶部安全区，让内容与右上角 ✕ 一起顶到窗口真实顶边（间距各自由 padding 决定）。
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { monitor.start(); refresh() }
        .onDisappear { monitor.stop() }
        .onReceive(ticker) { _ in refresh() }
    }

    // MARK: 行骨架

    /// 小节标题行：粗体标签 + 右侧可选状态文案
    private func headerRow(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: GaltDesign.FontSize.body, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: GaltDesign.FontSize.caption))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(height: 36)
    }

    /// 取值行：左标签 + 右侧任意控件
    private func valueRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(.system(size: GaltDesign.FontSize.body))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            trailing()
        }
        .frame(height: 56)
    }

    private var rowDivider: some View {
        Rectangle().fill(Palette.borderSubtle).frame(height: 1)
    }

    // MARK: 麦克风右侧控件

    @ViewBuilder
    private var micActionTrailing: some View {
        switch micStatus {
        case .notDetermined:
            filledButton("请求麦克风权限") {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { refresh(); monitor.stop(); monitor.start() }
                }
            }
        case .authorized:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
        default:
            outlineButton("打开系统设置–麦克风") { openSettings("Privacy_Microphone") }
        }
    }

    private var micStatusText: String {
        switch micStatus {
        case .authorized: return "已授权"
        case .denied: return "已拒绝，需在系统设置中开启"
        case .notDetermined: return "尚未授权"
        case .restricted: return "受限（可能由描述文件管控）"
        @unknown default: return "未知"
        }
    }

    // MARK: 按钮复用

    /// 深色主按钮（小尺寸）
    private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.onPrimary)
                .padding(.horizontal, GaltDesign.Spacing.md)
                .frame(height: 30)
        }
        .buttonStyle(FilledButtonStyle())
    }

    /// 描边次按钮
    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, GaltDesign.Spacing.md)
                .frame(height: 28)
        }
        .buttonStyle(OutlineButtonStyle())
    }

    /// 危险描边按钮（红框红字）——重置授权
    private func dangerOutlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.danger)
                .padding(.horizontal, GaltDesign.Spacing.md)
                .frame(height: 28)
        }
        .buttonStyle(OutlineButtonStyle(border: Palette.danger))
        .help("清除系统对 Galt 的辅助功能授权记录；重打包换签名后授权错乱时用")
    }

    // MARK: 逻辑

    private func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        axTrusted = AXIsProcessTrusted()
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// tccutil 清除本应用的辅助功能授权（ad-hoc 重打包后授权失配时的修复入口）。
    ///
    /// 注意：授权状态对**正在运行的进程**不会即时刷新——`tccutil reset` 清掉记录后，
    /// 当前进程的 `AXIsProcessTrusted()` 仍维持旧值，必须重启 App 才生效。
    /// 所以这里同步执行并给出反馈，成功后引导用户重启。
    private func resetAccessibility() {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            alert(title: "无法重置", info: "未能读取 App 的 Bundle 标识——可能是以未打包的开发版运行。请使用打包后的 Galt.app。")
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleId]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            alert(title: "重置失败", info: "无法执行 tccutil：\(error.localizedDescription)")
            return
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else {
            alert(title: "重置失败", info: output.isEmpty ? "tccutil 返回错误码 \(task.terminationStatus)。" : output)
            return
        }
        promptRelaunch()
    }

    /// 重置成功后：告知需重启才生效，并提供「立即重启」。
    private func promptRelaunch() {
        let a = NSAlert()
        a.messageText = "已清除辅助功能授权记录"
        a.informativeText = "需要重启 Galt 才能生效。重启后请在「系统设置 → 隐私与安全性 → 辅助功能」里重新勾选 Galt。"
        a.addButton(withTitle: "立即重启")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn {
            relaunchApp()
        }
    }

    /// 退出当前进程并拉起新实例（用 shell 等当前进程退出后再 open，避免竞态）。
    private func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func alert(title: String, info: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.addButton(withTitle: "好")
        a.runModal()
    }
}

/// 分段电平条：一排细竖条，随 RMS 自左向右点亮（对齐 Figma 的等化器样式）。
private struct SegmentedLevelMeter: View {
    var level: Float
    var active: Bool

    private static let count = 19   // 对齐设计稿：19 根 6px 宽、4px 间隔，共 186px

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(for: i))
                    .frame(width: 6, height: 16)
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }

    /// 归一电平（与旧 LevelMeter 一致，×6 放大语音小振幅），决定点亮到第几条
    private func color(for index: Int) -> Color {
        guard active else { return Palette.track }
        let filled = Int((min(level * 6, 1)) * Float(Self.count))
        return index < filled ? Palette.success : Palette.track
    }
}
