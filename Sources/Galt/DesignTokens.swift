import AppKit
import SwiftUI

/// 全局设计 token：尺寸 / 间距 / 圆角 / 字号 / 控件高度的**单一真相来源**。
///
/// 控制台（`ConsoleDesign`）与设置（`SettingsDesign`）此前各写一套常量、值靠巧合一致，
/// 改一边就会悄悄漂移。两者现在统一从这里取数值，颜色语义别名仍各自保留。
/// 新代码请直接用 `GaltDesign.*`；散落在视图里的间距 / 圆角 / 字号魔数也应逐步迁移到下方阶梯。
enum GaltDesign {

    // MARK: - 窗口 chrome（控制台 / 设置共用）

    /// 窗口内容与外层留白的内缩。
    static let outerInset = Spacing.sm
    static let sidebarWidth: CGFloat = 232
    static let sidebarRowHeight = ControlHeight.row
    static let sidebarRowRadius = Radius.control
    static let sidebarIconWidth: CGFloat = 18
    static let sidebarIconSize = FontSize.body
    static let sidebarTextSize = FontSize.body
    static let sidebarHorizontalPadding: CGFloat = 10
    static let sidebarInnerHorizontalPadding = Spacing.sm
    /// 正文最大宽度：窗口更宽时超出部分居中留白（控制台概览 / 设置内容共用）。
    static let contentWidth: CGFloat = 904
    static let contentTopPadding = Spacing.xl
    static let panelCornerRadius = Radius.panel

    // MARK: - 间距阶梯

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - 圆角阶梯

    enum Radius {
        static let sm: CGFloat = 6        // 小按钮 / HUD
        static let control: CGFloat = 8   // 输入框 / 下拉 / 侧栏行
        static let card: CGFloat = 12     // 卡片 / 列表行
        static let panel: CGFloat = 16    // 面板 / 主内容容器
    }

    // MARK: - 字号阶梯

    enum FontSize {
        static let caption: CGFloat = 12  // 图表标签 / 辅助说明
        static let body: CGFloat = 14     // 正文 / 侧栏
        static let title: CGFloat = 20    // 页头标题
        static let metric: CGFloat = 28   // 指标数值
    }

    // MARK: - 控件高度

    enum ControlHeight {
        static let compact: CGFloat = 28  // 下拉 / 热键录制器
        static let row: CGFloat = 32      // 侧栏行
        static let field: CGFloat = 36    // 表单输入框
    }

    // MARK: - 引导窗口尺寸

    /// 引导是固定尺寸的一次性流程窗。`OnboardingWindow`（正式入口）与
    /// `ConsoleRoute.onboarding`（仅 DEBUG 预览）共用这组常量，避免 480×600 各写一遍。
    enum Onboarding {
        static let windowSize = NSSize(width: 480, height: 600)
        static let minWindowSize = NSSize(width: 420, height: 520)
    }

    // MARK: - 动效

    /// 动效 token：时长与缓动曲线的**单一真相来源**。
    ///
    /// 入场 / 退场 / 悬停一律 ease-out（起步即给反馈，呼应系统 HUD）；页内元素移动 / 选中胶囊
    /// 滑动用无回弹 spring。时长此前以魔数（0.08 / 0.12 / 0.15 / 0.22…）散落 7 个文件、30+ 处，
    /// 改一处难保同步——统一收敛到此。退场比入场快、小元素比大元素快，阶梯已体现这一规律。
    ///
    /// 调用点仍各自按 `reduceMotion` 关闭动画：用下方助手取「已判断」版本，开启「减弱动态」时返回 nil：
    ///   `.animation(GaltDesign.Motion.hover(reduceMotion), value: hovering)`
    ///   `withAnimation(GaltDesign.Motion.page(reduceMotion)) { … }`
    ///
    /// HUD 音浪 / 成功对勾 / 柱状图入场等**一次性精调的 spring 物理参数**不在此集中——它们各自
    /// 贴合特定手感，不是可复用的语义档位，保留在使用处。
    enum Motion {
        /// 时长阶梯（秒）。
        enum Duration {
            static let pressed: TimeInterval = 0.08   // 按下回弹——最快，须即时反馈
            static let hover: TimeInterval = 0.12     // 悬停 / 聚焦状态层
            static let highlight: TimeInterval = 0.15 // 高亮联动 / HUD 阶段切换
            static let expand: TimeInterval = 0.20    // 展开 / 收起
            static let transition: TimeInterval = 0.22 // 大区淡入淡出
        }

        // 标准缓动常量（不含 reduceMotion 判断）。一般请优先用下方 reduceMotion 助手。
        static let pressedEase: Animation = .easeOut(duration: Duration.pressed)
        static let hoverEase: Animation = .easeOut(duration: Duration.hover)
        static let highlightEase: Animation = .easeOut(duration: Duration.highlight)
        static let expandEase: Animation = .easeOut(duration: Duration.expand)
        static let transitionEase: Animation = .easeOut(duration: Duration.transition)
        /// 页内移动 / 侧栏选中胶囊滑动：平滑无回弹弹簧。
        static let pageSpring: Animation = .spring(response: 0.3, dampingFraction: 0.9)

        // reduceMotion 感知助手：开启「减弱动态」时返回 nil（关闭动画）。
        static func pressed(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : pressedEase }
        static func hover(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : hoverEase }
        static func highlight(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : highlightEase }
        static func expand(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : expandEase }
        static func transition(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : transitionEase }
        static func page(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : pageSpring }
    }
}
