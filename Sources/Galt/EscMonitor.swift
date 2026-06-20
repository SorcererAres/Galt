import AppKit

/// 轻量 ESC 监听：仅在听写进行中（录音 / 处理 / 失败等待）挂载，松手收起即卸载。
/// 全局监听只能观察、无法吞掉事件——ESC 仍会传给前台 App，对我们「中断本次听写」的用途无碍。
/// 依赖辅助功能授权（Galt 录音/出字本就需要），未授权时全局监听拿不到事件，属可接受降级。
final class EscMonitor {
    /// 按下 ESC 时回调（主线程）
    var onEsc: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// kVK_Escape
    private static let escKeyCode: UInt16 = 53

    var isInstalled: Bool { globalMonitor != nil || localMonitor != nil }

    func install() {
        guard !isInstalled else { return } // 幂等
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escKeyCode else { return }
            self?.fire()
        }
        // 本地监听覆盖 Galt 自身窗口聚焦的场景；原样返回事件，不影响其它响应者。
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escKeyCode else { return event }
            self?.fire()
            return event
        }
    }

    func uninstall() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func fire() {
        DispatchQueue.main.async { [weak self] in self?.onEsc?() }
    }

    deinit { uninstall() }
}
