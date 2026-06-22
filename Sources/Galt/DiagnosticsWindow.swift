import ApplicationServices
import AVFoundation
import AppKit
import SwiftUI

/// 权限与麦克风自检窗口：一眼看清麦克风/辅助功能授权，并用实时电平条确认麦克风真的在拾音。
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "权限与麦克风自检"
            w.isReleasedWhenClosed = false
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.contentView = NSHostingView(rootView: DiagnosticsView())
            window = w
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct DiagnosticsView: View {
    @StateObject private var monitor = MicMonitor()
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axTrusted = AXIsProcessTrusted()
    /// 定时复检权限（用户可能在系统设置里授权后切回来）
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.xl) {
            section(title: "麦克风") { micCard }
            section(title: "辅助功能（自动出字所需）") { accessibilityCard }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                outlineButton("刷新") { refresh() }
            }
        }
        .padding(GaltDesign.Spacing.xl)
        .frame(minWidth: 460, minHeight: 440, alignment: .topLeading)
        .background(Palette.surfaceCanvas)
        .onAppear { monitor.start(); refresh() }
        .onDisappear { monitor.stop() }
        .onReceive(ticker) { _ in refresh() }
    }

    // MARK: 分区骨架（页头标题 + 卡片）

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.md) {
            Text(title)
                .font(.system(size: GaltDesign.FontSize.title, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            card { content() }
        }
    }

    /// 卡片容器：白面 + 描边，复刻设置页 modelCard 的内距与圆角。
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.md) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, GaltDesign.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous).fill(Palette.surfaceCard))
        .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
    }

    // MARK: 麦克风

    private var micCard: some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.md) {
            statusRow(title: "录音权限", granted: micStatus == .authorized,
                      detail: micStatusText)
            actionRow
            Divider()

            // 实时电平：对着麦克风说话，绿条跳动＝拾音正常；不动＝静音（设备没开/没电/选错）
            VStack(alignment: .leading, spacing: GaltDesign.Spacing.sm) {
                Text("对着麦克风说话，看下面的条是否跳动：")
                    .font(.system(size: GaltDesign.FontSize.caption)).foregroundStyle(Palette.textSecondary)
                LevelMeter(level: monitor.level)
                Text(monitor.running ? meterHint : "无法启动麦克风采集——多半未授权或无可用输入设备。")
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch micStatus {
        case .notDetermined:
            Button {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { refresh(); monitor.stop(); monitor.start() }
                }
            } label: {
                Text("请求麦克风权限")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.onPrimary)
                    .padding(.horizontal, GaltDesign.Spacing.md)
                    .frame(height: 28)
            }
            .buttonStyle(FilledButtonStyle())
        case .authorized:
            EmptyView()
        default:
            outlineButton("打开系统设置 → 麦克风") { openSettings("Privacy_Microphone") }
        }
    }

    private var micStatusText: String {
        switch micStatus {
        case .authorized: return "已授权"
        case .denied: return "已拒绝——需在系统设置中开启"
        case .notDetermined: return "尚未授权"
        case .restricted: return "受限（可能由描述文件管控）"
        @unknown default: return "未知"
        }
    }

    private var meterHint: String {
        monitor.level > 0.02 ? "✓ 检测到声音" : "未检测到声音（保持安静时正常）"
    }

    // MARK: 辅助功能

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.md) {
            statusRow(title: "辅助功能权限", granted: axTrusted,
                      detail: axTrusted ? "已授权" : "未授权——无法自动粘贴，只能手动 ⌘V")
            HStack(spacing: GaltDesign.Spacing.md) {
                outlineButton("打开系统设置 → 辅助功能") { openSettings("Privacy_Accessibility") }
                // 危险操作：弱化成 danger 文字链接，避免误点
                Button { resetAccessibility() } label: {
                    Text("重置本应用授权")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.danger)
                }
                .buttonStyle(LinkButtonStyle())
                .help("清除系统对 Galt 的辅助功能授权记录；重打包换签名后授权错乱时用")
            }
        }
    }

    // MARK: 复用

    private func statusRow(title: String, granted: Bool, detail: String) -> some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Palette.success : Palette.warning)
            Text(title).font(.system(size: GaltDesign.FontSize.body, weight: .medium))
            Text(detail).font(.system(size: GaltDesign.FontSize.caption)).foregroundStyle(Palette.textSecondary)
        }
    }

    /// 描边次按钮：复刻设置页「下载」钮（高 28 / 横距 md / 12px 文字）。
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

/// 横向电平条：灰底 + 随 RMS 伸缩的绿条
private struct LevelMeter: View {
    var level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(level > 0.02 ? Palette.success : Palette.textSecondary)
                    .frame(width: geo.size.width * CGFloat(min(level * 6, 1)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .frame(height: 12)
    }
}
