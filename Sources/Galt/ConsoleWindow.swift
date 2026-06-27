import AppKit
import SwiftUI

/// 全局统一的时间显示：一律 24 小时制。所有列表 / 历史的时间戳都引用这里，避免散落的
/// 12h / 区域相关格式各自为政。
enum GaltTimeFormat {
    /// 仅时间，24 小时制两位，如 "17:19"
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX") // 固定格式，与区域无关
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 月日 + 时间，24 小时制，按当前区域排月日，如 "6月18日 17:19"
    static let monthDayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        // 模板里的 HH 强制 24 小时制，月日顺序仍随区域本地化
        f.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return f
    }()
}

/// 控制台专属设计常量：尺寸度量统一委托 `GaltDesign`（单一真相来源），
/// 此处仅保留控制台语境下的颜色语义别名。
enum ConsoleDesign {
    static let outerInset = GaltDesign.outerInset
    static let sidebarWidth = GaltDesign.sidebarWidth
    static let sidebarBackground = Palette.surfaceCanvas
    static let panelBackground = Palette.surfacePanel
    static let contentBackground = Palette.surfacePanel
    static let cardBackground = Palette.surfaceCard
    static let fieldBackground = Color(nsColor: .textBackgroundColor)
    static let subtleFill = Palette.stateHover
    // 主操作色：用 teal-600 —— 既是规范「浅底青绿文字/图标」色，又保证白字按钮 ≈3.8:1 过 AA。
    // teal-500 (Palette.primary) 留给纯色块场景（选中态、图表高亮、进度条等无小字处）。
    static let primaryControl = Palette.primary
    static let selectedFill = Palette.selectionFill
    static let border = Palette.borderDefault
    static let primaryControlText = Palette.textOnColor
    static let sidebarRowHeight = GaltDesign.sidebarRowHeight
    static let sidebarRowRadius = GaltDesign.sidebarRowRadius
    static let sidebarIconSize = GaltDesign.sidebarIconSize
    static let sidebarIconWidth = GaltDesign.sidebarIconWidth
    static let sidebarTextSize = GaltDesign.sidebarTextSize
    static let sidebarHorizontalPadding = GaltDesign.sidebarHorizontalPadding
    static let panelCornerRadius = GaltDesign.panelCornerRadius
    static let homeContentWidth = GaltDesign.contentWidth
}

/// 系统毛玻璃背景：`behindWindow` 采样窗口后方（桌面 / 其它窗口），随亮暗与对比自适应。
/// 用于侧栏与窗口留白区，呈现 macOS 原生侧栏的磨砂质感（正文卡片仍走实心，保证可读）。
struct VibrancyBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // 跟随窗口激活态自动提亮 / 变灰，对齐系统侧栏行为
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// 点击窗口空白区域时结束文本编辑。AppKit 默认不会因点空白而让 NSTextField 失焦
/// （只有另一个控件接管焦点、或显式 makeFirstResponder(nil) 才会），这里补上
/// 「点输入框以外的地方即收起焦点」的预期行为。被控件消费的点击不会走到这里。
final class FocusClearingWindow: NSWindow {
    override func mouseDown(with event: NSEvent) {
        // 编辑中时第一响应者是 field editor（NSText 子类）；借这次空白点击结束编辑。
        if firstResponder is NSText {
            makeFirstResponder(nil)
        }
        super.mouseDown(with: event)
    }
}

/// 控制台主窗口（菜单栏 → 打开控制台）
final class ConsoleWindowController: NSObject, NSWindowDelegate {
    static let shared = ConsoleWindowController()
    private let navigation = ConsoleNavigation(route: ConsoleRoute.initialRoute)
    private var window: NSWindow?
    private var currentMinimumContentSize = ConsoleRoute.initialRoute.minimumContentSize

    func show(route: ConsoleRoute = .primary(.overview)) {
        navigation.navigate(to: route)
        if window == nil {
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            let w = FocusClearingWindow(
                contentRect: route.contentRect(for: styleMask),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            w.title = "Galt 控制台"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            // 透明窗口：让侧栏的 behindWindow 毛玻璃能采样到后方桌面/窗口
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.delegate = self
            applyMinimumSize(route.minimumContentSize, to: w)
            let hosting = NSHostingView(rootView: ConsoleView(navigation: navigation) { [weak self] route in
                self?.applyWindowMetrics(for: route)
            })
            // macOS 13+：NSHostingView 会把 SwiftUI 内容尺寸回写到窗口尺寸约束。
            // 控制台的最小尺寸由 AppKit 窗口统一管理，避免历史 / 词典等弹性页面把约束改小。
            hosting.sizingOptions = []
            w.contentView = hosting
            window = w
            applyWindowMetrics(for: route)
        } else {
            applyWindowMetrics(for: route)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func applyWindowMetrics(for route: ConsoleRoute) {
        guard let window else { return }
        currentMinimumContentSize = route.minimumContentSize
        applyMinimumSize(route.minimumContentSize, to: window)
        if let frameSize = route.frameSize {
            window.setFrame(NSRect(origin: window.frame.origin, size: frameSize), display: true)
        } else {
            let targetSize = NSSize(
                width: max(route.contentSize.width, route.minimumContentSize.width),
                height: max(route.contentSize.height, route.minimumContentSize.height)
            )
            window.setContentSize(targetSize)
        }
        window.center()
    }

    private func applyMinimumSize(_ contentMinSize: NSSize, to window: NSWindow) {
        currentMinimumContentSize = contentMinSize
        window.contentMinSize = contentMinSize
        let minFrameRect = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentMinSize))
        window.minSize = minFrameRect.size

        if window.contentView != nil {
            let currentContentSize = window.contentLayoutRect.size
            guard currentContentSize.width < contentMinSize.width || currentContentSize.height < contentMinSize.height else {
                return
            }
            let targetContentSize = NSSize(
                width: max(currentContentSize.width, contentMinSize.width),
                height: max(currentContentSize.height, contentMinSize.height)
            )
            window.setContentSize(targetContentSize)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let proposedFrame = NSRect(origin: sender.frame.origin, size: frameSize)
        let proposedContent = sender.contentRect(forFrameRect: proposedFrame)
        let clampedContentSize = NSSize(
            width: max(proposedContent.width, currentMinimumContentSize.width),
            height: max(proposedContent.height, currentMinimumContentSize.height)
        )
        let clampedFrame = sender.frameRect(forContentRect: NSRect(origin: .zero, size: clampedContentSize))
        return clampedFrame.size
    }

    func show(page: ConsolePrimaryPage) {
        show(route: .primary(page))
    }
}

final class ConsoleNavigation: ObservableObject {
    @Published private(set) var route: ConsoleRoute
    /// 「添加新词」全局模态开关——由根视图在整窗层呈现
    @Published var isAddingTerm = false
    private var lastPrimaryPage: ConsolePrimaryPage

    init(route: ConsoleRoute = .primary(.overview)) {
        self.route = route
        self.lastPrimaryPage = route.primaryPage ?? .overview
    }

    var isShowingSettings: Bool {
        if case .settings = route { return true }
        return false
    }

    var isShowingOnboarding: Bool {
        if case .onboarding = route { return true }
        return false
    }

    var primarySelection: ConsolePrimaryPage {
        route.primaryPage ?? lastPrimaryPage
    }

    func navigate(to route: ConsoleRoute) {
        if let page = route.primaryPage {
            lastPrimaryPage = page
        }
        self.route = route
    }

    func showPrimary(_ page: ConsolePrimaryPage) {
        navigate(to: .primary(page))
    }

    func showSettings() {
        navigate(to: .settings)
    }

    func showOnboarding() {
        navigate(to: .onboarding)
    }

    func leaveSettings() {
        navigate(to: .primary(lastPrimaryPage))
    }

    func completeOnboarding() -> ConsoleRoute {
        SettingsStore.shared.hasCompletedOnboarding = true
        SettingsStore.shared.onboardingVersion = OnboardingView.currentVersion
        let route = ConsoleRoute.primary(.overview)
        navigate(to: route)
        return route
    }
}

enum ConsoleRoute: Equatable {
    case primary(ConsolePrimaryPage)
    case settings
    case onboarding

    static var initialRoute: ConsoleRoute {
        // 引导已独立成 OnboardingWindowController，控制台窗口不再承载 onboarding，
        // 默认始终进概览（仅保留 DEBUG 下的显式 onboarding 便于单独预览引导界面）。
        #if DEBUG
        switch ProcessInfo.processInfo.environment["GALT_CONSOLE_PAGE"] {
        case "history": return .primary(.history)
        case "dictionary": return .primary(.dictionary)
        case "settings": return .settings
        case "onboarding": return .onboarding
        default: return .primary(.overview)
        }
        #else
        return .primary(.overview)
        #endif
    }

    var primaryPage: ConsolePrimaryPage? {
        if case let .primary(page) = self { return page }
        return nil
    }

    var contentSize: NSSize {
        switch self {
        case .onboarding:
            // 引导窗实际由 frameSize 驱动（见 applyWindowMetrics），此处与 frameSize 取齐避免歧义。
            return GaltDesign.Onboarding.windowSize
        case .primary, .settings:
            return NSSize(width: 1200, height: 800)
        }
    }

    func contentRect(for styleMask: NSWindow.StyleMask) -> NSRect {
        if let frameSize {
            return NSWindow.contentRect(
                forFrameRect: NSRect(origin: .zero, size: frameSize),
                styleMask: styleMask
            )
        }
        return NSRect(origin: .zero, size: contentSize)
    }

    var frameSize: NSSize? {
        switch self {
        case .onboarding:
            return GaltDesign.Onboarding.windowSize
        case .primary, .settings:
            return nil
        }
    }

    var minimumContentSize: NSSize {
        switch self {
        case .onboarding:
            return GaltDesign.Onboarding.minWindowSize
        case .primary, .settings:
            // 概览内容固定 904 + 侧栏 232 + 外边距 16 ≈ 1152，取 1200 留出余量，避免最小窗口下裁切
            return NSSize(width: 1200, height: 620)
        }
    }
}

enum ConsolePrimaryPage: CaseIterable, Identifiable {
    case overview, history, dictionary

    var id: ConsolePrimaryPage { self }

    var sidebarTitle: String {
        switch self {
        case .overview: return "首页"
        case .history: return "历史"
        case .dictionary: return "词典"
        }
    }

    var contentTitle: String {
        switch self {
        case .overview: return "概览"
        case .history: return "听写历史"
        case .dictionary: return "个人词典"
        }
    }
}

struct ConsoleView: View {
    @ObservedObject var navigation: ConsoleNavigation
    let onRouteMetricsChange: (ConsoleRoute) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 大区切换（主界面 ⇄ 设置 ⇄ 引导）：进入用 ease-out 淡入
    private var routeAnimation: Animation? {
        GaltDesign.Motion.transition(reduceMotion)
    }
    /// 一级页切换与侧栏选中：平滑无回弹弹簧，让选中胶囊滑动 + 内容淡入一气呵成
    private var pageAnimation: Animation? {
        GaltDesign.Motion.page(reduceMotion)
    }

    var body: some View {
        let minContent = navigation.route.minimumContentSize
        Group {
            if navigation.isShowingOnboarding {
                OnboardingView {
                    let route = withAnimation(routeAnimation) { navigation.completeOnboarding() }
                    onRouteMetricsChange(route)
                }
                .transition(.opacity)
            } else if navigation.isShowingSettings {
                SettingsView(layout: .sidebar) {
                    withAnimation(routeAnimation) { navigation.leaveSettings() }
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    ConsoleSidebar(
                        selection: Binding(
                            get: { navigation.primarySelection },
                            set: { page in
                                withAnimation(pageAnimation) { navigation.showPrimary(page) }
                            }
                        ),
                        onSettings: { withAnimation(routeAnimation) { navigation.showSettings() } }
                    )
                    .frame(width: ConsoleDesign.sidebarWidth)

                    contentPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(ConsoleDesign.outerInset)
                .transition(.opacity)
            }
        }
        // 窗口画布走毛玻璃；侧栏与四周留白透出后方，正文卡片在其上保持实心
        .background(VibrancyBackground())
        .ignoresSafeArea()
        // 让 SwiftUI 根自己报告最小尺寸——NSHostingView 异步推送给窗口 contentMinSize 的就是这个值，
        // 避免仅靠 sizingOptions=[]+显式赋值的方案被首个 runloop 的布局回写覆盖。
        .frame(minWidth: minContent.width, minHeight: minContent.height)
        // 全局模态：铺满整窗（含侧栏与四周留白），不受单个 pane 边界限制
        .overlay {
            if navigation.isAddingTerm {
                AddTermDialog(onClose: { navigation.isAddingTerm = false })
                    .transition(.opacity)
            }
        }
        .animation(routeAnimation, value: navigation.isAddingTerm)
    }

    private var contentPanel: some View {
        ZStack {
            // 稳定的面板底色：切换页时只让内容淡入淡出，避免出现空隙闪白
            ConsoleDesign.panelBackground
            Group {
                switch navigation.primarySelection {
                case .overview: OverviewPage(onSeeAll: { withAnimation(pageAnimation) { navigation.showPrimary(.history) } })
                case .history: HistoryPage()
                case .dictionary: DictionaryPage(onRequestAddTerm: { navigation.isAddingTerm = true })
                }
            }
            .id(navigation.primarySelection)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: ConsoleDesign.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ConsoleDesign.panelCornerRadius, style: .continuous)
                .strokeBorder(ConsoleDesign.border, lineWidth: 1)
        )
    }
}

struct ConsoleSidebar: View {
    @Binding var selection: ConsolePrimaryPage
    let onSettings: () -> Void
    @Namespace private var selectionPill

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)

            VStack(spacing: 0) {
                ForEach(ConsolePrimaryPage.allCases) { page in
                    ConsoleSidebarRow(
                        title: page.sidebarTitle,
                        page: page,
                        isSelected: selection == page,
                        namespace: selectionPill
                    ) {
                        selection = page
                    }
                }
            }
            .padding(.horizontal, ConsoleDesign.sidebarHorizontalPadding)

            Spacer()

            Button(action: onSettings) {
                ConsoleSidebarFooterRowContent(title: "设置")
            }
            .buttonStyle(RowButtonStyle())
            .padding(.horizontal, ConsoleDesign.sidebarHorizontalPadding)
            .padding(.bottom, GaltDesign.Spacing.sm)
        }
        // 不铺实心底色——透出窗口画布的毛玻璃
    }
}

