import AppKit

// Galt — 菜单栏常驻的 AI 语音听写工具
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
