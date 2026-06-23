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
        // 后台预热历史缓存：首次进入概览/历史页即时，不在主线程现读现解析整份历史
        HistoryStore.shared.preload()
        installMainMenu()
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
            OnboardingWindowController.shared.show()
        } else {
            requestPermissions()
        }

        hotkey.onDown = { [weak self] mode in self?.dictation.keyDown(mode) }
        hotkey.onUp = { [weak self] mode in self?.dictation.keyUp(mode) }
        _ = hotkey.start()

        #if DEBUG
        // 开发期：GALT_OPEN_CONSOLE=1 启动即打开控制台，便于实机验收
        if ProcessInfo.processInfo.environment["GALT_OPEN_CONSOLE"] == "1", !needsOnboarding {
            ConsoleWindowController.shared.show()
        }
        #endif
    }

    /// 点击 Dock 图标（仅「在 Dock 中显示」时存在）重新打开应用：Galt 没有常驻主窗口，
    /// 默认行为是「无事发生」。这里接管——已有可见窗口则交还系统（前置/还原），
    /// 否则按启动逻辑打开引导或控制台。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if SettingsStore.shared.hasCompletedOnboarding {
            ConsoleWindowController.shared.show()
        } else {
            OnboardingWindowController.shared.show()
        }
        return true
    }

    /// 装一个最小主菜单。Galt 是 `.accessory` 应用、不显示系统菜单栏，但**标准文本编辑快捷键**
    /// （⌘A/⌘C/⌘V/⌘X/⌘Z）是靠主菜单「编辑」菜单的 key equivalent 派发到第一响应者的——
    /// 不装主菜单，设置页 / 控制台里的 TextField、SecureField 就无法响应这些快捷键。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App 菜单：accessory 下不可见，但保留标准结构（含 ⌘Q）。
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "退出 Galt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 编辑菜单：提供 ⌘Z/⇧⌘Z/⌘X/⌘C/⌘V/⌘A，动作走第一响应者链（nil target）。
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    /// 首次启动引导授权：麦克风。辅助功能是增强项；未授权时热键走 fallback，文本保留在剪贴板。
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { NSLog("Galt: 麦克风权限未授予，无法录音") }
        }
    }
}