struct ConsoleSidebarRow: View {
    let title: String
    let page: ConsolePrimaryPage
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ConsoleSidebarRowContent(title: title, page: page, isSelected: isSelected, namespace: namespace)
        }
        .buttonStyle(RowButtonStyle(isSelected: isSelected, selectionDrawnExternally: true))
    }
}

struct ConsoleSidebarRowContent: View {
    let title: String
    let page: ConsolePrimaryPage
    let isSelected: Bool
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.xs) {
            SidebarPageIcon(page: page)
                .frame(width: ConsoleDesign.sidebarIconWidth, height: 16)
            Text(title)
                .font(.system(size: ConsoleDesign.sidebarTextSize, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.textPrimary)
        .frame(height: ConsoleDesign.sidebarRowHeight)
        .padding(.leading, GaltDesign.Spacing.sm)
        .padding(.trailing, 10)
        .background {
            // 唯一的选中胶囊，借 matchedGeometryEffect 在各行间滑动
            if isSelected {
                RoundedRectangle(cornerRadius: ConsoleDesign.sidebarRowRadius, style: .continuous)
                    .fill(ConsoleDesign.selectedFill)
                    .matchedGeometryEffect(id: "consoleSidebarSelection", in: namespace)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ConsoleDesign.sidebarRowRadius, style: .continuous))
    }
}

struct ConsoleSidebarFooterRowContent: View {
    let title: String

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.xs) {
            SlidersHorizontalShape()
                .stroke(style: StrokeStyle(lineWidth: 1.333, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)
                .frame(width: ConsoleDesign.sidebarIconWidth, height: 16)
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.textPrimary.opacity(0.85))
        .frame(height: ConsoleDesign.sidebarRowHeight)
        .padding(.leading, GaltDesign.Spacing.sm)
        .padding(.trailing, 10)
        .contentShape(RoundedRectangle(cornerRadius: ConsoleDesign.sidebarRowRadius, style: .continuous))
    }
}

/// 侧栏一级页图标（对照 Figma node 610:637）：描边矢量，1.333 线宽 / 圆头圆角，16×16 画布。
struct SidebarPageIcon: View {
    let page: ConsolePrimaryPage
    private let style = StrokeStyle(lineWidth: 1.333, lineCap: .round, lineJoin: .round)

