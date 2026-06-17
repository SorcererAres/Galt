import AppKit
import SwiftUI

enum ConsoleDesign {
    static let outerInset: CGFloat = 8
    static let sidebarWidth: CGFloat = 232
    static let sidebarBackground = Palette.surfaceCanvas
    static let panelBackground = Palette.surfacePanel
    static let contentBackground = Palette.surfacePanel
    static let cardBackground = Palette.surfaceCard
    static let fieldBackground = Color(nsColor: .textBackgroundColor)
    static let subtleFill = Color.primary.opacity(0.05)
    // 主操作色：用 teal-600 —— 既是规范「浅底青绿文字/图标」色，又保证白字按钮 ≈3.8:1 过 AA。
    // teal-500 (Palette.primary) 留给纯色块场景（选中态、图表高亮、进度条等无小字处）。
    static let primaryControl = Palette.primary
    static let selectedFill = Palette.selectionFill
    static let border = Palette.borderDefault
    static let primaryControlText = Palette.textOnColor
    static let sidebarRowHeight: CGFloat = 32
    static let sidebarRowRadius: CGFloat = 8
    static let sidebarIconSize: CGFloat = 14
    static let sidebarIconWidth: CGFloat = 18
    static let sidebarTextSize: CGFloat = 14
    static let sidebarHorizontalPadding: CGFloat = 10
    static let panelCornerRadius: CGFloat = 16
    static let homeContentWidth: CGFloat = 904
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

/// 控制台主窗口（菜单栏 → 打开控制台）
final class ConsoleWindowController {
    static let shared = ConsoleWindowController()
    private let navigation = ConsoleNavigation(route: ConsoleRoute.initialRoute)
    private var window: NSWindow?

    func show(route: ConsoleRoute = .primary(.overview)) {
        navigation.navigate(to: route)
        if window == nil {
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            let w = NSWindow(
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
            w.contentMinSize = route.minimumContentSize
            w.contentView = NSHostingView(rootView: ConsoleView(navigation: navigation) { [weak self] route in
                self?.applyWindowMetrics(for: route)
            })
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
        window.contentMinSize = route.minimumContentSize
        if let frameSize = route.frameSize {
            window.setFrame(NSRect(origin: window.frame.origin, size: frameSize), display: true)
        } else {
            window.setContentSize(route.contentSize)
        }
        window.center()
    }

    func show(page: ConsolePrimaryPage) {
        show(route: .primary(page))
    }

    func showOnboarding() {
        show(route: .onboarding)
    }
}

final class ConsoleNavigation: ObservableObject {
    @Published private(set) var route: ConsoleRoute
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
        #if DEBUG
        switch ProcessInfo.processInfo.environment["GALT_CONSOLE_PAGE"] {
        case "history": return .primary(.history)
        case "dictionary": return .primary(.dictionary)
        case "settings": return .settings
        case "onboarding": return .onboarding
        default: return .overviewOrOnboarding
        }
        #else
        return .overviewOrOnboarding
        #endif
    }

    private static var overviewOrOnboarding: ConsoleRoute {
        SettingsStore.shared.hasCompletedOnboarding ? .primary(.overview) : .onboarding
    }

    var primaryPage: ConsolePrimaryPage? {
        if case let .primary(page) = self { return page }
        return nil
    }

    var contentSize: NSSize {
        switch self {
        case .onboarding:
            return NSSize(width: 480, height: 560)
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
            return NSSize(width: 480, height: 600)
        case .primary, .settings:
            return nil
        }
    }

    var minimumContentSize: NSSize {
        switch self {
        case .onboarding:
            return NSSize(width: 420, height: 520)
        case .primary, .settings:
            return NSSize(width: 960, height: 620)
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

    var icon: String {
        switch self {
        case .overview: return "waveform"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        }
    }
}

struct ConsoleView: View {
    @ObservedObject var navigation: ConsoleNavigation
    let onRouteMetricsChange: (ConsoleRoute) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 大区切换（主界面 ⇄ 设置 ⇄ 引导）：进入用 ease-out 淡入
    private var routeAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }
    /// 一级页切换与侧栏选中：平滑无回弹弹簧，让选中胶囊滑动 + 内容淡入一气呵成
    private var pageAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)
    }

    var body: some View {
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
    }

    private var contentPanel: some View {
        ZStack {
            // 稳定的面板底色：切换页时只让内容淡入淡出，避免出现空隙闪白
            ConsoleDesign.panelBackground
            Group {
                switch navigation.primarySelection {
                case .overview: OverviewPage()
                case .history: HistoryPage()
                case .dictionary: DictionaryPage()
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
                        systemImage: page.icon,
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
            .buttonStyle(.plain)
            .padding(.horizontal, ConsoleDesign.sidebarHorizontalPadding)
            .padding(.bottom, 8)
        }
        // 不铺实心底色——透出窗口画布的毛玻璃
    }
}

struct ConsoleSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ConsoleSidebarRowContent(title: title, systemImage: systemImage, isSelected: isSelected, namespace: namespace)
        }
        .buttonStyle(.plain)
    }
}

