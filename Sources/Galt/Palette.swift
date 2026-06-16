import AppKit
import SwiftUI

/// Galt 色彩规范 v2.0 的唯一色源（亮 / 暗双模式）。详见仓库根 `Design.md`。
/// 单色品牌：主色亮 `#212121` ↔ 暗 `#F4F4F4`（最高对比中性）；青绿（accent）为唯一彩色点缀。
/// 每个语义 token 都是动态色，随窗口外观（aqua / darkAqua）自动解析，组件无需感知亮暗。
enum Palette {
    /// 按当前外观返回亮 / 暗值（0xRRGGBB）
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    // MARK: 主色（近黑 ↔ 近白，最高对比实心块）
    static let primary = dyn(0x212121, 0xF4F4F4)
    static let primaryHover = dyn(0x383838, 0xFFFFFF)
    static let primaryActive = dyn(0x0A0A0A, 0xD4D4D4)
    static let primarySubtle = dyn(0xECECEC, 0x2A2A2A) // 选中行 / 浅强调底（白卡上）
    /// 侧栏选中底：需在 surface-canvas 上可见，故比 primary-subtle 略深
    static let selectionFill = dyn(0xDFE0E3, 0x303030)
    static let onPrimary = dyn(0xFFFFFF, 0x212121)
    static let textOnColor = onPrimary

    // MARK: 文字
    static let textPrimary = dyn(0x212121, 0xF4F4F4)
    static let textSecondary = dyn(0x757575, 0xA8A8A8)
    static let textTertiary = dyn(0x9E9E9E, 0x7A7A7A)
    static let textDisplay = dyn(0x212121, 0xF4F4F4) // 大号数字（与主文字同值）

    // MARK: 表面（暗色层级越高越亮）
    static let surfaceCanvas = dyn(0xECECEC, 0x161616)
    static let surfacePanel = dyn(0xF5F5F5, 0x1E1E1E)
    static let surfaceCard = dyn(0xFFFFFF, 0x262626)
    static let surfaceRaised = dyn(0xFFFFFF, 0x303030)

    // MARK: 描边
    static let borderDefault = dyn(0xE2E2E2, 0x383838)
    static let borderSubtle = dyn(0xEEEEEE, 0x303030)
    static let track = dyn(0xF0F0F0, 0x2A2A2A)

    // MARK: 青绿点缀 accent（暗色提亮一档）
    static let accent = dyn(0x16AAAC, 0x45BDBC)
    static let accentSubtle = dyn(0xEAF8F7, 0x103B3C)
    static let accentFg = dyn(0x0B7074, 0x7DCFCB)

    // MARK: 语义色（暗色统一提亮）
    static let success = dyn(0x2BA86A, 0x3FBE7E)
    static let success50 = dyn(0xE6F6EE, 0x14301F)
    static let success500 = success
    static let success700 = dyn(0x1C7A4B, 0x6FD79B)
    static let warning = dyn(0xE8973B, 0xF0A94E)
    static let warning50 = dyn(0xFBEBD5, 0x322713)
    static let warning700 = dyn(0xB5712A, 0xF4C07E)
    static let danger = dyn(0xE5484D, 0xF0595E)
    static let danger50 = dyn(0xFDE3E4, 0x3A1718)
    static let danger500 = danger
    static let danger700 = dyn(0xB5363A, 0xF58A8E)
    static let info = dyn(0x2E8FE6, 0x4FA0EE)
    static let info50 = dyn(0xE4ECF9, 0x14243A)
    static let info700 = dyn(0x1E6FD0, 0x80B6F2)

    // MARK: KPI 柔色面（暗色：深底 + 浅字，不照搬 pastel）
    static let softTeal = dyn(0xDAEFEA, 0x16312C)
    static let softAmber = dyn(0xFAE2CC, 0x322713)
    static let softSky = dyn(0xE4ECF9, 0x16243A)
    static let softRose = dyn(0xF0DEDE, 0x331E22)
    static let softTealFg = dyn(0x0B7074, 0x7DCFCB)
    static let softAmberFg = dyn(0xB5712A, 0xF0C079)
    static let softSkyFg = dyn(0x1E6FD0, 0x80B6F2)
    static let softRoseFg = dyn(0xC23B58, 0xE68BA0)

    // MARK: 分类标签
    static let tagBlueBg = dyn(0xDCEBFC, 0x16263D)
    static let tagBlueFg = dyn(0x1E6FD0, 0x7FB4F0)
    static let tagTealBg = dyn(0xD3F1F0, 0x103B3C)
    static let tagTealFg = dyn(0x0B7074, 0x5FD0CE)
    static let tagRoseBg = dyn(0xFBE0E6, 0x3A1E26)
    static let tagRoseFg = dyn(0xC23B58, 0xE68BA0)
    static let tagVioletBg = dyn(0xE9E4FB, 0x241E3D)
    static let tagVioletFg = dyn(0x6B4FD0, 0xA892F0)
    static let tagAmberBg = dyn(0xFBEBD5, 0x322713)
    static let tagAmberFg = dyn(0xB5712A, 0xE0A961)
    static let tagGreenBg = dyn(0xE0F2E6, 0x16301F)
    static let tagGreenFg = dyn(0x2B7A4B, 0x6FCF8F)
}

extension Color {
    /// 以 0xRRGGBB 整型构造颜色（sRGB）
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    /// 以 0xRRGGBB 整型构造 sRGB 颜色
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