    var body: some View {
        Group {
            switch page {
            case .overview: HomeWaveformShape().stroke(style: style)
            case .history: HistoryFolderClockShape().stroke(style: style)
            case .dictionary: DictionaryBookShape().stroke(style: style)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// 首页（node 610:650）：6 条高低不一的竖条（声纹/均衡器）
struct HomeWaveformShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        // (x, y起, y止)
        let bars: [(CGFloat, CGFloat, CGFloat)] = [
            (1.3333, 6.6667, 8.6667), (4, 4, 11.3333), (6.6667, 2, 14),
            (9.3333, 5.3333, 10), (12, 3.3333, 12), (14.6667, 6.6667, 8.6667),
        ]
        var p = Path()
        for (x, y0, y1) in bars {
            p.move(to: pt(x, y0))
            p.addLine(to: pt(x, y1))
        }
        return p
    }
}

/// 历史（node 610:662）：文件夹 + 时钟 + 表针
struct HistoryFolderClockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        func curve(_ p: inout Path, to ex: CGFloat, _ ey: CGFloat,
                   _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
            p.addCurve(to: pt(ex, ey), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
        }
        var p = Path()
        // 表针
        p.move(to: pt(10.6667, 9.3333))
        p.addLine(to: pt(10.6667, 10.8))
        p.addLine(to: pt(11.7333, 11.4667))
        // 文件夹外形（开放路径）
        p.move(to: pt(4.6667, 13.3334))
        p.addLine(to: pt(2.6667, 13.3334))
        curve(&p, to: 1.72386, 12.9429, 2.31304, 13.3334, 1.97391, 13.1929)
        curve(&p, to: 1.33333, 12.0001, 1.47381, 12.6928, 1.33333, 12.3537)
        p.addLine(to: pt(1.33333, 3.3334))
        curve(&p, to: 1.72386, 2.39059, 1.33333, 2.97978, 1.47381, 2.64064)
        curve(&p, to: 2.66667, 2.00006, 1.97391, 2.14054, 2.31304, 2.00006)
        p.addLine(to: pt(5.26667, 2.00006))
        curve(&p, to: 5.90647, 2.15648, 5.48966, 1.99788, 5.70964, 2.05166)
        curve(&p, to: 6.39333, 2.60006, 6.1033, 2.2613, 6.27069, 2.41381)
        p.addLine(to: pt(6.93333, 3.40006))
        curve(&p, to: 7.41433, 3.84047, 7.05474, 3.58442, 7.22002, 3.73574)
        curve(&p, to: 8.04667, 4.00006, 7.60865, 3.94519, 7.82593, 4.00003)
        p.addLine(to: pt(13.3333, 4.00006))
        curve(&p, to: 14.2761, 4.39059, 13.687, 4.00006, 14.0261, 4.14054)
        curve(&p, to: 14.6667, 5.3334, 14.5262, 4.64064, 14.6667, 4.97978)
        // 时钟表盘
        p.addEllipse(in: CGRect(x: 6.6667 * s, y: 6.6667 * s, width: 8 * s, height: 8 * s))
        return p
    }
}

/// 词典（node 610:671）：书封圆角矩形 + 书脊竖线 + 斜置的另一册
struct DictionaryBookShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        func curve(_ p: inout Path, to ex: CGFloat, _ ey: CGFloat,
                   _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
            p.addCurve(to: pt(ex, ey), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
        }
        var p = Path()
        // 书封：圆角矩形 (2,2)-(7.333,14)，圆角 ~0.667
        p.addRoundedRect(in: CGRect(x: 2 * s, y: 2 * s, width: 5.3333 * s, height: 12 * s),
                         cornerSize: CGSize(width: 0.6667 * s, height: 0.6667 * s),
                         style: .continuous)
        // 书脊
        p.move(to: pt(4.6667, 2))
        p.addLine(to: pt(4.6667, 14))
        // 斜置的另一册
        p.move(to: pt(13.6, 12.6002))
        curve(&p, to: 13.2, 13.4668, 13.7333, 12.9335, 13.5333, 13.3335)
        p.addLine(to: pt(11.9333, 13.9335))
        curve(&p, to: 11.0667, 13.5335, 11.6, 14.0668, 11.2, 13.8668)
        p.addLine(to: pt(7.4, 3.40016))
        curve(&p, to: 7.8, 2.5335, 7.26667, 3.06683, 7.46667, 2.66683)
        p.addLine(to: pt(9.06667, 2.06683))
        curve(&p, to: 9.93333, 2.46683, 9.4, 1.9335, 9.8, 2.1335)
        p.closeSubpath()
        return p
    }
}

/// 自动添加（node 635:1333）：魔杖 / 自动手势 + 底部基线
struct AutoAddShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        func curve(_ p: inout Path, to ex: CGFloat, _ ey: CGFloat,
                   _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
            p.addCurve(to: pt(ex, ey), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
        }
        var p = Path()
        p.move(to: pt(14, 11.3332))
        p.addLine(to: pt(12.5627, 10.0878))
        curve(&p, to: 12.391, 10.0014, 12.5152, 10.0428, 12.4554, 10.0127)
        curve(&p, to: 12.2001, 10.0242, 12.3265, 9.9901, 12.2601, 9.99802)
        curve(&p, to: 12.0535, 10.1486, 12.1401, 10.0503, 12.0891, 10.0936)
        curve(&p, to: 12, 10.3332, 12.0179, 10.2035, 11.9993, 10.2677)
        p.addLine(to: pt(12, 10.6665))
        curve(&p, to: 11.8047, 11.1379, 12, 10.8433, 11.9298, 11.0129)
        curve(&p, to: 11.3333, 11.3332, 11.6797, 11.2629, 11.5101, 11.3332)
        p.addLine(to: pt(10, 11.3332))
        curve(&p, to: 9.5286, 11.1379, 9.82319, 11.3332, 9.65362, 11.2629)
        curve(&p, to: 9.33333, 10.6665, 9.40357, 11.0129, 9.33333, 10.8433)
        curve(&p, to: 3.66667, 7.99985, 9.33333, 8.96985, 6.67267, 8.01985)
        curve(&p, to: 2.48816, 8.488, 3.22464, 7.99985, 2.80072, 8.17544)
        curve(&p, to: 2, 9.66651, 2.17559, 8.80056, 2, 9.22449)
        curve(&p, to: 2.48816, 10.845, 2, 10.1085, 2.17559, 10.5325)
        curve(&p, to: 3.66667, 11.3332, 2.80072, 11.1576, 3.22464, 11.3332)
        curve(&p, to: 7.472, 2.33318, 6.43533, 11.3332, 6.83, 3.80318)
        curve(&p, to: 7.95937, 1.69812, 7.58045, 2.08504, 7.74773, 1.86707)
        curve(&p, to: 8.68662, 1.36355, 8.17101, 1.52917, 8.42062, 1.41434)
        curve(&p, to: 9.48598, 1.40666, 8.95262, 1.31277, 9.22698, 1.32757)
        curve(&p, to: 10.173, 1.8175, 9.74497, 1.48576, 9.98079, 1.62677)
        curve(&p, to: 10.5893, 2.50129, 10.3653, 2.00823, 10.5081, 2.24293)
        curve(&p, to: 10.6387, 3.30029, 10.6704, 2.75965, 10.6874, 3.0339)
        curve(&p, to: 10.3099, 4.03015, 10.59, 3.56667, 10.4771, 3.81719)
        curve(&p, to: 9.67867, 4.52251, 10.1426, 4.24311, 9.92594, 4.41211)
        // 底部基线
        p.move(to: pt(2, 14))
        p.addLine(to: pt(14, 14))
        return p
    }
}

/// 手动添加（node 635:1323）：手绘波浪线
struct ManualAddShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        func curve(_ p: inout Path, to ex: CGFloat, _ ey: CGFloat,
                   _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
            p.addCurve(to: pt(ex, ey), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
        }
        var p = Path()
        p.move(to: pt(4.66674, 2.33324))
        curve(&p, to: 6.66674, 4.99991, 8.00007, 0.999907, 9.3334, 3.99991)
        curve(&p, to: 3.3334, 10.6666, 1.00007, 6.66657, 1.3334, 9.99991)
        curve(&p, to: 12.6667, 5.99991, 6.66674, 11.9999, 9.3334, 3.99991)
        curve(&p, to: 10.0001, 13.9999, 16.0001, 7.99991, 13.0001, 14.9999)
        curve(&p, to: 14.0001, 12.6666, 6.66674, 12.3332, 10.3334, 6.66657)
        return p
    }
}

/// Figma 设置图标（node 610:680）：两条横轨 + 对角错位的两个圆钮，对齐 16×16 画布
struct SlidersHorizontalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        var p = Path()
        // 上轨（偏右）
        p.move(to: CGPoint(x: 6.667 * s, y: 4.667 * s))
        p.addLine(to: CGPoint(x: 12.667 * s, y: 4.667 * s))
        // 下轨（偏左）
        p.move(to: CGPoint(x: 3.333 * s, y: 11.333 * s))
        p.addLine(to: CGPoint(x: 9.333 * s, y: 11.333 * s))
        // 上钮（左）
        p.addEllipse(in: CGRect(x: 2.667 * s, y: 2.667 * s, width: 4 * s, height: 4 * s))
        // 下钮（右）
        p.addEllipse(in: CGRect(x: 9.333 * s, y: 9.333 * s, width: 4 * s, height: 4 * s))
        return p
    }
}

private enum ConsoleStyle {
    static let panelBackground = ConsoleDesign.panelBackground
    static let cardBackground = ConsoleDesign.cardBackground
    static let subtleFill = ConsoleDesign.subtleFill
    static let border = ConsoleDesign.border
}

struct ConsolePageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: GaltDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: GaltDesign.Spacing.sm) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 24)
            trailing()
        }
    }
}

struct ConsoleSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
        }
        .padding(.horizontal, GaltDesign.Spacing.md)
        .frame(height: GaltDesign.ControlHeight.field) // 输入框统一 36，对齐 FormFieldBox / SecretField
        .background(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                .fill(ConsoleDesign.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                .strokeBorder(ConsoleStyle.border, lineWidth: 1)
        )
    }
}

struct ConsoleEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: GaltDesign.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(GaltDesign.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous)
                .fill(ConsoleStyle.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous)
                .strokeBorder(ConsoleStyle.border, lineWidth: 1)
        )
    }
}

// MARK: - 概览页