struct ConsoleSidebarRowContent: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: ConsoleDesign.sidebarIconSize, weight: .regular))
                .frame(width: ConsoleDesign.sidebarIconWidth, height: 16)
            Text(title)
                .font(.system(size: ConsoleDesign.sidebarTextSize, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.textPrimary)
        .frame(height: ConsoleDesign.sidebarRowHeight)
        .padding(.leading, 8)
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
        HStack(spacing: 6) {
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
        .frame(height: 24)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .contentShape(RoundedRectangle(cornerRadius: ConsoleDesign.sidebarRowRadius, style: .continuous))
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ConsoleDesign.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ConsoleStyle.border, lineWidth: 1)
        )
    }
}

struct ConsoleEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
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
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ConsoleStyle.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ConsoleStyle.border, lineWidth: 1)
        )
    }
}

// MARK: - 概览页

struct OverviewPage: View {
    @AppStorage("polishEnabled") private var polishEnabled = true
    @State private var records: [HistoryRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Galt")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(height: 28, alignment: .leading)

                Text("Speak. The mind does the rest.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(height: 24, alignment: .leading)
                    .padding(.top, 4)

                metricsGrid
                    .padding(.top, 20)

                HStack(spacing: 16) {
                    chartSection
                    personalizationSection
                }
                .padding(.top, 16)

                recentSection
                    .padding(.top, 15)
            }
            .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .leading)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ConsoleStyle.panelBackground)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .galtHistoryChanged)) { _ in reload() }
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
        HStack(spacing: 16) {
            metric("总字数", subtitle: "所有时间使用", value: "\(totalWords)", fill: Palette.softTeal)
            metric("今日字数", subtitle: "今天已输出", value: "\(todayWords)", fill: Palette.softAmber)
            metric("使用时间", subtitle: "累计听写时长", value: "\(totalMinutes)", unit: "min", fill: Palette.softSky)
            metric("累计听写", subtitle: "所有会话", value: "\(records.count)", unit: "次", fill: Palette.softRose)
        }
    }

    private func metric(_ title: String, subtitle: String, value: String, unit: String? = nil, fill: Color) -> some View {
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
        .padding(12)
        .frame(width: 214, height: 108, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
        )
    }

    // MARK: 近 7 天柱状图

    private struct DayValue: Identifiable {
        let day: Date
        let seconds: Double
        var id: Date { day }
    }

    /// 近 7 天每日听写时长（秒），最旧在前
    private var dailyTime: [DayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]
        for record in records {
            byDay[calendar.startOfDay(for: record.date), default: 0] += record.duration
        }
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayValue(day: day, seconds: byDay[day] ?? 0)
        }
    }

    private var maxDailySeconds: Double { dailyTime.map(\.seconds).max() ?? 0 }

    /// 指定「几周前」的整周听写总时长（0 = 本周近 7 天，1 = 前 7 天）
    private func weekSeconds(weeksAgo: Int) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(weeksAgo * 7 + 6), to: today),
              let end = calendar.date(byAdding: .day, value: -(weeksAgo * 7) + 1, to: today) else { return 0 }
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

    /// 各前台 App 的使用占比：取用量前 3 + 其他，配 soft 色板
    private var appUsage: [(name: String, share: Double, color: Color)] {
        guard !records.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for record in records { counts[record.app ?? "其他", default: 0] += 1 }
        let total = Double(records.count)
        let sorted = counts.sorted { $0.value > $1.value }
        let colors = [Palette.softTeal, Palette.softAmber, Palette.softSky, Palette.softRose]
        var result: [(String, Double, Color)] = []
        for (index, entry) in sorted.prefix(3).enumerated() {
            result.append((entry.key, Double(entry.value) / total, colors[index]))
        }
        let othersCount = sorted.dropFirst(3).reduce(0) { $0 + $1.value }
        if othersCount > 0 {
            result.append(("其他", Double(othersCount) / total, colors[3]))
        }
        return result
    }

    private func weekdayLabel(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date) // 1=周日
        return ["日", "一", "二", "三", "四", "五", "六"][(weekday - 1) % 7]
    }

    // 生产力趋势：左侧周总时长 + 环比徽标，右侧带星期轴的柱图
    private var chartSection: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("生产力趋势")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("每日听写时间")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, 12)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(weeklyTotalLabel)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.textDisplay)
                    .monospacedDigit()
                Text("本周")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, 12)
            .padding(.top, 61)

            weeklyChangeBadge
                .padding(.leading, 13)
                .padding(.top, 123)

            productivityBars
                .frame(width: 292, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 444, height: 167, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surfaceCard))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
    }

    private var productivityBars: some View {
        let maxV = max(maxDailySeconds, 1)
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(dailyTime) { d in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(barColor(d.seconds))
                        .frame(width: 24, height: barHeight(d.seconds, max: maxV))
                }
            }
            .frame(height: 101, alignment: .bottom)
            HStack(spacing: 16) {
                ForEach(dailyTime) { d in
                    Text(weekdayLabel(d.day))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 24)
                }
            }
        }
        .padding(.top, 25)
        .padding(.trailing, 12)
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
                    .padding(.horizontal, 24)
            } else {
                HStack(spacing: 0) {
                    DonutChart(segments: appUsage.map { ($0.share, $0.color) })
                        .frame(width: 120, height: 120)
                        .padding(.leading, 24)
                    Spacer(minLength: 16)
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(appUsage.indices, id: \.self) { i in
                            usageLegendRow(appUsage[i])
                        }
                    }
                    .frame(width: 200)
                    .padding(.trailing, 28)
                }
            }
        }
        .frame(width: 444, height: 167)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surfaceCard))
    }

    private func usageLegendRow(_ usage: (name: String, share: Double, color: Color)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(usage.name)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
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
    }

    private func dashboardCard<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ConsoleDesign.cardBackground)
        )
    }

    // MARK: 最近听写

    private var recentSection: some View {
        dashboardCard(width: ConsoleDesign.homeContentWidth, height: 358) {
            Text("最近的转录内容")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(height: 22, alignment: .leading)

            if records.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text("还没有听写记录，按住 fn 试试。")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.prefix(4).enumerated()), id: \.element.id) { index, record in
                        HistoryRow(record: record)
                        if index < min(records.count, 4) - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
    }
}

