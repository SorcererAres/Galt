import AppKit

/// 菜单栏常驻入口
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let hintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let statsItem = NSMenuItem(title: "还没有听写记录", action: nil, keyEquivalent: "")
    private let polishItem = NSMenuItem(title: "AI 润色", action: #selector(togglePolish(_:)), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停听写", action: #selector(togglePause(_:)), keyEquivalent: "")
    private var translationMenu: NSMenu?
    private var micMenu: NSMenu?

    /// 当前是否正在录音（图标状态机用：录音 > 暂停 > 空闲）
    private var recordingActive = false

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.menu = buildMenu()
        refreshIcon()
    }

    /// 录音时菜单栏图标转为红色，给出与系统录音指示一致的活动反馈
    func setRecording(_ active: Bool) {
        recordingActive = active
        refreshIcon()
    }

    /// 按状态刷新菜单栏图标：录音=红，暂停=灰，空闲=常态
    private func refreshIcon() {
        guard let button = item.button else { return }
        if recordingActive {
            let image = GaltMark.image(size: 18, color: .systemRed)
            image.accessibilityDescription = "Galt 正在听写"
            button.image = image
        } else if SettingsStore.shared.dictationPaused {
            let image = GaltMark.image(size: 18, color: .tertiaryLabelColor)
            image.accessibilityDescription = "Galt 已暂停"
            button.image = image
        } else {
            let image = GaltMark.image(size: 18)
            image.accessibilityDescription = "Galt"
            button.image = image
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        hintItem.title = Self.hintTitle()
        hintItem.isEnabled = false
        menu.addItem(hintItem)
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let console = NSMenuItem(title: "打开控制台", action: #selector(openConsole), keyEquivalent: "d")
        console.target = self
        menu.addItem(console)

        pauseItem.target = self
        menu.addItem(pauseItem)

        polishItem.target = self
        menu.addItem(polishItem)

        let translationItem = NSMenuItem(title: "翻译模式", action: nil, keyEquivalent: "")
        let translationMenu = NSMenu()
        for (tag, title) in [("off", "关闭"), ("zh-Hans", "译为简体中文"), ("en", "译为英文"), ("ja", "译为日文")] {
            let item = NSMenuItem(title: title, action: #selector(setTranslation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tag
            translationMenu.addItem(item)
        }
        translationItem.submenu = translationMenu
        menu.addItem(translationItem)
        self.translationMenu = translationMenu

        let micItem = NSMenuItem(title: "麦克风", action: nil, keyEquivalent: "")
        let micMenu = NSMenu()
        micItem.submenu = micMenu
        menu.addItem(micItem)
        self.micMenu = micMenu

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let history = NSMenuItem(title: "打开听写历史", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        let diagnostics = NSMenuItem(title: "权限与麦克风自检…", action: #selector(openDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)

        let reonboard = NSMenuItem(title: "重新运行引导…", action: #selector(rerunOnboarding), keyEquivalent: "")
        reonboard.target = self
        menu.addItem(reonboard)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Galt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// 提示行文案：跟随用户绑定的「语音输入」快捷键
    private static func hintTitle() -> String {
        "按住 \(HotkeyCombo.dictationDisplay) 说话 · 未授权可用 ⌃⌥⌘Space"
    }

    /// 每次展开菜单时刷新统计与开关状态
    func menuWillOpen(_ menu: NSMenu) {
        hintItem.title = Self.hintTitle()
        pauseItem.state = SettingsStore.shared.dictationPaused ? .on : .off
        polishItem.state = SettingsStore.shared.polishEnabled ? .on : .off
        let target = SettingsStore.shared.translationTarget
        translationMenu?.items.forEach { item in
            item.state = (item.representedObject as? String == target) ? .on : .off
        }
        rebuildMicMenu()
        let stats = HistoryStore.shared.stats()
        if stats.count == 0 {
            statsItem.title = "还没有听写记录"
        } else {
            var title = "累计 \(stats.count) 次 · \(stats.words) 字 · \(stats.wpm) WPM"
            if stats.savedMinutes > 0 { title += " · 省 \(stats.savedMinutes) 分钟" }
            statsItem.title = title
        }
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        SettingsStore.shared.dictationPaused.toggle()
        sender.state = SettingsStore.shared.dictationPaused ? .on : .off
        refreshIcon()
    }

    @objc private func togglePolish(_ sender: NSMenuItem) {
        SettingsStore.shared.polishEnabled.toggle()
        sender.state = SettingsStore.shared.polishEnabled ? .on : .off
    }

    @objc private func setTranslation(_ sender: NSMenuItem) {
        SettingsStore.shared.translationTarget = (sender.representedObject as? String) ?? "off"
    }

    /// 重建麦克风子菜单：系统默认 + 当前可用输入设备，勾选当前选择（设备可热插拔，故每次展开重建）
    private func rebuildMicMenu() {
        guard let micMenu else { return }
        micMenu.removeAllItems()
        let current = SettingsStore.shared.micDeviceUID

        let auto = NSMenuItem(title: "系统默认", action: #selector(setMicDevice(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = "auto"
        auto.state = current == "auto" ? .on : .off
        micMenu.addItem(auto)

        let devices = AudioDevices.inputDevices()
        if !devices.isEmpty { micMenu.addItem(.separator()) }
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(setMicDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = current == device.uid ? .on : .off
            micMenu.addItem(item)
        }
    }

    @objc private func setMicDevice(_ sender: NSMenuItem) {
        SettingsStore.shared.micDeviceUID = (sender.representedObject as? String) ?? "auto"
    }

    @objc private func openConsole() {
        ConsoleWindowController.shared.show()
    }

    @objc private func openSettings() {
        SettingsRouter.show()
    }

    /// 重新运行引导：重置完成标记并打开引导窗口（Release 下的重跑入口）
    @objc private func rerunOnboarding() {
        SettingsStore.shared.resetOnboarding()
        OnboardingWindowController.shared.show()
    }

    @objc private func openDiagnostics() {
        DiagnosticsWindowController.shared.show()
    }

    @objc private func openHistory() {
        let store = HistoryStore.shared
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: store.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        } else {
            NSWorkspace.shared.open(store.directory)
        }
    }
}