struct OverviewPage: View {
    var onSeeAll: () -> Void = {}
    @AppStorage("polishEnabled") private var polishEnabled = true
    @State private var records: [HistoryRecord] = []
    @StateObject private var recentScroll = ScrollMetrics()
    /// 应用占比图与图例共享的高亮项（应用名）；nil 表示无高亮
    @State private var highlightedApp: String?
    /// 「语音输入」快捷键展示文案，随设置变更刷新
    @State private var dictationHint = HotkeyCombo.dictationDisplay
    /// 柱状图当前悬停的日期；nil 表示无悬停
    @State private var hoveredDay: Date?
    /// 柱状图入场生长动画开关
    @State private var barsAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 整页填满窗口：顶部仪表盘固定，「最近的转录内容」卡片吸收剩余高度并内部滚动，
        // 不再嵌套整页滚动条（避免双滚动条）。
        VStack(alignment: .leading, spacing: 0) {
            Text("Galt")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(height: 28, alignment: .leading)

            Text("Speak. The mind does the rest.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
                .frame(height: 24, alignment: .leading)
                .padding(.top, GaltDesign.Spacing.xxs)

            metricsGrid
                .padding(.top, 20)

            HStack(spacing: GaltDesign.Spacing.lg) {
                chartSection
                personalizationSection
            }
            .padding(.top, GaltDesign.Spacing.lg)

            recentSection
                .padding(.top, 15)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: ConsoleDesign.homeContentWidth, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, GaltDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ConsoleStyle.panelBackground)
        .onAppear { reload(); dictationHint = HotkeyCombo.dictationDisplay }
        .onReceive(NotificationCenter.default.publisher(for: .galtHistoryChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .galtHotkeysChanged)) { _ in
            dictationHint = HotkeyCombo.dictationDisplay
        }
    }

    private func reload() {
        records = HistoryStore.shared.all()
    }

    // MARK: 统计卡片

