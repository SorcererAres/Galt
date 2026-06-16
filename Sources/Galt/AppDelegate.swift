import AppKit
import AVFoundation
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dictation: DictationController!
    private var statusBar: StatusBarController!
    private let hotkey = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // 开发期离屏 UI 快照与验证（GALT_SNAPSHOT=1）：渲染后退出，不进入常驻流程
        SnapshotRenderer.runIfRequested()
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.environment["GALT_RESET_ONBOARDING"] == "1" {
            SettingsStore.shared.resetOnboarding()
        }
        #endif

        SettingsStore.shared.applyAppearance()
        SettingsStore.shared.applyDockVisibility()
        dictation = DictationController()
        statusBar = StatusBarController()
        dictation.onActiveChange = { [weak self] active in
            self?.statusBar.setRecording(active)
        }
        #if DEBUG
        let skipOnboarding = ProcessInfo.processInfo.environment["GALT_SKIP_ONBOARDING"] == "1"
        let forceOnboarding = !skipOnboarding
            || ProcessInfo.processInfo.environment["GALT_CONSOLE_PAGE"] == "onboarding"
        #else
        let forceOnboarding = false
        #endif
        let needsOnboarding = forceOnboarding || !SettingsStore.shared.hasCompletedOnboarding
        if needsOnboarding {
            ConsoleWindowController.shared.showOnboarding()
        } else {
            requestPermissions()
        }

        hotkey.onDown = { [weak self] mode in self?.dictation.keyDown(mode) }
        hotkey.onUp = { [weak self] mode in self?.dictation.keyUp(mode) }
        hotkey.start()

        #if DEBUG
        // 开发期：GALT_OPEN_CONSOLE=1 启动即打开控制台，便于实机验收
        if ProcessInfo.processInfo.environment["GALT_OPEN_CONSOLE"] == "1", !needsOnboarding {
            ConsoleWindowController.shared.show()
        }
        #endif
    }

    /// 首次启动引导授权：麦克风 + 辅助功能（注入文本与监听全局热键所需）
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { NSLog("Galt: 麦克风权限未授予，无法录音") }
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSLog("Galt: 等待用户在「系统设置 → 隐私与安全性 → 辅助功能」中授权")
        }
    }
}