/// 环形图：按占比绘制各段圆环（对照设计稿应用占比图）
struct DonutChart: View {
    let segments: [(value: Double, color: Color)]
    var lineWidth: CGFloat = 22

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
        ZStack {
            ForEach(segments.indices, id: \.self) { i in
                let start = segments[0..<i].reduce(0) { $0 + $1.value } / total
                let end = start + segments[i].value / total
                Circle()
                    .trim(from: start, to: end)
                    .stroke(segments[i].color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
            }
        }
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
    @AppStorage("historyRetentionDays") private var retentionDays = 0

    private var retentionLabel: String {
        retentionDays == 0 ? "永远" : "\(retentionDays) 天"
    }

    private func setRetention(_ days: Int) {
        retentionDays = days
        HistoryStore.shared.pruneExpired()
        reload()
    }

    private var filtered: [HistoryRecord] {
        let source: [HistoryRecord]
        switch filter {
        case .all, .dictation:
            source = records
        case .ask:
            source = []
        }

        guard !query.isEmpty else { return source }
        return source.filter {
            $0.text.localizedCaseInsensitiveContains(query)
                || $0.raw.localizedCaseInsensitiveContains(query)
                || ($0.app ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedRecords: [(title: String, records: [HistoryRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { record in
            calendar.startOfDay(for: record.date)
        }
        return groups.keys.sorted(by: >).map { day in
            (historyGroupTitle(for: day), groups[day]?.sorted { $0.date > $1.date } ?? [])
        }
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
                    .padding(.top, 16)
            }
            .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            ScrollView {
                timeline
                    .padding(.top, 23)
                    .padding(.bottom, 24)
                    .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(ConsoleDesign.panelBackground)
        .onAppear {
            HistoryStore.shared.pruneExpired()
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .galtHistoryChanged)) { _ in reload() }
    }

    private var historySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
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
                    // 无填充，透出面板底色；仅留描边
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Palette.borderSubtle, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 4) {
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
        HStack(spacing: 4) {
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
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(filter == item ? Palette.surfaceRaised : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(filter == item ? Palette.borderSubtle : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(height: 32)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.track)
        )
    }

    @ViewBuilder
    private var timeline: some View {
        if filtered.isEmpty {
            VStack(spacing: 6) {
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
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groupedRecords, id: \.title) { group in
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
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.borderSubtle, lineWidth: 1))
                    }
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
        default: return query.isEmpty ? "按住 fn 开始第一段听写。" : "换个关键词再试试。"
        }
    }

    private func reload() {
        records = HistoryStore.shared.all()
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
        HStack(alignment: .top, spacing: 8) {
            Text(record.date.formatted(.dateTime.hour().minute()))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(mutedColor)
                .monospacedDigit()
                .frame(width: 63, height: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        // 整行悬停高亮，强化「可点开 / 可操作」的反馈
        .background(hovering ? ConsoleDesign.subtleFill : Color.clear)
        // 操作按钮作为右上浮层，不占据正文宽度（正文保持 Figma 的 801）
        .overlay(alignment: .topTrailing) {
            rowActions
                .padding(.trailing, 16)
                .padding(.vertical, 15)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasRaw else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { expanded.toggle() }
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
        HStack(spacing: 8) {
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
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Palette.success : Palette.textSecondary)
            .help("复制成稿文本")
            .accessibilityLabel(copied ? "已复制" : "复制成稿文本")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .regular))
            }
            .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(record.app ?? "未知应用")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badge.bg))
                    .foregroundStyle(badge.fg)
                Text(record.date.formatted(.dateTime.month().day().hour().minute()))
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
                .buttonStyle(.borderless)
                .help("复制成稿文本")
                .accessibilityLabel(copied ? "已复制" : "复制成稿文本")
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { expanded.toggle() }
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

        var icon: String? {
            switch self {
            case .all: return nil
            case .automatic: return "sparkles"
            case .manual: return "pencil.line"
            }
        }
    }

    /// 仅供快照/预览预填词条
    var seedTerms: [String]? = nil

    @AppStorage("dictionaryTermsText") private var termsText = ""
    @State private var newTerm = ""
    @State private var filter: TermFilter = .all
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var isAddingTerm = false

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

    private var filteredTerms: [String] {
        let source: [String]
        switch filter {
        case .all, .manual:
            source = terms
        case .automatic:
            source = []
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
                    .padding(.top, 16)
            }
            .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            ScrollView {
                Group {
                    if filteredTerms.isEmpty {
                        emptyDictionaryState
                            .padding(.top, 72)
                    } else {
                        dictionaryGrid
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: ConsoleDesign.homeContentWidth, alignment: .topLeading)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(ConsoleStyle.panelBackground)
        .sheet(isPresented: $isAddingTerm) {
            addTermSheet
        }
    }

    private var dictionaryHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("词典")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(titleColor)
                .frame(height: 28, alignment: .leading)
            Spacer(minLength: 0)
            Button {
                isAddingTerm = true
            } label: {
                Text("添加词语")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.onPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(addButtonFill)
                    )
            }
            .buttonStyle(.plain)
            .help("添加新词")
        }
    }