    private var todayWords: Int {
        records.filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + HistoryStore.wordCount($1.text) }
    }

    private var totalWords: Int {
        records.reduce(0) { $0 + HistoryStore.wordCount($1.text) }
    }

    private var totalSeconds: Double {
        records.reduce(0) { $0 + $1.duration }
    }

    private var wpm: Int {
        totalSeconds > 1 ? Int(Double(totalWords) / (totalSeconds / 60)) : 0
    }

    private var savedMinutes: Int {
        max(0, Int(Double(totalWords) / 45.0 - totalSeconds / 60))
    }

    private var totalMinutes: Int {
        Int(totalSeconds / 60)
    }

    private var metricsGrid: some View {
        HStack(spacing: GaltDesign.Spacing.lg) {
            MetricCard(title: "总字数", subtitle: "所有时间使用", value: "\(totalWords)", fill: Palette.softTeal)
            MetricCard(title: "今日字数", subtitle: "今天已输出", value: "\(todayWords)", fill: Palette.softAmber)
            MetricCard(title: "使用时间", subtitle: "累计听写时长", value: "\(totalMinutes)", unit: "min", fill: Palette.softSky)
            MetricCard(title: "累计听写", subtitle: "所有会话", value: "\(records.count)", unit: "次", fill: Palette.softRose)
        }
    }

    // MARK: 本周柱状图（周日 → 周六）

    private struct DayValue: Identifiable {
        let day: Date
        let seconds: Double
        let count: Int
        var id: Date { day }
    }

    /// 本周周日 0 点（固定以周日为周起点，与 日一二三四五六 轴对齐）
    private func startOfWeekSunday(_ calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1 = 周日
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: today)
    }

    /// 本周每日听写时长（秒），周日→周六；今天之后的日期为空柱
    private var dailyTime: [DayValue] {
        let calendar = Calendar.current
        guard let sunday = startOfWeekSunday(calendar) else { return [] }
        var byDay: [Date: Double] = [:]
        var cntDay: [Date: Int] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.date)
            byDay[day, default: 0] += record.duration
            cntDay[day, default: 0] += 1
        }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: sunday) else { return nil }
            return DayValue(day: day, seconds: byDay[day] ?? 0, count: cntDay[day] ?? 0)
        }
    }

    /// 时长简洁展示：h / min / s
    private func durationLabel(_ secs: Double) -> String {
        if secs >= 3600 { return "\(Int((secs / 3600).rounded()))h" }
        if secs >= 60 { return "\(Int(secs / 60))min" }
        return "\(Int(secs))s"
    }

    private var maxDailySeconds: Double { dailyTime.map(\.seconds).max() ?? 0 }

    /// 指定「几周前」的整周（周日→周六）听写总时长（0 = 本周，1 = 上周）
    private func weekSeconds(weeksAgo: Int) -> Double {
        let calendar = Calendar.current
        guard let sunday = startOfWeekSunday(calendar),
              let start = calendar.date(byAdding: .day, value: -(weeksAgo * 7), to: sunday),
              let end = calendar.date(byAdding: .day, value: 7, to: start) else { return 0 }
        return records.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.duration }
    }

    private var weeklyTotalLabel: String {
        let secs = weekSeconds(weeksAgo: 0)
        if secs >= 3600 { return "\(Int((secs / 3600).rounded()))h" }
        if secs >= 60 { return "\(Int(secs / 60))min" }
        return "\(Int(secs))s"
    }

    /// 本周相对上周的变化百分比；上周为 0 时返回 nil
    private var weeklyChangePercent: Int? {
        let last = weekSeconds(weeksAgo: 1)
        guard last > 0 else { return nil }
        return Int(((weekSeconds(weeksAgo: 0) - last) / last * 100).rounded())
    }

    /// 占比统计的归一化键：去空格 + 小写，用于无 bundleId 时按名称聚类
    private static func normalizedAppKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 近 7 天各前台 App 的使用占比（与「生产力趋势」同口径）。
    /// 聚类：优先按 bundleId 归并；老记录无 bundleId 时回退到归一化名称，
    /// 并借「名称→bundleId」映射把它们并入同一应用簇。展示名取簇内最常见的原始名称。
    private var appUsage: [AppUsageSlice] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        let recent = records.filter { $0.date >= start }
        guard !recent.isEmpty else { return [] }

        // 用「同时有名称与 bundleId 的记录」建立映射，让老记录(无 bundleId)也能并入同簇
        var nameToBundle: [String: String] = [:]
        for r in recent {
            if let b = r.bundleId, let n = r.app {
                nameToBundle[Self.normalizedAppKey(n)] = b
            }
        }

        struct Cluster { var count = 0; var names: [String: Int] = [:] }
        var clusters: [String: Cluster] = [:]
        for r in recent {
            let name = r.app ?? "未知应用"
            let nkey = Self.normalizedAppKey(name)
            let key = r.bundleId ?? nameToBundle[nkey] ?? nkey
            var c = clusters[key] ?? Cluster()
            c.count += 1
            c.names[name, default: 0] += 1
            clusters[key] = c
        }

        let total = Double(recent.count)
        // 每簇用出现最多的原始名称作展示名，按用量降序
        let sorted = clusters.values
            .map { (name: $0.names.max { $0.value < $1.value }?.key ?? "未知应用", count: $0.count) }
            .sorted { $0.count > $1.count }
        let colors = [Palette.chartTeal, Palette.chartAmber, Palette.chartSky, Palette.chartRose]

        // 应用数 ≤ 配色槽位：全部按真名展示；否则前 3 名 + 其余聚合为「其他」
        if sorted.count <= colors.count {
            return sorted.enumerated().map { e in
                AppUsageSlice(name: e.element.name, share: Double(e.element.count) / total,
                              count: e.element.count, color: colors[e.offset])
            }
        }
        var result = sorted.prefix(3).enumerated().map { e in
            AppUsageSlice(name: e.element.name, share: Double(e.element.count) / total,
                          count: e.element.count, color: colors[e.offset])
        }
        let othersCount = sorted.dropFirst(3).reduce(0) { $0 + $1.count }
        result.append(AppUsageSlice(name: "其他", share: Double(othersCount) / total,
                                    count: othersCount, color: colors[3]))
        return result
    }

    private func weekdayLabel(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date) // 1=周日
        return ["日", "一", "二", "三", "四", "五", "六"][(weekday - 1) % 7]
    }

    // 生产力趋势：左侧周总时长 + 环比徽标，右侧带星期轴的柱图
    private var chartSection: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
                Text("生产力趋势")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("每日听写时间")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, GaltDesign.Spacing.md)
            .padding(.top, GaltDesign.Spacing.md)

            VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
                Text(weeklyTotalLabel)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.textDisplay)
                    .monospacedDigit()
                Text("本周")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, GaltDesign.Spacing.md)
            .padding(.top, 61)

            weeklyChangeBadge
                .padding(.leading, 13)
                .padding(.top, 123)

            productivityBars
                .frame(width: 292, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 444, height: 167, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous).fill(Palette.surfaceCard))
    }

    @ViewBuilder
    private var weeklyChangeBadge: some View {
        if let pct = weeklyChangePercent {
            let up = pct >= 0
            badge("\(up ? "+" : "")\(pct)%与上周相比",
                  fg: up ? Palette.success700 : Palette.danger700,
                  bg: up ? Palette.success50 : Palette.danger50)
        } else if weekSeconds(weeksAgo: 0) > 0 {
            badge("本周新增", fg: Palette.success700, bg: Palette.success50)
        }
    }

    private func badge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(fg)
            .padding(.horizontal, GaltDesign.Spacing.md)
            .padding(.vertical, GaltDesign.Spacing.xxs)
            .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous).fill(bg))
    }

    @ViewBuilder
    private var productivityBars: some View {
        if weekSeconds(weeksAgo: 0) <= 0 {
            emptyWeekState
        } else {
            let maxV = max(maxDailySeconds, 1)
            VStack(spacing: GaltDesign.Spacing.sm) {
                HStack(alignment: .bottom, spacing: GaltDesign.Spacing.lg) {
                    ForEach(Array(dailyTime.enumerated()), id: \.element.id) { index, d in
                        barColumn(d, index: index, maxV: maxV)
                    }
                }
                .frame(height: 101, alignment: .bottom)
                HStack(spacing: GaltDesign.Spacing.lg) {
                    ForEach(dailyTime) { d in
                        Text(weekdayLabel(d.day))
                            .font(.system(size: 12, weight: hoveredDay == d.day ? .semibold : .regular))
                            .foregroundStyle(hoveredDay == d.day ? Palette.textPrimary : Palette.textSecondary)
                            .frame(width: 24)
                            .animation(GaltDesign.Motion.highlight(reduceMotion), value: hoveredDay)
                    }
                }
            }
            .padding(.top, 25)
            .padding(.trailing, GaltDesign.Spacing.md)
            .onAppear { barsAppeared = true }
        }
    }

    /// 本周完全无记录：右侧柱区显示一句引导，替代 7 根零值灰柱
    private var emptyWeekState: some View {
        Text("本周还没有听写记录")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            .padding(.trailing, GaltDesign.Spacing.md)
    }

    /// 单日柱列：透明命中区撑满整列便于悬停；柱体入场生长 + 悬停高亮 + 顶部数值气泡
    private func barColumn(_ d: DayValue, index: Int, maxV: Double) -> some View {
        let isOn = hoveredDay == d.day
        let dim = hoveredDay != nil && !isOn
        return ZStack(alignment: .bottom) {
            Color.clear.frame(width: 24, height: 101) // 全列高度命中区
            RoundedRectangle(cornerRadius: GaltDesign.Radius.sm, style: .continuous)
                .fill(isOn ? Palette.accent : barColor(d.seconds))
                .frame(width: 24, height: barHeight(d.seconds, max: maxV))
                .scaleEffect(y: barsAppeared ? 1 : 0.001, anchor: .bottom) // 从基线生长
                .animation(reduceMotion ? nil :
                    .spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.05),
                    value: barsAppeared)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: d.seconds)
        }
        .frame(width: 24, height: 101, alignment: .bottom)
        .scaleEffect(x: isOn ? 1.1 : 1, anchor: .bottom)
        .opacity(dim ? 0.45 : 1)
        .overlay(alignment: .top) {
            if isOn { barTooltip(d).offset(y: -6) }
        }
        .animation(GaltDesign.Motion.highlight(reduceMotion), value: hoveredDay)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoveredDay = d.day }
            else if hoveredDay == d.day { hoveredDay = nil }
        }
    }

    /// 柱顶数值气泡：周X · 时长 · 次数（无记录时显示「暂无」）
    private func barTooltip(_ d: DayValue) -> some View {
        let text = d.count == 0
            ? "周\(weekdayLabel(d.day)) · 暂无"
            : "周\(weekdayLabel(d.day)) · \(durationLabel(d.seconds)) · \(d.count) 次"
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, GaltDesign.Spacing.sm)
            .padding(.vertical, GaltDesign.Spacing.xxs)
            .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.sm, style: .continuous).fill(Palette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.sm, style: .continuous).strokeBorder(Palette.borderSubtle, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .transition(.opacity)
    }

    private func barHeight(_ value: Double, max maxV: Double) -> CGFloat {
        guard value > 0 else { return 8 }
        return Swift.max(16, CGFloat(value / maxV) * 101)
    }

    private func barColor(_ value: Double) -> Color {
        guard value > 0 else { return Palette.track }
        return value == maxDailySeconds ? Palette.accent : Palette.accentSubtle
    }

    // 个性化：左侧应用占比环形图 + 右侧图例
    private var personalizationSection: some View {
        ZStack {
            if appUsage.isEmpty {
                Text("听写后这里会显示各应用的使用占比。")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, GaltDesign.Spacing.xl)
            } else {
                HStack(spacing: 0) {
                    DonutChart(
                        segments: appUsage.map { DonutSegment(name: $0.name, value: Double($0.count), color: $0.color) },
                        highlighted: $highlightedApp,
                        centerCaption: "近 7 天"
                    )
                    .frame(width: 120, height: 120)
                    .padding(.leading, GaltDesign.Spacing.xl)
                    Spacer(minLength: 16)
                    VStack(alignment: .leading, spacing: GaltDesign.Spacing.md) {
                        ForEach(appUsage) { usage in
                            usageLegendRow(usage)
                        }
                    }
                    .frame(width: 200)
                    .padding(.trailing, 28)
                }
            }
        }
        .frame(width: 444, height: 167)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous).fill(Palette.surfaceCard))
    }

    private func usageLegendRow(_ usage: AppUsageSlice) -> some View {
        // 与环形图共享高亮：本行高亮时整行不透明、其余降淡；悬停回写高亮状态
        let isOn = highlightedApp == usage.name
        let dimmed = highlightedApp != nil && !isOn
        return VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
            Text(usage.name)
                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule().fill(usage.color)
                        .frame(width: max(4, proxy.size.width * usage.share))
                }
            }
            .frame(height: 4)
        }
        .opacity(dimmed ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in highlightedApp = hovering ? usage.name : nil }
        .animation(GaltDesign.Motion.highlight(reduceMotion), value: highlightedApp)
    }

    private func dashboardCard<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .padding(GaltDesign.Spacing.md)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous)
                .fill(ConsoleDesign.cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous))
    }

    // MARK: 最近听写

    /// 最多展示的转录条数（列表可上下滚动）
    private static let recentLimit = 25

    private var recentSection: some View {
        // 不再统一 padding(12)：表头自带内边距，列表区里滚动条独占右侧一列、贴卡片右内缘
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text("最近的转录内容")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Button(action: onSeeAll) {
                    Text("查看全部")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Palette.textPrimary)
                }
                .buttonStyle(LinkButtonStyle())
                .accessibilityLabel("查看全部转录记录")
            }
            .frame(height: 22)
            .padding(.horizontal, GaltDesign.Spacing.md)
            .padding(.top, GaltDesign.Spacing.md)

            if records.isEmpty {
                VStack(spacing: GaltDesign.Spacing.sm) {
                    Spacer(minLength: 0)
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text("还没有听写记录，按住 \(dictationHint) 试试。")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(GaltDesign.Spacing.md)
            } else {
                // 行在左（留 12pt 内边距），滚动条独占右侧 6pt 一列并贴卡片右内缘
                HStack(spacing: GaltDesign.Spacing.sm) {
                    BrandScrollViewCore(metrics: recentScroll) {
                        LazyVStack(spacing: GaltDesign.Spacing.md) {
                            ForEach(Array(records.prefix(Self.recentLimit)), id: \.id) { record in
                                RecentTranscriptRow(record: record)
                            }
                        }
                        .padding(.top, GaltDesign.Spacing.md)
                        .padding(.bottom, GaltDesign.Spacing.xxxs) // 末行描边不被裁切
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    BrandScrollbar(metrics: recentScroll)
                        .frame(width: 6)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, GaltDesign.Spacing.md)
                }
                .padding(.leading, GaltDesign.Spacing.md)   // 行的左内边距
                .padding(.trailing, GaltDesign.Spacing.xxs)   // 滚动条贴卡片右内缘（留 4pt 避开 16pt 圆角）
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous).fill(ConsoleDesign.cardBackground))
        .clipShape(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous))
    }
}

/// 概览页顶部统计卡片。纯展示、不可点击，故 hover 仅做克制的「呼吸」：
/// 轻微提起 + 阴影渐显，绝不动布局，也不改底色（只动 transform / shadow）。
private struct MetricCard: View {
    let title: String
    let subtitle: String
    let value: String
    var unit: String? = nil
    let fill: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(height: 22, alignment: .leading)
            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
                .frame(height: 16, alignment: .leading)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.textDisplay)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(height: 36, alignment: .leading)
        }
        .padding(GaltDesign.Spacing.md)
        .frame(width: 214, height: 108, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous)
                .fill(fill)
        )
        .scaleEffect(hovered ? 1.012 : 1)
        .shadow(color: .black.opacity(hovered ? 0.10 : 0),
                radius: hovered ? 10 : 0, y: hovered ? 4 : 0)
        .animation(GaltDesign.Motion.hover(reduceMotion), value: hovered)
        .onHover { hovered = $0 }
    }
}

