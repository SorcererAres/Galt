import AppKit
import SwiftUI

/// Galt 品牌标记：点 / 划组成的图案（取自 App 图标内的图形）。
/// 16×16 设计网格，180° 点对称：左上点 ↔ 右下点、上横划 ↔ 下横划、左竖划 ↔ 右竖划、中心点自对称。
enum GaltMark {
    /// 设计网格中的元素（16×16）。划用圆头线段、点用同径圆。
    /// 线段：(x1,y1,x2,y2)
    static let dashes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (4.6, 2.5, 9.0, 2.5),    // 上横划
        (2.5, 4.6, 2.5, 9.0),    // 左竖划
        (13.5, 7.0, 13.5, 11.4), // 右竖划
        (7.0, 13.5, 11.4, 13.5), // 下横划
    ]
    static let dots: [(CGFloat, CGFloat)] = [
        (2.5, 2.5),   // 左上点
        (8.0, 8.0),   // 中心点
        (13.5, 13.5), // 右下点
    ]

    /// 绘制成 size×size 的 `NSImage`（供菜单栏 / 程序化图标使用）。
    /// `color` 为 nil 时返回模板图（随菜单栏明暗自动反色）；否则用指定色实心绘制。
    static func image(size: CGFloat = 18, lineWidthRatio: CGFloat = 1.5, color: NSColor? = nil) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let s = size / 16
            let lw = lineWidthRatio * s
            // AppKit 原点在左下，设计网格原点在左上 → 翻转 y
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: (16 - y) * s) }
            (color ?? .black).setStroke()
            (color ?? .black).setFill()
            let strokePath = NSBezierPath()
            strokePath.lineWidth = lw
            strokePath.lineCapStyle = .round
            strokePath.lineJoinStyle = .round
            for (x1, y1, x2, y2) in dashes {
                strokePath.move(to: pt(x1, y1))
                strokePath.line(to: pt(x2, y2))
            }
            strokePath.stroke()
            let r = lw / 2
            for (x, y) in dots {
                let c = pt(x, y)
                NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: lw, height: lw)).fill()
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }
}
