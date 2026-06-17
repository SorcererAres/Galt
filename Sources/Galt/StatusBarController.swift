import AppKit

/// 菜单栏常驻入口
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let statsItem = NSMenuItem(title: "还没有听写记录", action: nil, keyEquivalent: "")
    private let polishItem = NSMenuItem(title: "AI 润色", action: #selector(togglePolish(_:)), keyEquivalent: "")
    private var translationMenu: NSMenu?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let idle = GaltMark.image(size: 18)
        idle.accessibilityDescription = "Galt"
        item.button?.image = idle
        item.menu = buildMenu()
    }

    /// 录音时菜单栏图标转为红色，给出与系统录音指示一致的活动反馈
    func setRecording(_ active: Bool) {
        guard let button = item.button else { return }
        if active {
            let image = GaltMark.image(size: 18, color: .systemRed)
            image.accessibilityDescription = "Galt 正在听写"
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

        let hint = NSMenuItem(title: "按住 fn 说话 · 未授权可用 ⌃⌥⌘Space", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let console = NSMenuItem(title: "打开控制台", action: #selector(openConsole), keyEquivalent: "d")
        console.target = self
        menu.addItem(console)

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

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let history = NSMenuItem(title: "打开听写历史", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Galt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// 每次展开菜单时刷新统计与开关状态
    func menuWillOpen(_ menu: NSMenu) {
        polishItem.state = SettingsStore.shared.polishEnabled ? .on : .off
        let target = SettingsStore.shared.translationTarget
        translationMenu?.items.forEach { item in
            item.state = (item.representedObject as? String == target) ? .on : .off
        }
        let stats = HistoryStore.shared.stats()
        if stats.count == 0 {
            statsItem.title = "还没有听写记录"
        } else {
            var title = "累计 \(stats.count) 次 · \(stats.words) 字 · \(stats.wpm) WPM"
            if stats.savedMinutes > 0 { title += " · 省 \(stats.savedMinutes) 分钟" }
            statsItem.title = title
        }
    }

    @objc private func togglePolish(_ sender: NSMenuItem) {
        SettingsStore.shared.polishEnabled.toggle()
        sender.state = SettingsStore.shared.polishEnabled ? .on : .off
    }

    @objc private func setTranslation(_ sender: NSMenuItem) {
        SettingsStore.shared.translationTarget = (sender.representedObject as? String) ?? "off"
    }

    @objc private func openConsole() {
        ConsoleWindowController.shared.show()
    }

    @objc private func openSettings() {
        SettingsRouter.show()
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