/// 概览页「最近的转录内容」单行（对照 Figma node 652:2223）：
/// 时间戳 + 单行文本 + 应用彩色标签；悬停高亮描边并浮出复制按钮。
struct RecentTranscriptRow: View {
    let record: HistoryRecord
    @State private var hovering = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scrollIsActive) private var scrollIsActive

    /// 应用名 → 彩色标签（与历史页同一套哈希映射，保证同一应用同色）
    private var tag: (bg: Color, fg: Color) {
        let tags: [(Color, Color)] = [
            (Palette.tagBlueBg, Palette.tagBlueFg),
            (Palette.tagTealBg, Palette.tagTealFg),
            (Palette.tagVioletBg, Palette.tagVioletFg),
            (Palette.tagAmberBg, Palette.tagAmberFg),
            (Palette.tagRoseBg, Palette.tagRoseFg),
            (Palette.tagGreenBg, Palette.tagGreenFg),
        ]
        var hash = 0
        for scalar in (record.app ?? "").unicodeScalars { hash = (hash &* 31 &+ Int(scalar.value)) & 0xFFFF }
        return tags[hash % tags.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: GaltDesign.Spacing.sm) {
            Text(GaltTimeFormat.time.string(from: record.date))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
                .frame(width: 63, alignment: .leading)
                .padding(.top, GaltDesign.Spacing.xxxs) // 与首行文字光学对齐的微调

            VStack(alignment: .leading, spacing: GaltDesign.Spacing.sm) {
                Text(record.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: GaltDesign.Spacing.xs) {
                    Circle().fill(tag.fg).frame(width: 4, height: 4)
                    Text(record.app ?? "未知应用")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(tag.fg)
                }
                .padding(.horizontal, GaltDesign.Spacing.xs)
                .padding(.vertical, GaltDesign.Spacing.xxxs)
                .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.sm, style: .continuous).fill(tag.bg))
            }

            Spacer(minLength: 56)
        }
        .padding(.horizontal, 15)
        .frame(height: 72) // 内容垂直居中，上下间距一致
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous)
            .fill(hovering ? Palette.stateHover : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous)
            .strokeBorder(hovering ? Palette.borderHover : Palette.borderSubtle, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(copied ? Palette.success : Palette.textSecondary)
            }
            .buttonStyle(IconButtonStyle())
            .padding(.top, 11)
            .padding(.trailing, 11)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .contentShape(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous))
        // 滚动时内容从静止光标下滑过会误触 onHover，这里屏蔽；滚动一起即收起高亮
        .onHover { if !scrollIsActive { hovering = $0 } }
        .onChange(of: scrollIsActive) { active in if active { hovering = false } }
        .animation(GaltDesign.Motion.hover(reduceMotion), value: hovering)
        .contextMenu {
            Button("复制文本") { copy() }
        }
        .accessibilityElement(children: .combine)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

/// 应用占比一段：value 为计数，环内按计数归一化。
struct DonutSegment: Identifiable {
    let name: String
    let value: Double
    let color: Color
    var id: String { name }
}

/// 概览页应用占比的一行数据（环形与图例共用）。
struct AppUsageSlice: Identifiable {
    let name: String
    let share: Double
    let count: Int
    let color: Color
    var id: String { name }
}

/// 环形图：按计数绘制各段圆环；支持悬停高亮（与图例共享 `highlighted`）。
/// 悬停某段：该段加粗、其余降淡，环心切换显示「名称 + 占比% + 次数」；离开恢复默认标题。
struct DonutChart: View {
    let segments: [DonutSegment]
    @Binding var highlighted: String?
    /// 无高亮时环心副标题（如「近 7 天」）
    var centerCaption: String = ""
    var lineWidth: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let growth: CGFloat = 4 // 高亮段加粗量

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
        GeometryReader { geo in
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
                    let start = segments[0..<index].reduce(0) { $0 + $1.value } / total
                    let end = start + seg.value / total
                    let isOn = highlighted == seg.name
                    let dim = highlighted != nil && !isOn
                    Circle()
                        .trim(from: start, to: end)
                        .stroke(seg.color,
                                style: StrokeStyle(lineWidth: isOn ? lineWidth + growth : lineWidth, lineCap: .butt))
                        .opacity(dim ? 0.35 : 1)
                        .rotationEffect(.degrees(-90))
                        .padding(lineWidth / 2 + growth / 2)
                }
                centerLabel(total: total)
            }
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    highlighted = segmentName(at: point, in: geo.size, total: total)
                case .ended:
                    highlighted = nil
                }
            }
            .animation(GaltDesign.Motion.highlight(reduceMotion), value: highlighted)
        }
    }

    @ViewBuilder
    private func centerLabel(total: Double) -> some View {
        VStack(spacing: GaltDesign.Spacing.xxxs) {
            if let name = highlighted, let seg = segments.first(where: { $0.name == name }) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(Int((seg.value / total * 100).rounded()))% · \(Int(seg.value)) 次")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
            } else {
                if !centerCaption.isEmpty {
                    Text(centerCaption)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text("\(Int(total)) 次")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 96)
    }

    /// 把光标坐标换算成「角度 + 半径」，命中圆环带内时返回所在段名称，否则 nil。
    private func segmentName(at point: CGPoint, in size: CGSize, total: Double) -> String? {
        let cx = size.width / 2, cy = size.height / 2
        let dx = point.x - cx, dy = point.y - cy
        let radius = (dx * dx + dy * dy).squareRoot()
        let side = min(size.width, size.height)
        // 圆环带（含少量松弛，便于命中）
        let outer = side / 2 + 4
        let inner = side / 2 - lineWidth - growth - 8
        guard radius <= outer, radius >= inner else { return nil }
        // 自顶部顺时针的比例（与 rotationEffect(-90) 对齐）
        var fraction = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
        if fraction < 0 { fraction += 1 }
        var acc = 0.0
        for seg in segments {
            let next = acc + seg.value / total
            if fraction >= acc && fraction < next { return seg.name }
            acc = next
        }
        return segments.last?.name
    }
}

// MARK: - 历史页

