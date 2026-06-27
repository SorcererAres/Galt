import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 把文本注入当前光标处：暂存剪贴板 → 写入成稿 → 模拟 ⌘V → 恢复原剪贴板
/// 粘贴只是出字手段，结束后还原用户原本复制的内容，不污染剪贴板。
enum TextInjector {
    /// ⌘V 派发后到系统真正读取剪贴板之间的等待；过早恢复会让粘贴到旧内容
    private static let restoreDelay: TimeInterval = 0.2
    /// 切换输入源后等待系统生效再粘贴；过短会让 ⌘V 仍落在原 IME 上
    private static let inputSourceSettle: TimeInterval = 0.05

    /// 返回 true 表示已模拟粘贴；false 表示缺少辅助功能权限（文本仍在剪贴板供手动 ⌘V）
    @discardableResult
    static func inject(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        guard AXIsProcessTrusted() else {
            // 无辅助功能授权时无法自动粘贴：把文本留在剪贴板供手动 ⌘V（此时不还原，否则用户无从粘贴）。
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return false
        }

        // 暂存原剪贴板（含所有类型），粘贴后还原
        let saved = snapshot()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 中文/日文等非 ASCII 输入法激活时，模拟的 ⌘V 可能被 IME 的待组词状态截获，
        // 导致粘贴失效或粘出半截。临时切到 ASCII 键盘布局（优先 ABC/US），粘贴后再切回。
        if let original = switchToASCIIInputSourceIfNeeded() {
            DispatchQueue.main.asyncAfter(deadline: .now() + inputSourceSettle) {
                synthesizePaste()
                // 先切回输入源，再还原剪贴板；两者都需在粘贴真正读取剪贴板之后
                DispatchQueue.main.asyncAfter(deadline: .now() + inputSourceSettle) {
                    TISSelectInputSource(original)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    restore(saved)
                }
            }
        } else {
            synthesizePaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                restore(saved)
            }
        }
        return true
    }

    /// 抓取当前剪贴板快照：每个 item 的全部类型数据，用于注入后原样还原
    private static func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        NSPasteboard.general.pasteboardItems?.map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let bytes = item.data(forType: type) { data[type] = bytes }
            }
            return data
        } ?? []
    }

    /// 还原剪贴板到快照；空快照表示原本就没有内容，清空即可
    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, bytes) in entry { item.setData(bytes, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// 在当前光标处直接键入文本（不经剪贴板），用于流式润色的增量出字。
    /// 返回 true 表示已键入；false 表示缺少辅助功能权限。
    /// 若此时目标应用有选区，首个字符会自动替换选区——与「语音编辑」的预期一致。
    @discardableResult
    static func typeIncremental(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        guard AXIsProcessTrusted() else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        // keyboardSetUnicodeString 单次建议不超过 ~20 个 UTF-16 单元，超出需分片
        let units = Array(text.utf16)
        let chunkSize = 20
        var index = 0
        while index < units.count {
            var slice = Array(units[index..<min(index + chunkSize, units.count)])
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
            up?.post(tap: .cghidEventTap)
            index += chunkSize
        }
        return true
    }

    /// 删除刚刚直接键入的字符，用于流式输出失败时回滚半成品。
    static func deleteBackward(characterCount: Int) {
        guard characterCount > 0, AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let deleteKey: CGKeyCode = 51
        for _ in 0..<characterCount {
            let down = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - 输入源切换（规避中文/日文 IME 吞掉 ⌘V）

    /// 当前输入源非 ASCII 时，切到 ASCII 键盘布局，并返回原输入源供粘贴后还原。
    /// 已是 ASCII，或找不到可用 ASCII 布局时返回 nil（无需还原）。
    private static func switchToASCIIInputSourceIfNeeded() -> TISInputSource? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              !isASCIICapable(current),
              let ascii = preferredASCIIInputSource() else { return nil }
        TISSelectInputSource(ascii)
        return current
    }

    /// 在已启用的输入源中挑选 ASCII 键盘布局，优先 ABC / US。
    private static func preferredASCIIInputSource() -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as NSArray? as? [TISInputSource]
        else { return nil }
        let ascii = list.filter { isASCIICapable($0) && isEnabled($0) }
        if let preferred = ascii.first(where: {
            guard let id = sourceID($0) else { return false }
            return id == "com.apple.keylayout.ABC" || id == "com.apple.keylayout.US"
        }) {
            return preferred
        }
        return ascii.first
    }

    private static func isASCIICapable(_ source: TISInputSource) -> Bool {
        boolProperty(source, kTISPropertyInputSourceIsASCIICapable)
    }

    private static func isEnabled(_ source: TISInputSource) -> Bool {
        boolProperty(source, kTISPropertyInputSourceIsEnabled)
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    private static func sourceID(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
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