    private var dictionaryToolbar: some View {
        HStack(alignment: .center, spacing: 16) {
            filterControl
            Spacer(minLength: 0)
            searchControl
        }
        .frame(height: 32)
    }

    private var filterControl: some View {
        HStack(spacing: 4) {
            ForEach(TermFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    HStack(spacing: 4) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(titleColor)
                                .frame(width: 16, height: 16)
                        }
                        Text(item.title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(filter == item ? Palette.surfaceRaised : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(filter == item ? hairline : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
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
            HStack(spacing: 6) {
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
                .buttonStyle(.plain)
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
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(segmentBackground)
                    )
            }
            .buttonStyle(.plain)
            .help("搜索")
            .accessibilityLabel("搜索词汇")
        }
    }

    private var emptyDictionaryState: some View {
        VStack(spacing: 8) {
            Text("还没有词汇")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(titleColor)
            Text("Galt 会记住您独特的名称和术语，通过您的编辑自动学习，或由您手动添加。")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(mutedColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    private var dictionaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 214, maximum: 214), spacing: 16, alignment: .topLeading)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(filteredTerms, id: \.self) { term in
                DictionaryTermChip(term: term, icon: chipIcon, hairline: hairline, textColor: titleColor) {
                    remove(term)
                }
            }
        }
    }

    private var addTermSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加新词")
                .font(.system(size: 22, weight: .bold))
            TextField("专有名词、人名或行业术语", text: $newTerm)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    add()
                    isAddingTerm = false
                }
            HStack {
                Spacer()
                Button("取消") {
                    newTerm = ""
                    isAddingTerm = false
                }
                Button("添加") {
                    add()
                    isAddingTerm = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func add() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !terms.contains(term) else { return }
        termsText = (terms + [term]).joined(separator: "\n")
        newTerm = ""
    }

    private func remove(_ term: String) {
        termsText = terms.filter { $0 != term }.joined(separator: "\n")
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
        HStack(spacing: 8) {
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
                .buttonStyle(.plain)
                .help("删除「\(term)」")
                .accessibilityLabel("删除词条 \(term)")
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.surfaceRaised.opacity(hovering ? 0.6 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