struct HistoryPage: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all, dictation, ask

        var id: Filter { self }

        var title: String {
            switch self {
            case .all: return "全部"
            case .dictation: return "听写"
            case .ask: return "问任何问题"
            }
        }

        var width: CGFloat {
            switch self {
            case .all, .dictation: return 48
            case .ask: return 84
            }
        }
    }

    @State private var records: [HistoryRecord] = []
    @State private var query = ""
    @State private var filter: Filter = .all
    /// 记忆化的分组结果：仅在 records / 搜索词 / 过滤项变化时重算，避免每次 body 求值都分组排序
    @State private var grouped: [(title: String, records: [HistoryRecord])] = []
    /// 分步加载：当前展示的记录条数上限；滚动到底部自动加大一页
    @State private var displayLimit = 40
    /// 是否还有未展示的记录（决定要不要渲染「加载更多」哨兵）
    @State private var hasMore = false
    /// 每页加载条数
    private let pageSize = 40
    /// 「语音输入」快捷键展示文案，随设置变更刷新
    @State private var dictationHint = HotkeyCombo.dictationDisplay
    @AppStorage("historyRetentionDays") private var retentionDays = 0
    @AppStorage("storeAudioInHistory") private var storeAudio = false

    private var retentionLabel: String {
        retentionDays == 0 ? "永远" : "\(retentionDays) 天"
    }

    private func setRetention(_ days: Int) {
        retentionDays = days
        HistoryStore.shared.pruneExpired()
        reload()
    }

    /// 重算分组（按 records + 搜索 + 过滤），只对「当前展示窗口」(displayLimit) 内的记录分组。
    /// 分步加载：每次只分组排序一小批，主线程开销恒定且很小；滚动到底再加大窗口。
    /// 只在 reload / 搜索 / 过滤 / 加载更多时调用，而非每次 body 求值。
    private func rebuildGroups() {
        let source: [HistoryRecord]
        switch filter {
        case .all, .dictation:
            source = records
        case .ask:
            source = []
        }
        let matched: [HistoryRecord]
        if query.isEmpty {
            matched = source
        } else {
            matched = source.filter {
                $0.text.localizedCaseInsensitiveContains(query)
                    || $0.raw.localizedCaseInsensitiveContains(query)
                    || ($0.app ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        hasMore = matched.count > displayLimit
        let visible = matched.count > displayLimit ? Array(matched.prefix(displayLimit)) : matched
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.date) }
        grouped = groups.keys.sorted(by: >).map { day in
            (historyGroupTitle(for: day), groups[day]?.sorted { $0.date > $1.date } ?? [])
        }
    }

    /// 滚动到底部哨兵出现时调用：加大展示窗口一页，重算分组（追加下一批）
    private func loadMore() {
        guard hasMore else { return }
        displayLimit += pageSize
        rebuildGroups()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("历史")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(height: 28, alignment: .leading)

                historySettings
                    .padding(.top, 19)

                filterControl
                    .padding(.top, GaltDesign.Spacing.lg)
            }
            .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
            .padding(.top, GaltDesign.Spacing.xl)
            .padding(.horizontal, GaltDesign.Spacing.xl)
            // 与概览一致：904 内容在面板内水平居中（内层 cap 仍 topLeading，使文字/卡片在 904 内左排）
            .frame(maxWidth: .infinity, alignment: .top)

            // 内容铺满面板、且面板有 16pt 圆角：滚动条右侧留白、底部避开圆角
            BrandScrollView(scrollbarInset: EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 6)) {
                timeline
                    .padding(.top, 23)
                    .padding(.bottom, GaltDesign.Spacing.xl)
                    .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
                    .padding(.horizontal, GaltDesign.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(ConsoleDesign.panelBackground)
        .onAppear {
            reload()
            dictationHint = HotkeyCombo.dictationDisplay
        }
        .onChange(of: query) { _ in displayLimit = pageSize; rebuildGroups() }
        .onChange(of: filter) { _ in displayLimit = pageSize; rebuildGroups() }
        .onReceive(NotificationCenter.default.publisher(for: .galtHistoryChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .galtHotkeysChanged)) { _ in
            dictationHint = HotkeyCombo.dictationDisplay
        }
    }

    private var historySettings: some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.lg) {
            HStack(alignment: .center, spacing: GaltDesign.Spacing.xl) {
                historySettingText(
                    title: "保存历史",
                    subtitle: "您希望在设备上保存口述历史多久？"
                )
                Spacer(minLength: 24)
                Menu {
                    Button("永久保留") { setRetention(0) }
                    Button("30 天") { setRetention(30) }
                    Button("14 天") { setRetention(14) }
                    Button("7 天") { setRetention(7) }
                } label: {
                    HStack(spacing: 0) {
                        Text(retentionLabel)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .padding(.horizontal, 11)
                    .frame(width: 128, height: 28)
                    // 无填充，透出面板底色；描边随 hover 加深。
                    // 作为下拉控件，描边用 borderDefault，与 DropdownPicker 一致（容器才用默认的 borderSubtle）。
                    .modifier(HoverBorderBox(idleBorder: Palette.borderDefault))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 48)

            HStack(alignment: .center, spacing: GaltDesign.Spacing.xl) {
                historySettingText(
                    title: "保存音频",
                    subtitle: "随历史一并在本机保存录音，便于回放与重新转写；占用磁盘，随历史超期一并清理。"
                )
                Spacer(minLength: 24)
                Toggle("", isOn: $storeAudio)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Palette.primary)
            }
            .frame(height: 48)

            historySettingText(
                title: "您的数据保持私密",
                subtitle: "您的语音口述是私密的，零数据保留。它们仅存储在您的设备上，无法从其他地方访问。"
            )
            .frame(height: 48, alignment: .leading)
        }
    }

    private func historySettingText(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(height: 22, alignment: .leading)
            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(height: 22, alignment: .leading)
        }
    }

    private var filterControl: some View {
        HStack(spacing: GaltDesign.Spacing.xxs) {
            ForEach(Filter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .frame(width: item.width, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                                .fill(filter == item ? Palette.surfaceRaised : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                                .strokeBorder(filter == item ? Palette.borderSubtle : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(RowButtonStyle(isSelected: filter == item, selectionDrawnExternally: true))
            }
        }
        .padding(GaltDesign.Spacing.xxxs)
        .frame(height: 32)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.track)
        )
    }

    @ViewBuilder
    private var timeline: some View {
        if grouped.isEmpty {
            VStack(spacing: GaltDesign.Spacing.xs) {
                Text(emptyTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(emptyMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            // 惰性渲染：仅滚动到的日期分组才构建行，避免历史很长时切页一次性建完所有行卡顿
            LazyVStack(alignment: .leading, spacing: GaltDesign.Spacing.lg) {
                ForEach(grouped, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 11) {
                        Text(group.title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(height: 16, alignment: .leading)
                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                HistoryTimelineRow(record: record) {
                                    HistoryStore.shared.delete(id: record.id)
                                }
                                if index < group.records.count - 1 {
                                    // 行间分隔线：通栏 border-subtle（对齐 Figma #ededed，无左右内缩）
                                    Rectangle()
                                        .fill(Palette.borderSubtle)
                                        .frame(height: 1)
                                }
                            }
                        }
                        // 每个日期分组为一张圆角描边卡片（无填充，透出面板底色；悬停高亮裁切到圆角内）
                        .clipShape(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous).strokeBorder(Palette.borderSubtle, lineWidth: 1))
                    }
                }
                // 加载更多哨兵：LazyVStack 下，滚动到它才出现 → 触发加载下一批
                if hasMore {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, GaltDesign.Spacing.md)
                        .onAppear { loadMore() }
                }
            }
        }
    }

    private func historyGroupTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        let currentYear = calendar.component(.year, from: Date())
        let year = calendar.component(.year, from: day)
        if currentYear == year {
            return day.formatted(.dateTime.month(.wide).day())
        }
        return day.formatted(.dateTime.year().month(.wide).day())
    }

    private var emptyTitle: String {
        switch filter {
        case .ask: return "暂无提问记录"
        default: return query.isEmpty ? "还没有听写记录" : "没有匹配的记录"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .ask: return "用「随便问」热键提问，回答会记录在这里。"
        default: return query.isEmpty ? "按住 \(dictationHint) 开始第一段听写。" : "换个关键词再试试。"
        }
    }

    private func reload() {
        records = HistoryStore.shared.all()
        rebuildGroups()
    }
}

struct HistoryTimelineRow: View {
    let record: HistoryRecord
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var expanded = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let mutedColor = Palette.textSecondary
    private var hasRaw: Bool { !record.raw.isEmpty && record.raw != record.text }

