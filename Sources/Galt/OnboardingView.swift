import AppKit
import ApplicationServices
import AVFoundation
import Speech
import SwiftUI

struct OnboardingView: View {
    static let currentVersion = 1

    enum Step: Int, CaseIterable {
        case welcome, permissions, preferences
    }

    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var speechStatus = SFSpeechRecognizer.authorizationStatus()
    @AppStorage("dictationHotkey") private var dictationHotkey = "fn"
    @AppStorage("localLocaleId") private var localLocale = "zh-CN"
    @AppStorage("engineMode") private var engineMode = "auto"

    private var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    private var onboardingAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interpolatingSpring(stiffness: 260, damping: 30)
    }

    private var sharedAxisTransition: AnyTransition {
        let insertionOffset: CGFloat = reduceMotion ? 0 : 22
        let removalOffset: CGFloat = reduceMotion ? 0 : -14
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: insertionOffset)),
            removal: .opacity.combined(with: .offset(x: removalOffset))
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ConsoleDesign.contentBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                progressBar
                    .padding(.top, 44)

                header
                    .padding(.top, 58)

                pageTransitionHost
                    .padding(.top, 58)

                Spacer(minLength: 0)

                footerButton
                    .padding(.bottom, 27)
            }
            .padding(.horizontal, 28)
        }
        .frame(width: 480, height: 600)
        .onAppear(perform: refreshPermissionStatus)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(height: 22, alignment: .leading)

                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)
            }
            .id("header-\(step.rawValue)")
            .transition(sharedAxisTransition)
        }
        .frame(width: 424, height: 49, alignment: .topLeading)
        .clipped()
    }

    private var footerButton: some View {
        Button(action: advance) {
            Text(step == .preferences ? "完成" : "继续")
                .font(.system(size: 13, weight: .semibold))
                .id("button-\(step.rawValue)")
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let segmentWidth = proxy.size.width / CGFloat(Step.allCases.count)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ConsoleDesign.subtleFill)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.primary)
                    .frame(width: segmentWidth * CGFloat(step.rawValue + 1))
                    .animation(onboardingAnimation, value: step)
            }
        }
        .frame(width: 424, height: 8)
    }

    private var pageTransitionHost: some View {
        ZStack(alignment: .topLeading) {
            pageContent
                .id(step)
                .transition(sharedAxisTransition)
        }
        .frame(width: 424, height: 216, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 40) {
                stagedRow(0) {
                    infoRow(
                        icon: "keyboard",
                        title: "按住 fn 说话",
                        text: "松开后，Galt 会自动转写、润色，并插入到当前光标位置。"
                    )
                }
                stagedRow(1) {
                    infoRow(
                        icon: "menubar.rectangle",
                        title: "保持在菜单栏",
                        text: "日常使用不需要打开窗口；控制台只用于查看历史、词典和设置。"
                    )
                }
                stagedRow(2) {
                    infoRow(
                        icon: "lock.shield",
                        title: "隐私优先",
                        text: "历史和词典默认保存在本机。云端识别和 AI 润色只在你配置对应厂商后使用。",
                        height: 56
                    )
                }
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 40) {
                stagedRow(0) {
                    permissionRow(
                        icon: "mic",
                        title: "允许麦克风访问",
                        text: "捕获音频以进行转录，仅在听写功能启用时使用。",
                        isGranted: microphoneStatus == .authorized,
                        actionTitle: microphoneActionTitle
                    ) {
                        requestMicrophone()
                    }
                }
                stagedRow(1) {
                    permissionRow(
                        icon: "accessibility",
                        title: "允许辅助功能访问",
                        text: "将文本粘贴到应用中并与系统交互，仅在必要时使用。",
                        isGranted: accessibilityGranted,
                        actionTitle: accessibilityGranted ? "已授权" : "允许"
                    ) {
                        openAccessibilitySettings()
                    }
                }
                stagedRow(2) {
                    permissionRow(
                        icon: "waveform",
                        title: "允许语音识别",
                        text: "用于 Apple 本地离线转写。",
                        isGranted: speechStatus == .authorized,
                        actionTitle: speechActionTitle
                    ) {
                        requestSpeechRecognition()
                    }
                }
            }
        case .preferences:
            VStack(alignment: .leading, spacing: 40) {
                stagedRow(0) {
                    preferenceRow(title: "语音输入快捷键", text: "之后可以在设置中调整。") {
                        compactPicker(selection: $dictationHotkey) {
                            Text("Fn").tag("fn")
                            Text("Right Cmd").tag("rcmd")
                            Text("Right Option").tag("ropt")
                            Text("Control").tag("ctrl")
                        }
                    }
                }
                stagedRow(1) {
                    preferenceRow(title: "听写语言", text: "Apple 本地识别会使用这个语言变体。") {
                        compactPicker(selection: $localLocale) {
                            Text("简体中文").tag("zh-CN")
                            Text("English").tag("en-US")
                            Text("日本語").tag("ja-JP")
                        }
                    }
                }
                stagedRow(2) {
                    preferenceRow(title: "转写模式", text: "自动模式会优先使用云端，失败时回退本地。") {
                        compactPicker(selection: $engineMode) {
                            Text("自动").tag("auto")
                            Text("仅本地").tag("local")
                            Text("仅云端").tag("cloud")
                        }
                    }
                }
            }
        }
    }

    private var headerTitle: String {
        switch step {
        case .welcome: return "欢迎使用 Galt"
        case .permissions: return "设置权限"
        case .preferences: return "设置偏好"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .welcome:
            return "Galt 是常驻菜单栏的语音输入工具，帮你把口述变成可直接发送的文字。"
        case .permissions:
            return "按需授权，未授权的项目也可以稍后在系统设置或 Galt 设置中处理。"
        case .preferences:
            return "先使用推荐默认值即可。完成后你可以随时在设置中修改。"
        }
    }

    private var microphoneActionTitle: String {
        switch microphoneStatus {
        case .authorized: return "已授权"
        case .denied, .restricted: return "允许"
        case .notDetermined: return "允许"
        @unknown default: return "检查"
        }
    }

    private var speechActionTitle: String {
        switch speechStatus {
        case .authorized: return "已授权"
        case .denied, .restricted: return "允许"
        case .notDetermined: return "允许"
        @unknown default: return "检查"
        }
    }

    private func stagedRow<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 10)))
            .animation(onboardingAnimation.delay(reduceMotion ? 0 : Double(index) * 0.035), value: step)
    }

    private func infoRow(icon: String, title: String, text: String, height: CGFloat = 40) -> some View {
        HStack(alignment: .top, spacing: 12) {
            iconTile(icon: icon, isGranted: false)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 16, alignment: .leading)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 424, height: height, alignment: .topLeading)
    }

    private func permissionRow(
        icon: String,
        title: String,
        text: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            iconTile(icon: icon, isGranted: isGranted)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 16, alignment: .leading)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300, alignment: .leading)

            Spacer(minLength: 0)

            Button(actionTitle, action: action)
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .disabled(isGranted)
        }
        .frame(width: 430, height: 40, alignment: .leading)
    }

    private func preferenceRow<Control: View>(
        title: String,
        text: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 16, alignment: .leading)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 288, alignment: .leading)

            Spacer(minLength: 0)
            control()
        }
        .frame(width: 424, height: 40, alignment: .leading)
    }

    private func iconTile(icon: String, isGranted: Bool) -> some View {
        Image(systemName: isGranted ? "checkmark" : icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isGranted ? Palette.success : ConsoleDesign.primaryControl)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ConsoleDesign.subtleFill)
            )
    }

    private func compactPicker<Selection: Hashable, Content: View>(
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Picker("", selection: selection, content: content)
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 112, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ConsoleDesign.subtleFill)
            )
    }

    private func advance() {
        guard let index = Step.allCases.firstIndex(of: step) else { return }
        if step == .preferences {
            onComplete()
            return
        }
        let nextIndex = Step.allCases.index(after: index)
        withAnimation(onboardingAnimation) {
            step = Step.allCases[nextIndex]
        }
        refreshPermissionStatus()
    }

    private func refreshPermissionStatus() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    private func requestMicrophone() {
        if microphoneStatus == .denied || microphoneStatus == .restricted {
            openPrivacySettings()
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                refreshPermissionStatus()
            }
        }
    }

    private func requestSpeechRecognition() {
        if speechStatus == .denied || speechStatus == .restricted {
            openPrivacySettings()
            return
        }
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async {
                refreshPermissionStatus()
            }
        }
    }

    private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacySettings()
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingPrimaryButton(configuration: configuration)
    }

    private struct OnboardingPrimaryButton: View {
        let configuration: ButtonStyle.Configuration

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var fill: Color {
            if !isEnabled { return ConsoleDesign.primaryControl.opacity(0.32) }
            if configuration.isPressed { return ConsoleDesign.primaryControl.opacity(0.86) }
            if isHovered { return ConsoleDesign.primaryControl.opacity(0.94) }
            return ConsoleDesign.primaryControl
        }

        private var textColor: Color {
            isEnabled ? ConsoleDesign.primaryControlText : ConsoleDesign.primaryControlText.opacity(0.65)
        }

        var body: some View {
            configuration.label
                .foregroundStyle(textColor)
                .frame(width: 424, height: 52)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isHovered && isEnabled ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .opacity(isEnabled ? 1 : 0.72)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingSecondaryButton(configuration: configuration)
    }

    private struct OnboardingSecondaryButton: View {
        let configuration: ButtonStyle.Configuration

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var fill: Color {
            if !isEnabled { return ConsoleDesign.subtleFill.opacity(0.65) }
            if configuration.isPressed { return ConsoleDesign.primaryControl.opacity(0.12) }
            if isHovered { return ConsoleDesign.primaryControl.opacity(0.08) }
            return ConsoleDesign.subtleFill
        }

        private var textColor: Color {
            if !isEnabled { return Color.secondary.opacity(0.62) }
            return ConsoleDesign.primaryControl
        }

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .frame(width: 56, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isHovered && isEnabled ? ConsoleDesign.primaryControl.opacity(0.18) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.74)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}
