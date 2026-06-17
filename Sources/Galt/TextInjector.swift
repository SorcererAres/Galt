import AppKit
import ApplicationServices

/// 把文本注入当前光标处：写入剪贴板 → 模拟 ⌘V
/// 听写结果始终保留在剪贴板，方便随时手动粘贴
enum TextInjector {
    /// 返回 true 表示已模拟粘贴；false 表示缺少辅助功能权限（文本仍在剪贴板）
    @discardableResult
    static func inject(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            // 无辅助功能授权时保持静默降级：文本留在剪贴板供手动粘贴。
            return false
        }

        synthesizePaste()
        return true
    }

    /// 模拟 ⌘V（需要辅助功能权限）
    private static func synthesizePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