    var body: some View {
        HStack(alignment: .top, spacing: GaltDesign.Spacing.sm) {
            Text(GaltTimeFormat.time.string(from: record.date))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(mutedColor)
                .monospacedDigit()
                .frame(width: 63, height: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
                Text(record.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(expanded ? nil : 2)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .textSelection(.enabled)
                if expanded && hasRaw {
                    Text("原始转写：\(record.raw)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(mutedColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, GaltDesign.Spacing.lg)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        // 整行悬停高亮，强化「可点开 / 可操作」的反馈
        .background(hovering ? ConsoleDesign.subtleFill : Color.clear)
        // 操作按钮作为右上浮层，不占据正文宽度（正文保持 Figma 的 801）
        .overlay(alignment: .topTrailing) {
            rowActions
                .padding(.trailing, GaltDesign.Spacing.lg)
                .padding(.vertical, 15)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .animation(GaltDesign.Motion.hover(reduceMotion), value: hovering)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasRaw else { return }
            withAnimation(GaltDesign.Motion.expand(reduceMotion)) { expanded.toggle() }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("复制成稿文本") { copy(record.text) }
            if hasRaw {
                Button("复制原始转写") { copy(record.raw) }
            }
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private var rowActions: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            if hasRaw {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Button {
                copy(record.text)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .regular))
            }
            .buttonStyle(IconButtonStyle())
            .foregroundStyle(copied ? Palette.success : Palette.textSecondary)
            .help("复制成稿文本")
            .accessibilityLabel(copied ? "已复制" : "复制成稿文本")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .regular))
            }
            .buttonStyle(IconButtonStyle())
            .foregroundStyle(.secondary)
            .help("删除这条记录")
            .accessibilityLabel("删除这条记录")
        }
    }

    private func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

// MARK: - 历史行（概览与历史页共用）

struct HistoryRow: View {
    let record: HistoryRecord
    var onDelete: (() -> Void)?
    @State private var expanded = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.xs) {
            HStack(spacing: GaltDesign.Spacing.sm) {
                Text(record.app ?? "未知应用")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, GaltDesign.Spacing.sm)
                    .padding(.vertical, GaltDesign.Spacing.xxxs)
                    .background(Capsule().fill(badge.bg))
                    .foregroundStyle(badge.fg)
                Text(GaltTimeFormat.monthDayTime.string(from: record.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if record.raw != record.text {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .help(expanded ? "收起原始转写" : "展开原始转写")
                        .accessibilityHidden(true) // 整行可点展开，箭头仅为视觉提示
                }
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(record.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(IconButtonStyle())
                .help("复制成稿文本")
                .accessibilityLabel(copied ? "已复制" : "复制成稿文本")
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("删除这条记录")
                    .accessibilityLabel("删除这条记录")
                }
            }
            Text(record.text)
                .font(.system(size: 13))
                .lineLimit(expanded ? nil : 2)
                .textSelection(.enabled)
            if expanded && record.raw != record.text {
                Text("原始转写：\(record.raw)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, GaltDesign.Spacing.md)
        .padding(.vertical, GaltDesign.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(GaltDesign.Motion.expand(reduceMotion)) { expanded.toggle() }
        }
    }

    /// 分类标签配色：取自 Palette 标签色板（柔和色相，避开语义红 / 绿），按 app 名稳定哈希
    private var badge: (bg: Color, fg: Color) {
        let tags: [(Color, Color)] = [
            (Palette.tagBlueBg, Palette.tagBlueFg),
            (Palette.tagTealBg, Palette.tagTealFg),
            (Palette.tagVioletBg, Palette.tagVioletFg),
            (Palette.tagAmberBg, Palette.tagAmberFg),
            (Palette.tagRoseBg, Palette.tagRoseFg),
            (Palette.tagGreenBg, Palette.tagGreenFg),
        ]
        var hash = 0
        for scalar in (record.app ?? "").unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) & 0xFFFF
        }
        return tags[hash % tags.count]
    }
}

// MARK: - 词典页

struct DictionaryPage: View {
    private enum TermFilter: String, CaseIterable, Identifiable {
        case all, automatic, manual

        var id: TermFilter { self }

        var title: String {
            switch self {
            case .all: return "全部"
            case .automatic: return "自动添加"
            case .manual: return "手动添加"
            }
        }

    }

    /// 仅供快照/预览预填词条
    var seedTerms: [String]? = nil
    /// 请求打开「添加新词」模态——由根视图 ConsoleView 在整窗层呈现（保证全局遮罩）
    var onRequestAddTerm: () -> Void = {}

    @AppStorage("dictionaryTermsText") private var termsText = ""
    @State private var filter: TermFilter = .all
    private let termIconStroke = StrokeStyle(lineWidth: 1.333, lineCap: .round, lineJoin: .round)
    @State private var searchQuery = ""
    @State private var isSearching = false
    /// learnedTerms 非 @AppStorage 可观测，删词后自增此值强制刷新
    @State private var learnedRefresh = 0

    // Figma 设计令牌
    private let titleColor = Palette.textPrimary
    private let mutedColor = Palette.textSecondary
    private let segmentBackground = Palette.track
    private let hairline = Palette.borderSubtle
    private let addButtonFill = Palette.primary

    private var terms: [String] {
        if let seedTerms { return seedTerms }
        return termsText
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 自动学习的词（预览/快照态不取真实数据）
    private var automaticTerms: [String] {
        _ = learnedRefresh // 建立刷新依赖
        return seedTerms == nil ? SettingsStore.shared.learnedTerms : []
    }

    private var filteredTerms: [String] {
        let source: [String]
        switch filter {
        case .all:
            var seen = Set<String>()
            source = (terms + automaticTerms).filter { seen.insert($0).inserted }
        case .manual:
            source = terms
        case .automatic:
            source = automaticTerms
        }

        guard !searchQuery.isEmpty else { return source }
        return source.filter { $0.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var chipIcon: String {
        filter == .automatic ? "sparkles" : "pencil.line"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                dictionaryHeader

                dictionaryToolbar
                    .padding(.top, GaltDesign.Spacing.lg)
            }
            .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
            .padding(.top, GaltDesign.Spacing.xl)
            .padding(.horizontal, GaltDesign.Spacing.xl)
            // 与概览一致：904 内容在面板内水平居中（内层 cap 仍 topLeading，使文字/卡片在 904 内左排）
            .frame(maxWidth: .infinity, alignment: .top)

            // 与历史页一致：滚动条右侧留白、底部避开面板圆角
            BrandScrollView(scrollbarInset: EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 6)) {
                Group {
                    if filteredTerms.isEmpty {
                        emptyDictionaryState
                            .padding(.top, 72)
                    } else {
                        dictionaryGrid
                    }
                }
                .padding(.top, GaltDesign.Spacing.lg)
                .padding(.bottom, GaltDesign.Spacing.xl)
                .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
                .padding(.horizontal, GaltDesign.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(ConsoleStyle.panelBackground)
    }

    private var dictionaryHeader: some View {
        HStack(alignment: .center, spacing: GaltDesign.Spacing.lg) {
            Text("词典")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(titleColor)
                .frame(height: 28, alignment: .leading)
            Spacer(minLength: 0)
            Button {
                onRequestAddTerm()
            } label: {
                Text("添加词语")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.onPrimary)
                    .padding(.horizontal, GaltDesign.Spacing.md)
                    .frame(height: 28)
            }
            .buttonStyle(FilledButtonStyle(fill: addButtonFill))
            .help("添加新词")
        }
    }

    private var dictionaryToolbar: some View {
        HStack(alignment: .center, spacing: GaltDesign.Spacing.lg) {
            filterControl
            Spacer(minLength: 0)
            searchControl
        }
        .frame(height: 32)
    }

    private var filterControl: some View {
        HStack(spacing: GaltDesign.Spacing.xxs) {
            ForEach(TermFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    HStack(spacing: GaltDesign.Spacing.xxs) {
                        if item != .all {
                            Group {
                                if item == .automatic {
                                    AutoAddShape().stroke(style: termIconStroke)
                                } else {
                                    ManualAddShape().stroke(style: termIconStroke)
                                }
                            }
                            .foregroundStyle(titleColor)
                            .frame(width: 16, height: 16)
                        }
                        Text(item.title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, GaltDesign.Spacing.md)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                            .fill(filter == item ? Palette.surfaceRaised : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                            .strokeBorder(filter == item ? hairline : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(RowButtonStyle(isSelected: filter == item, selectionDrawnExternally: true))
            }
        }
        .padding(GaltDesign.Spacing.xxxs)
        .frame(height: 32)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(segmentBackground)
        )
    }

    @ViewBuilder
    private var searchControl: some View {
        if isSearching {
            HStack(spacing: GaltDesign.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                TextField("搜索词汇", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Button {
                    searchQuery = ""
                    isSearching = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(IconButtonStyle(cornerRadius: 5, padding: 2))
                .accessibilityLabel("关闭搜索")
            }
            .padding(.horizontal, 10)
            .frame(width: 240, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(segmentBackground)
            )
        } else {
            Button {
                isSearching = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(titleColor)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(IconButtonStyle(cornerRadius: 10, padding: 0))
            .help("搜索")
            .accessibilityLabel("搜索词汇")
        }
    }

    private var emptyDictionaryState: some View {
        VStack(spacing: GaltDesign.Spacing.sm) {
            Text(emptyDictTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(titleColor)
            Text(emptyDictMessage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(mutedColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    /// 空态标题：搜索无结果 / 自动学习标签 / 完全为空 三种语义分开
    private var emptyDictTitle: String {
        if !searchQuery.isEmpty { return "没有匹配的词汇" }
        if filter == .automatic { return "还没有自动学习的词汇" }
        return "还没有词汇"
    }

    private var emptyDictMessage: String {
        if !searchQuery.isEmpty { return "换个关键词再试试。" }
        if filter == .automatic { return "Galt 会从您的编辑中自动学习独特的名称和术语，学到的词会出现在这里。" }
        return "Galt 会记住您独特的名称和术语，通过您的编辑自动学习，或由您手动添加。"
    }

    private var dictionaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 214, maximum: 214), spacing: GaltDesign.Spacing.lg, alignment: .topLeading)],
            alignment: .leading,
            spacing: GaltDesign.Spacing.lg
        ) {
            ForEach(filteredTerms, id: \.self) { term in
                DictionaryTermChip(term: term, icon: chipIcon, hairline: hairline, textColor: titleColor) {
                    remove(term)
                }
            }
        }
    }

    private func remove(_ term: String) {
        // 自动学习的词从 learnedTerms 移除；手填词从 termsText 移除
        if SettingsStore.shared.learnedTerms.contains(term) {
            SettingsStore.shared.learnedTerms = SettingsStore.shared.learnedTerms.filter { $0 != term }
            learnedRefresh += 1
        } else {
            termsText = terms.filter { $0 != term }.joined(separator: "\n")
        }
    }
}

/// 全局「添加新词」模态：半透明遮罩铺满整窗 + 自定义圆角卡片。
/// 不用系统 `.sheet`——macOS 上它是 NSWindow，圆角压不到设计值；
/// 也不挂在词典 pane 上——那样遮罩盖不住侧栏，不是真正的全局模态。
/// 词库走同一个 `@AppStorage` 键，写入后词典列表自动同步。
private struct AddTermDialog: View {
    var onClose: () -> Void
    @AppStorage("dictionaryTermsText") private var termsText = ""
    @State private var newTerm = ""

    private var terms: [String] {
        termsText
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
            card
                .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("添加新词")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            TextField("专有名词、人名或行业术语", text: $newTerm)
                .textFieldStyle(.plain)
                .onSubmit { commit() }
                .modifier(FormFieldBox(autoFocus: true))

            HStack(spacing: 10) {
                Spacer()
                Button { close() } label: {
                    Text("取消")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, GaltDesign.Spacing.lg)
                        .frame(height: 32)
                }
                .buttonStyle(OutlineButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button { commit() } label: {
                    Text("添加")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.onPrimary)
                        .padding(.horizontal, GaltDesign.Spacing.lg)
                        .frame(height: 32)
                }
                .buttonStyle(FilledButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(GaltDesign.Spacing.xl)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous)
                .fill(Palette.surfaceCard)
        )
        .clipShape(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous))
    }

    private func commit() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !terms.contains(term) else { return }
        termsText = (terms + [term]).joined(separator: "\n")
        close()
    }

    private func close() {
        newTerm = ""
        onClose()
    }
}

/// 词典词条 chip：214×32 描边胶囊；悬停时显示删除，右键菜单亦可删除
private struct DictionaryTermChip: View {
    let term: String
    let icon: String
    let hairline: Color
    let textColor: Color
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(textColor.opacity(0.75))
                .frame(width: 16, height: 16)
            Text(term)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(IconButtonStyle(cornerRadius: 5, padding: 2))
                .help("删除「\(term)」")
                .accessibilityLabel("删除词条 \(term)")
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, GaltDesign.Spacing.sm)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                .fill(hovering ? Palette.stateHover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                .strokeBorder(hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous))
        .contextMenu {
            Button("删除", role: .destructive, action: onDelete)
        }
        .onHover { hovering = $0 }
    }
}

#if DEBUG
#Preview("Console") {
    ConsoleView(navigation: ConsoleNavigation()) { _ in }
        .frame(width: 1200, height: 800)
}
#endif
