import AppKit
import SwiftUI
import ServiceManagement

/// 设置作为控制台二级路由呈现，入口统一交给控制台窗口承载。
enum SettingsRouter {
    static func show() {
        ConsoleWindowController.shared.show(route: .settings)
    }
}

enum SettingsSidebarItem: CaseIterable, Identifiable {
    case hotkeys, language, audio, voiceEngine, modelLibrary, general

    var id: SettingsSidebarItem { self }

    var title: String {
        switch self {
        case .hotkeys: return "键盘快捷"
        case .language: return "语言"
        case .audio: return "音频"
        case .voiceEngine: return "语音引擎"
        case .modelLibrary: return "模型库"
        case .general: return "通用"
        }
    }

    var iconKind: SettingsIconShape.Kind {
        switch self {
        case .hotkeys: return .keyboard
        case .language: return .language
        case .audio: return .audio
        case .voiceEngine: return .engine
        case .modelLibrary: return .models
        case .general: return .general
        }
    }
}

/// 设置专属设计常量：尺寸度量统一委托 `GaltDesign`（单一真相来源，与控制台共用同一组数值），
/// 此处仅保留设置语境下的颜色语义别名。
private enum SettingsDesign {
    static let outerInset = GaltDesign.outerInset
    static let sidebarWidth = GaltDesign.sidebarWidth
    static let contentCornerRadius = GaltDesign.panelCornerRadius
    static let contentMaxWidth = GaltDesign.contentWidth
    static let contentTopPadding = GaltDesign.contentTopPadding

    static let windowBackground = Palette.surfaceCanvas
    static let contentBackground = Palette.surfacePanel
    static let contentBorder = Palette.borderDefault
    static let selectedRowFill = Palette.selectionFill
    static let primaryText = Palette.textPrimary
    static let rowTitle = Palette.textPrimary
    static let rowSubtitle = Palette.textSecondary
    static let sectionText = Palette.textPrimary.opacity(0.5)
    static let backText = Palette.textSecondary

    static let sidebarRowHeight = GaltDesign.sidebarRowHeight
    static let sidebarRowRadius = GaltDesign.sidebarRowRadius
    static let sidebarHorizontalPadding = GaltDesign.sidebarHorizontalPadding
    static let sidebarInnerHorizontalPadding = GaltDesign.sidebarInnerHorizontalPadding
    static let sidebarIconWidth = GaltDesign.sidebarIconWidth
    static let sidebarIconSize = GaltDesign.sidebarIconSize
    static let sidebarTextSize = GaltDesign.sidebarTextSize
}

/// 模型库表单输入框样式：36 高、圆角描边盒（对照设计稿）。
/// 三态（全中性，契合单色设计）：默认 borderDefault → 悬停 borderHover + 极淡底 →
/// 聚焦 textTertiary 描边 1.5px + 极淡底（仅描边加深一档表示「已激活」，不引入彩色）。
struct FormFieldBox: ViewModifier {
    /// 出现时是否自动聚焦（如弹窗内的首个输入框）。设置页表单默认不抢焦点。
    var autoFocus: Bool = false
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var border: Color {
        if focused { return Palette.textTertiary }
        if hovering { return Palette.borderHover }
        return Palette.borderDefault
    }
    private var fill: Color {
        (focused || hovering) ? Palette.stateHover : .clear
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .padding(.horizontal, 11)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focused($focused)
            .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                .strokeBorder(border, lineWidth: focused ? 1.5 : 1))
            .onHover { hovering = $0 }
            .onAppear { if autoFocus { DispatchQueue.main.async { focused = true } } }
            .animation(GaltDesign.Motion.hover(reduceMotion), value: hovering)
            .animation(GaltDesign.Motion.hover(reduceMotion), value: focused)
    }
}

/// 密钥输入框：默认隐藏（SecureField），点右侧眼睛切换为明文（TextField）。
/// 样式对齐 FormFieldBox（36 高 / 圆角 8 / 三态描边），焦点绑定到内部输入框，
/// 切换显示态后异步重新取得焦点，避免 Secure↔Plain 替换导致的失焦。
private struct SecretField: View {
    let placeholder: String
    @Binding var text: String

    @State private var revealed = false
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var border: Color {
        if focused { return Palette.textTertiary }
        if hovering { return Palette.borderHover }
        return Palette.borderDefault
    }
    private var fill: Color { (focused || hovering) ? Palette.stateHover : .clear }

    var body: some View {
        HStack(spacing: GaltDesign.Spacing.sm) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($focused)

            Button {
                revealed.toggle()
                DispatchQueue.main.async { focused = true }
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(hovering || focused ? Palette.textSecondary : Palette.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(revealed ? "隐藏密钥" : "显示密钥")
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
            .strokeBorder(border, lineWidth: focused ? 1.5 : 1))
        .onHover { hovering = $0 }
        .animation(GaltDesign.Motion.hover(reduceMotion), value: hovering)
        .animation(GaltDesign.Motion.hover(reduceMotion), value: focused)
    }
}

/// 设置侧栏矢量图标（对照 Figma node 647:121）：1.333 描边 / 圆头圆角 / 16×16 画布。
/// 按页种类切换路径；以 `.stroke()` 渲染，颜色随父级 foregroundStyle。
struct SettingsIconShape: Shape {
    enum Kind { case back, general, keyboard, language, audio, engine, models }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        func m(_ x: CGFloat, _ y: CGFloat) { p.move(to: pt(x, y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: pt(x, y)) }
        func c(_ ex: CGFloat, _ ey: CGFloat, _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
            p.addCurve(to: pt(ex, ey), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
        }
        func dot(_ x: CGFloat, _ y: CGFloat) { p.move(to: pt(x, y)); p.addLine(to: pt(x + 0.02, y)) }
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            p.addEllipse(in: CGRect(x: x * s, y: y * s, width: w * s, height: h * s))
        }
        func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
            p.addRoundedRect(in: CGRect(x: x * s, y: y * s, width: w * s, height: h * s),
                             cornerSize: CGSize(width: r * s, height: r * s), style: .continuous)
        }

        switch kind {
        case .back:
            m(8, 12.6667); l(3.33333, 8); l(8, 3.33333)
            m(12.6667, 8); l(3.33333, 8)

        case .general: // 扳手
            m(9.79999, 4.19986)
            c(9.60941, 4.66652, 9.67783, 4.32448, 9.60941, 4.49202)
            c(9.79999, 5.13319, 9.60941, 4.84103, 9.67783, 5.00857)
            l(10.8667, 6.19986)
            c(11.3333, 6.39043, 10.9913, 6.32201, 11.1588, 6.39043)
            c(11.8, 6.19986, 11.5078, 6.39043, 11.6754, 6.32201)
            l(13.8707, 4.12986)
            c(14.526, 4.27519, 14.084, 3.91519, 14.446, 3.98319)
            c(14.4932, 6.50892, 14.7274, 5.00777, 14.716, 5.78257)
            c(13.2676, 8.37668, 14.2703, 7.23527, 13.8452, 7.88312)
            c(11.2315, 9.2959, 12.69, 8.87024, 11.9837, 9.18908)
            c(9.01999, 8.97986, 10.4793, 9.40272, 9.71218, 9.2931)
            l(3.74665, 14.2532)
            c(2.74675, 14.6672, 3.48144, 14.5183, 3.12176, 14.6672)
            c(1.74699, 14.2529, 2.37174, 14.6671, 2.01211, 14.5181)
            c(1.33301, 13.253, 1.48186, 13.9876, 1.33295, 13.628)
            c(1.74732, 12.2532, 1.33307, 12.8779, 1.4821, 12.5183)
            l(7.02065, 6.97986)
            c(6.70461, 4.76836, 6.70741, 6.28766, 6.59779, 5.52058)
            c(7.62383, 2.73227, 6.81143, 4.01613, 7.13027, 3.30989)
            c(9.49159, 1.50667, 8.11738, 2.15464, 8.76524, 1.72953)
            c(11.7253, 1.47386, 10.2179, 1.28382, 10.9927, 1.27243)
            c(11.8713, 2.12986, 12.0173, 1.55386, 12.0853, 1.91519)
            l(9.79999, 4.19986)
            p.closeSubpath()

        case .keyboard:
            roundRect(1.33333, 2.66667, 13.3333, 10.6667, 0.66667)
            dot(4, 5.33333); dot(6.66667, 5.33333); dot(9.33333, 5.33333); dot(12, 5.33333)
            dot(5.33333, 8); dot(8, 8); dot(10.6667, 8)
            m(4.66667, 10.6667); l(11.3333, 10.6667)

        case .language: // 地球
            ellipse(1.33333, 1.33333, 13.3333, 13.3333)
            m(5.33333, 8)
            c(8, 1.33333, 5.33333, 5.51783, 6.28816, 3.13077)
            c(10.6667, 8, 9.71184, 3.13077, 10.6667, 5.51783)
            c(8, 14.6667, 10.6667, 10.4822, 9.71184, 12.8692)
            c(5.33333, 8, 6.28816, 12.8692, 5.33333, 10.4822)
            p.closeSubpath()
            m(1.33333, 8); l(14.6667, 8)

        case .audio: // 活动脉冲线
            m(14.6667, 8)
            l(13.0133, 8)
            c(12.2061, 8.26998, 12.722, 7.99938, 12.4384, 8.0942)
            c(11.7267, 8.97333, 11.9737, 8.44575, 11.8053, 8.6928)
            l(10.16, 14.5467)
            c(10.1, 14.6333, 10.1499, 14.5813, 10.1288, 14.6117)
            c(10, 14.6667, 10.0711, 14.655, 10.0361, 14.6667)
            c(9.9, 14.6333, 9.96394, 14.6667, 9.92885, 14.655)
            c(9.84, 14.5467, 9.87115, 14.6117, 9.8501, 14.5813)
            l(6.16, 1.45333)
            c(6.1, 1.36667, 6.1499, 1.41871, 6.12885, 1.3883)
            c(6, 1.33333, 6.07115, 1.34503, 6.03606, 1.33333)
            c(5.9, 1.36667, 5.96394, 1.33333, 5.92885, 1.34503)
            c(5.84, 1.45333, 5.87115, 1.3883, 5.8501, 1.41871)
            l(4.27333, 7.02667)
            c(3.79658, 7.72801, 4.19498, 7.3061, 4.02759, 7.55234)
            c(2.99333, 8, 3.56556, 7.90367, 3.28355, 7.99917)
            l(1.33333, 8)

        case .engine: // 芯片
            m(2.66667, 6)
            l(2.66667, 3.33333)
            c(3.05719, 2.39052, 2.66667, 2.97971, 2.80714, 2.64057)
            c(4, 2, 3.30724, 2.14048, 3.64638, 2)
            l(12, 2)
            c(12.9428, 2.39052, 12.3536, 2, 12.6928, 2.14048)
            c(13.3333, 3.33333, 13.1929, 2.64057, 13.3333, 2.97971)
            l(13.3333, 6)
            m(5.33333, 5.33333); l(5.33333, 6)
            m(8, 5.33333); l(8, 6)
            m(10.6667, 5.33333); l(10.6667, 6)
            roundRect(1.33333, 6, 13.3333, 8, 0.66667)
            ellipse(4, 8.66667, 2.66667, 2.66667)
            ellipse(9.33333, 8.66667, 2.66667, 2.66667)

        case .models: // 堆叠
            m(8, 8); l(8, 6)
            c(7.80474, 5.5286, 8, 5.82319, 7.92976, 5.65362)
            c(7.33333, 5.33333, 7.67971, 5.40357, 7.51014, 5.33333)
            l(6, 5.33333)
            c(5.5286, 5.5286, 5.82319, 5.33333, 5.65362, 5.40357)
            c(5.33333, 6, 5.40357, 5.65362, 5.33333, 5.82319)
            l(5.33333, 8)
            m(10.6667, 13.3333); l(10.6667, 11.3333)
            c(10.4714, 10.8619, 10.6667, 11.1565, 10.5964, 10.987)
            c(10, 10.6667, 10.3464, 10.7369, 10.1768, 10.6667)
            l(8.66667, 10.6667)
            c(8.19526, 10.8619, 8.48986, 10.6667, 8.32029, 10.7369)
            c(8, 11.3333, 8.07024, 10.987, 8, 11.1565)
            l(8, 13.3333)
            m(13.3333, 14.6667); l(13.3333, 1.33333)
            m(2.66667, 8); l(13.3333, 8)
            m(2.66667, 13.3333); l(13.3333, 13.3333)
            m(2.66667, 1.33333); l(2.66667, 14.6667)
            m(2.66667, 2.66667); l(13.3333, 2.66667)
        }
        return p
    }
}

/// 设置侧栏图标统一渲染：16×16 描边，颜色随父级 foregroundStyle。
struct SettingsSidebarIcon: View {
    let kind: SettingsIconShape.Kind
    var body: some View {
        SettingsIconShape(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: 1.333, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 16)
    }
}

struct SettingsView: View {
    /// 呈现样式：控制台内嵌用长表单；独立设置窗口用侧边栏偏好布局；tabbed 保留给旧快照兼容
    enum Layout { case grouped, tabbed, sidebar }
    var layout: Layout = .grouped
    var onBack: (() -> Void)? = nil
    /// 仅供快照/测试预置 .sidebar 布局的初始选中项
    var initialSelection: SettingsSidebarItem? = nil

    // 键盘快捷键
    @AppStorage("dictationHotkey") private var dictationHotkey = "fn"
    @AppStorage("translateHotkey") private var translateHotkey = "none"
    @AppStorage("askHotkey") private var askHotkey = "none"

    // 语言
    @AppStorage("uiLanguage") private var uiLanguage = "zh-Hans"
    @AppStorage("translationTarget") private var translationTarget = "off"
    @AppStorage("localLocaleId") private var localLocale = "zh-CN"

    // 音频
    @AppStorage("micDeviceUID") private var micDeviceUID = "auto"
    @AppStorage("soundFeedback") private var soundFeedback = true
    @AppStorage("muteWhileDictating") private var muteWhileDictating = false

    // 应用行为
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showInDock") private var showInDock = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    // 转写引擎与润色
    @AppStorage("engineMode") private var engineMode = "auto"
    @AppStorage("localEngine") private var localEngine = "apple"
    @AppStorage("whisperModelId") private var whisperModelId = "small-q5_1"
    @AppStorage("polishEnabled") private var polishEnabled = true
    @AppStorage("cloudSTTProviderId") private var sttProviderId = "groq"
    @AppStorage("llmProviderId") private var llmProviderId = "groq"

    // Key 存钥匙串，不走 UserDefaults
    @State private var sttKey = ""
    @State private var sttAppKey = ""
    @State private var llmKey = ""
    @State private var llmModel = ""
    // 模型库：各厂商凭证 / 模型按 id 缓存，供凭证目录逐行编辑
    @State private var sttKeys: [String: String] = [:]
    @State private var llmKeys: [String: String] = [:]
    @State private var llmModels: [String: String] = [:]
    // 火山 ASR 模型配置（协议 / 资源 / 接口），write-through 到 SettingsStore
    @State private var volcanoProtocol = SettingsStore.shared.volcanoProtocol
    @State private var volcanoResourceId = SettingsStore.shared.volcanoResourceId
    @State private var volcanoEndpoint = SettingsStore.shared.volcanoEndpoint
    // 删除本地模型后自增，触发 modelLibraryPanel 重新读取文件存在状态
    @State private var modelStateTick = 0
    // 模型库：顶部分段 + 主从选中 + 高级折叠 + 表单提示
    @State private var librarySegment = "stt"   // stt | llm | local
    @State private var libSelectedSTT = "groq"
    @State private var libSelectedLLM = "groq"
    @State private var showAdvancedOptions = false
    @State private var formMessage = ""
    @State private var fetchedModels: [String] = []
    @State private var isProbing = false
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var sidebarSelection: SettingsSidebarItem = .general
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var settingsSelectionPill
    /// 设置分页切换：与控制台一级页一致的平滑弹簧
    private var settingsTabAnimation: Animation? {
        GaltDesign.Motion.page(reduceMotion)
    }
    @ObservedObject private var downloader = ModelDownloader.shared

    var body: some View {
        Group {
            switch layout {
            case .grouped: groupedBody
            case .tabbed: tabbedBody
            case .sidebar: sidebarBody
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let initialSelection { sidebarSelection = initialSelection }
        inputDevices = AudioDevices.inputDevices()
        volcanoProtocol = SettingsStore.shared.volcanoProtocol
        volcanoResourceId = SettingsStore.shared.volcanoResourceId
        volcanoEndpoint = SettingsStore.shared.volcanoEndpoint
        reloadSTTFields()
        reloadLLMFields()
        for provider in STTProviderInfo.all {
            sttKeys[provider.id] = SettingsStore.shared.sttKey(forProvider: provider.id)
        }
        for provider in LLMProviderInfo.all {
            llmKeys[provider.id] = SettingsStore.shared.llmKey(forProvider: provider.id)
            llmModels[provider.id] = SettingsStore.shared.llmModel(forProvider: provider.id)
        }
    }

    /// 控制台内嵌：单列长表单，契合左侧导航语境
    private var groupedBody: some View {
        Form {
            hotkeySection
            languageSection
            audioSection
            behaviorSection
            engineSection
            llmSection
            polishSection
        }
        .formStyle(.grouped)
    }

    /// 独立窗口：经典 macOS 工具栏分页偏好，降低单屏滚动负担
    private var tabbedBody: some View {
        TabView {
            Form {
                hotkeySection
                polishSection
            }
            .formStyle(.grouped)
            .tabItem { Label("听写", systemImage: "keyboard") }

            Form {
                engineSection
                llmSection
            }
            .formStyle(.grouped)
            .tabItem { Label("引擎", systemImage: "waveform") }

            Form {
                languageSection
                audioSection
            }
            .formStyle(.grouped)
            .tabItem { Label("语言与音频", systemImage: "globe") }

            Form {
                behaviorSection
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .padding(.top, GaltDesign.Spacing.xxs)
    }

    private var sidebarBody: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: SettingsDesign.sidebarWidth)
                .frame(maxHeight: .infinity)

            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SettingsDesign.contentBackground)
                .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.contentCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsDesign.contentCornerRadius, style: .continuous)
                        .strokeBorder(SettingsDesign.contentBorder, lineWidth: 1)
                )
        }
        .padding(SettingsDesign.outerInset)
        // 与控制台一致的侧栏毛玻璃；内容卡片自带实心底
        .background(VibrancyBackground())
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 32)
            settingsBackButton
            settingsSidebarSection("个人", items: [.general, .hotkeys, .language, .audio])
            settingsSidebarSection("引擎", items: [.voiceEngine, .modelLibrary])
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        // 不铺实心底色——透出 sidebarBody 的毛玻璃
    }

    private var settingsBackButton: some View {
        Button {
            if let onBack {
                onBack()
            } else {
                NSApp.keyWindow?.performClose(nil)
            }
        } label: {
            HStack(spacing: GaltDesign.Spacing.xs) {
                SettingsSidebarIcon(kind: .back)
                    .frame(width: SettingsDesign.sidebarIconWidth, height: 16)
                Text("返回应用")
                    .font(.system(size: SettingsDesign.sidebarTextSize, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(SettingsDesign.backText)
            .frame(height: SettingsDesign.sidebarRowHeight)
            .padding(.horizontal, SettingsDesign.sidebarInnerHorizontalPadding)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: SettingsDesign.sidebarRowRadius))
        .padding(.horizontal, SettingsDesign.sidebarHorizontalPadding)
    }

    private func settingsSidebarSection(_ title: String, items: [SettingsSidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsDesign.sectionText)
                .padding(.leading, 18)
                .padding(.trailing, GaltDesign.Spacing.md)
                .padding(.top, 15)
                .padding(.bottom, 5)
            ForEach(items) { item in
                settingsSidebarButton(item)
            }
        }
    }

    private func settingsSidebarButton(_ item: SettingsSidebarItem) -> some View {
        Button {
            withAnimation(settingsTabAnimation) { sidebarSelection = item }
        } label: {
            HStack(spacing: GaltDesign.Spacing.xs) {
                SettingsSidebarIcon(kind: item.iconKind)
                    .frame(width: SettingsDesign.sidebarIconWidth, height: 16)
                Text(item.title)
                    .font(.system(size: SettingsDesign.sidebarTextSize, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(SettingsDesign.primaryText)
            .frame(height: SettingsDesign.sidebarRowHeight)
            .padding(.horizontal, SettingsDesign.sidebarInnerHorizontalPadding)
            .background {
                if sidebarSelection == item {
                    RoundedRectangle(cornerRadius: SettingsDesign.sidebarRowRadius, style: .continuous)
                        .fill(SettingsDesign.selectedRowFill)
                        .matchedGeometryEffect(id: "settingsSidebarSelection", in: settingsSelectionPill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.sidebarRowRadius, style: .continuous))
        }
        .buttonStyle(RowButtonStyle(isSelected: sidebarSelection == item,
                                    cornerRadius: SettingsDesign.sidebarRowRadius,
                                    selectionDrawnExternally: true))
        .padding(.horizontal, SettingsDesign.sidebarHorizontalPadding)
    }

    @ViewBuilder
    private var settingsContent: some View {
        Group {
            if sidebarSelection == .modelLibrary {
                // 模型库：标题 + 分段固定，仅下方内容滚动
                modelLibraryScreen
            } else {
                scrollingSettingsContent
            }
        }
        .background(SettingsDesign.contentBackground)
    }

    private var scrollingSettingsContent: some View {
        BrandScrollView {
            VStack(alignment: .leading, spacing: GaltDesign.Spacing.xl) {
                Text(sidebarSelection.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SettingsDesign.primaryText)
                    .frame(height: 28, alignment: .leading)

                switch sidebarSelection {
                case .hotkeys:
                    hotkeysPanel
                case .language:
                    languagePanel
                case .audio:
                    audioPanel
                case .voiceEngine:
                    voiceEnginePanel
                case .general:
                    behaviorPanel
                case .modelLibrary:
                    EmptyView() // 由 modelLibraryScreen 单独处理
                }
            }
            .frame(maxWidth: SettingsDesign.contentMaxWidth, alignment: .leading)
            .padding(.top, SettingsDesign.contentTopPadding)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
            .id(sidebarSelection)
            .transition(.opacity)
        }
    }

    /// 模型库：固定头部（标题 + 分段）+ 可滚动内容
    private var modelLibraryScreen: some View {
        let _ = modelStateTick
        return VStack(alignment: .leading, spacing: GaltDesign.Spacing.lg) {
            Text("模型库")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SettingsDesign.primaryText)
                .frame(height: 28, alignment: .leading)
            librarySegmentControl
            modelLibraryBody
        }
        .frame(maxWidth: SettingsDesign.contentMaxWidth, alignment: .leading)
        .padding(.top, SettingsDesign.contentTopPadding)
        .padding(.bottom, GaltDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var modelLibraryBody: some View {
        switch librarySegment {
        case "local":
            BrandScrollView { localModelsList.padding(.bottom, GaltDesign.Spacing.sm) }
        case "llm":
            providerMasterDetail(isSTT: false)
        default:
            providerMasterDetail(isSTT: true)
        }
    }

    private var hotkeysPanel: some View {
        settingsPanel(title: "") {
            settingsRow(title: "语音输入", subtitle: "按住说话，松开出字；点按进入锁定听写。") {
                HotkeyRecorder(
                    keyRaw: $dictationHotkey,
                    allowNone: false,
                    accessibilityLabel: "语音输入快捷键",
                    takenRawValues: takenHotkeyRawValues(excluding: "dictation")
                )
                    .frame(width: 196, height: 28)
            }
            settingsRow(title: "翻译", subtitle: "按住说话，输出翻译目标语言的成稿。") {
                HotkeyRecorder(
                    keyRaw: $translateHotkey,
                    allowNone: true,
                    accessibilityLabel: "翻译快捷键",
                    takenRawValues: takenHotkeyRawValues(excluding: "translate")
                )
                    .frame(width: 196, height: 28)
            }
            settingsRow(title: "随便问", subtitle: "按住提问，AI 的回答直接写到光标处。") {
                HotkeyRecorder(
                    keyRaw: $askHotkey,
                    allowNone: true,
                    accessibilityLabel: "随便问快捷键",
                    takenRawValues: takenHotkeyRawValues(excluding: "ask")
                )
                    .frame(width: 196, height: 28)
            }
        }
    }

    private var languagePanel: some View {
        settingsPanel(title: "") {
            settingsRow(title: "界面语言", subtitle: "选择用户界面使用的语言。") {
                DropdownPicker(selection: $uiLanguage, options: [
                    DropdownOption(value: "zh-Hans", title: "简体中文（中国大陆）"),
                ])
            }
            settingsRow(title: "翻译目标", subtitle: "选择翻译模式下的听写目标语言。") {
                DropdownPicker(selection: $translationTarget, options: [
                    DropdownOption(value: "off", title: "关闭"),
                    DropdownOption(value: "zh-Hans", title: "简体中文"),
                    DropdownOption(value: "en", title: "英语（美国）"),
                    DropdownOption(value: "ja", title: "日语"),
                ])
            }
            settingsRow(title: "语言变体", subtitle: "选择您首选的语言变体，以获得最佳体验。") {
                DropdownPicker(selection: $localLocale, options: [
                    DropdownOption(value: "zh-CN", title: "简体中文"),
                    DropdownOption(value: "en-US", title: "English (US)"),
                    DropdownOption(value: "zh-TW", title: "繁體中文（台灣）"),
                    DropdownOption(value: "zh-HK", title: "粤语（香港）"),
                    DropdownOption(value: "ja-JP", title: "日本語"),
                ])
            }
        }
    }

    private var audioPanel: some View {
        settingsPanel(title: "") {
            settingsRow(title: "麦克风", subtitle: "选择语音输入使用的音频设备。") {
                DropdownPicker(selection: $micDeviceUID, options:
                    [DropdownOption(value: "auto", title: "自动检测")]
                    + inputDevices.map { DropdownOption(value: $0.uid, title: $0.name) })
            }
            settingsToggleRow(title: "交互声音", subtitle: "为开始和停止等关键操作播放声音。", isOn: $soundFeedback)
            settingsToggleRow(title: "语音输入时静音", subtitle: "在语音输入时自动静音其他活动音频。", isOn: $muteWhileDictating)
        }
    }

    // MARK: 语音引擎（仅激活选择与开关）

    private var voiceEnginePanel: some View {
        VStack(alignment: .leading, spacing: 36) {
            settingsPanel(title: "转写") {
                settingsRow(title: "引擎模式", subtitle: "选择云端、本地或自动兜底模式。") {
                    DropdownPicker(selection: $engineMode, options: [
                        DropdownOption(value: "auto", title: "自动（云端优先，离线兜底）"),
                        DropdownOption(value: "cloud", title: "仅云端"),
                        DropdownOption(value: "local", title: "仅本地（离线）"),
                    ])
                }
                settingsRow(title: "云端转写厂商", subtitle: cloudProviderHint) {
                    DropdownPicker(selection: $sttProviderId,
                        options: STTProviderInfo.all.map { DropdownOption(value: $0.id, title: $0.name) })
                }
                settingsRow(title: "本地模型", subtitle: "仅列出已下载的模型；更多模型在「模型库」下载。") {
                    DropdownPicker(selection: activeLocalSelection, options: localEngineOptions)
                }
            }

            settingsPanel(title: "AI润色") {
                settingsToggleRow(title: "启用 LLM 润色", subtitle: "去填充词、自动标点、按目标应用调整语气。", isOn: $polishEnabled)
                settingsRow(title: "润色厂商", subtitle: llmProviderHint) {
                    DropdownPicker(selection: $llmProviderId,
                        options: LLMProviderInfo.all.map { DropdownOption(value: $0.id, title: $0.name) })
                }
            }
        }
    }

    private var cloudProviderHint: String {
        let info = STTProviderInfo.byId(sttProviderId)
        let hasKey = !(sttKeys[sttProviderId] ?? "").isEmpty
        let configured = info.needsAppKey ? (hasKey && !sttAppKey.isEmpty) : hasKey
        return configured ? "当前厂商凭证已配置。" : "当前厂商尚未配置 API Key，请前往模型库。"
    }

    private var llmProviderHint: String {
        let configured = !(llmKeys[llmProviderId] ?? "").isEmpty
        return configured ? "当前厂商凭证已配置。" : "当前厂商尚未配置 API Key，请前往模型库。"
    }

    // MARK: 模型库（顶部分段 + 厂商主从布局 / 本地模型卡片，对照设计稿）
    // 标题与分段由 modelLibraryScreen 固定承载，内容区单独滚动。

    private var librarySegmentControl: some View {
        HStack(spacing: GaltDesign.Spacing.xxs) {
            librarySegmentButton("转写厂商", "stt")
            librarySegmentButton("润色厂商", "llm")
            librarySegmentButton("本地模型", "local")
        }
        .padding(GaltDesign.Spacing.xxxs)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.track))
    }

    private func librarySegmentButton(_ title: String, _ value: String) -> some View {
        Button {
            withAnimation(settingsTabAnimation) { librarySegment = value }
            formMessage = ""
            fetchedModels = []
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SettingsDesign.rowTitle)
                .padding(.horizontal, GaltDesign.Spacing.md)
                .padding(.vertical, GaltDesign.Spacing.xs)
                .background {
                    if librarySegment == value {
                        RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous)
                            .fill(Palette.surfaceRaised)
                            .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous).strokeBorder(Palette.borderSubtle, lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(isSelected: librarySegment == value, selectionDrawnExternally: true))
    }

    // MARK: 本地模型卡片列表

    private var localModelsList: some View {
        VStack(spacing: GaltDesign.Spacing.md) {
            modelCard(title: "Apple 设备端听写", subtitle: "系统内置、零下载。首次使用会请求「语音识别」权限。") {
                Text("已授权")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.rowTitle)
                    .padding(.horizontal, GaltDesign.Spacing.md)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.control, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
            }
            ForEach(LocalModel.all) { model in
                modelCard(
                    title: model.name,
                    subtitle: whisperSubtitle(model)
                ) {
                    whisperModelControl(model)
                }
            }
            if let error = downloader.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.danger500)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func whisperSubtitle(_ model: LocalModel) -> String {
        model.note + (model.isDownloaded ? "（已下载，可离线使用）" : "（下载约 \(model.sizeMB)MB）")
    }

    /// 本地引擎下拉选项：Apple + 已下载的本地模型（名字与模型库一致）。
    /// 未下载的模型不出现；sherpa 模型仅在 GALT_SHERPA 下进入目录，故无需额外门控。
    private var localEngineOptions: [DropdownOption] {
        _ = modelStateTick // 下载/删除后随 tick 重算
        var opts = [DropdownOption(value: "apple", title: "Apple 设备端听写")]
        opts += LocalModel.all
            .filter { $0.isDownloaded }
            .map { DropdownOption(value: $0.id, title: $0.name) }
        return opts
    }

    /// 本地引擎/模型的统一选择：值为 "apple" 或某个已下载模型的 id。
    /// 读：apple→"apple"，否则当前模型 id（若已被删除则回退 "apple"）。
    /// 写：选模型即定运行时（sherpa 模型→sherpa，其余→whispercpp）。
    private var activeLocalSelection: Binding<String> {
        let engine = $localEngine
        let modelId = $whisperModelId
        return Binding(
            get: {
                guard engine.wrappedValue != "apple" else { return "apple" }
                let m = LocalModel.byId(modelId.wrappedValue)
                return m.isDownloaded ? m.id : "apple"
            },
            set: { newValue in
                if newValue == "apple" {
                    engine.wrappedValue = "apple"
                } else {
                    let m = LocalModel.byId(newValue)
                    modelId.wrappedValue = m.id
                    engine.wrappedValue = m.runtime == .sherpaOnnx ? "sherpa" : "whispercpp"
                }
            }
        )
    }

    private func modelCard<Trailing: View>(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: GaltDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsDesign.rowTitle)
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(SettingsDesign.rowSubtitle)
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, GaltDesign.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous).fill(Color.clear))
        .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.card, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
    }

    @ViewBuilder
    private func whisperModelControl(_ model: LocalModel) -> some View {
        if downloader.downloadingId == model.id {
            HStack(spacing: GaltDesign.Spacing.sm) {
                ProgressView(value: downloader.progress).frame(width: 120)
                Text("\(Int(downloader.progress * 100))%").font(.caption).monospacedDigit()
            }
        } else if model.isDownloaded {
            HStack(spacing: GaltDesign.Spacing.md) {
                Button {
                    // 删除当前正在使用的模型时，本地引擎回退到 Apple，避免引擎指向已不存在的模型
                    if whisperModelId == model.id && localEngine != "apple" {
                        localEngine = "apple"
                    }
                    try? model.delete()
                    modelStateTick += 1
                } label: {
                    Text("删除").font(.system(size: 12)).foregroundStyle(Palette.danger500)
                }
                .buttonStyle(LinkButtonStyle())
            }
        } else {
            Button { downloader.download(model) } label: {
                Text("下载")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.rowTitle)
                    .padding(.horizontal, GaltDesign.Spacing.md)
                    .frame(height: 28)
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }

    // MARK: 厂商主从布局（左列表 + 右配置表单）

    private func providerMasterDetail(isSTT: Bool) -> some View {
        HStack(spacing: 0) {
            providerList(isSTT: isSTT)
                .frame(width: 244)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Palette.borderDefault).frame(width: 1)
                }
            providerForm(isSTT: isSTT)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous).fill(Color.clear))
        .overlay(RoundedRectangle(cornerRadius: GaltDesign.Radius.panel, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
    }

    @ViewBuilder
    private func providerList(isSTT: Bool) -> some View {
        let ids: [String] = isSTT ? STTProviderInfo.all.map(\.id) : LLMProviderInfo.all.map(\.id)
        VStack(spacing: GaltDesign.Spacing.xxs) {
            ForEach(ids, id: \.self) { id in
                providerListItem(id: id, name: providerDisplayName(id, isSTT: isSTT), isSTT: isSTT)
            }
            Spacer(minLength: 0)
        }
        .padding(GaltDesign.Spacing.lg)
    }

    /// 模型库列表/表单用的短展示名（对照设计稿，避免完整长名截断）
    private func providerDisplayName(_ id: String, isSTT: Bool) -> String {
        let map: [String: String] = isSTT
            ? ["groq": "Groq Whisper", "siliconflow": "SenseVoice", "dashscope": "Qwen3 ASR", "volcano": "火山引擎", "openai": "OpenAI"]
            : ["groq": "Groq", "dashscope": "阿里云百炼", "ark": "火山方舟", "deepseek": "DeepSeek", "siliconflow": "硅基流动", "openai": "OpenAI"]
        return map[id] ?? (isSTT ? STTProviderInfo.byId(id).name : LLMProviderInfo.byId(id).name)
    }

    private func providerListItem(id: String, name: String, isSTT: Bool) -> some View {
        let selected = (isSTT ? libSelectedSTT : libSelectedLLM) == id
        let configured = isSTT ? !(sttKeys[id] ?? "").isEmpty : !(llmKeys[id] ?? "").isEmpty
        return Button {
            if isSTT { libSelectedSTT = id } else { libSelectedLLM = id }
            formMessage = ""
            fetchedModels = []
        } label: {
            HStack(spacing: GaltDesign.Spacing.sm) {
                Text(name)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(configured ? "已配置" : "未配置")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, GaltDesign.Spacing.md)
            .frame(height: 36)
        }
        .buttonStyle(RowButtonStyle(isSelected: selected))
    }

    @ViewBuilder
    private func providerForm(isSTT: Bool) -> some View {
        let id = isSTT ? libSelectedSTT : libSelectedLLM
        let name = providerDisplayName(id, isSTT: isSTT)
        let configured = isSTT ? !(sttKeys[id] ?? "").isEmpty : !(llmKeys[id] ?? "").isEmpty
        let needsAppKey = isSTT && STTProviderInfo.byId(id).needsAppKey
        // 容器有 16pt 圆角描边：滚动条内缩，避开圆角、不溢出边框
        BrandScrollView(scrollbarInset: EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 6)) {
            VStack(alignment: .leading, spacing: GaltDesign.Spacing.lg) {
                // 头部：名称/状态 + 保存（按设计稿无头像，文字直接靠左）
                HStack(spacing: GaltDesign.Spacing.md) {
                    VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxxs) {
                        Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                        Text(configured ? "已配置" : "未配置").font(.system(size: 12)).foregroundStyle(SettingsDesign.rowSubtitle)
                    }
                    Spacer(minLength: 12)
                    Button {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        formMessage = "已保存"
                    } label: {
                        Text("保存").font(.system(size: 12)).foregroundStyle(Palette.onPrimary)
                            .padding(.horizontal, GaltDesign.Spacing.md).frame(height: 28)
                    }
                    .buttonStyle(FilledButtonStyle())
                }

                formField(label: "API 密钥", required: true) {
                    SecretField(placeholder: needsAppKey ? "Access Token（X-Api-Access-Key）" : "sk-..",
                                text: isSTT ? sttKeyBinding(id) : llmKeyBinding(id))
                }
                if needsAppKey {
                    formField(label: "App ID", required: true) {
                        TextField("X-Api-App-Key", text: $sttAppKey)
                            .textFieldStyle(.plain)
                            .modifier(FormFieldBox())
                            .onChange(of: sttAppKey) { newValue in
                                SettingsStore.shared.volcanoAppKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                    }
                }
                // 通用「接口地址」只对 OpenAI 兼容厂商 + LLM 生效；火山有独立 endpoint、
                // dashscope 走专用链路，都不消费它，故隐藏以免误导（见 usesGenericBaseURL）。
                if usesGenericBaseURL(id, isSTT: isSTT) {
                    formField(label: "接口地址", optional: true) {
                        TextField(defaultBaseURL(id, isSTT: isSTT), text: baseURLBinding(id))
                            .textFieldStyle(.plain)
                            .modifier(FormFieldBox())
                    }
                }

                HStack(spacing: 10) {
                    // 验证对所有厂商开放（非 OpenAI 兼容走验证音频）；获取模型仍仅 OpenAI 兼容可用。
                    formSecondaryButton("验证") { probeProvider(id: id, isSTT: isSTT, fetch: false) }
                        .disabled(isProbing)
                    formSecondaryButton("获取模型") { probeProvider(id: id, isSTT: isSTT, fetch: true) }
                        .disabled(!providerProbable(id, isSTT: isSTT) || isProbing)
                    if isProbing {
                        ProgressView().controlSize(.small)
                    } else if !formMessage.isEmpty {
                        Text(formMessage).font(.system(size: 12)).foregroundStyle(SettingsDesign.rowSubtitle).lineLimit(1)
                    } else if !providerProbable(id, isSTT: isSTT) {
                        Text("该厂商不支持自动获取模型，可点「验证」测试连接").font(.system(size: 12)).foregroundStyle(SettingsDesign.rowSubtitle)
                    }
                }
                Divider().overlay(Palette.borderDefault)

                if id == "volcano" {
                    // 火山支持多模型：预设一键带出 + 协议/资源/接口可自填
                    volcanoModelSection()
                } else {
                    formField(label: "模型", required: true) {
                        if isSTT {
                            // 转写模型固定，只读展示（沿用既有「转写只读」约定）
                            Text(sttModelName(STTProviderInfo.byId(id)))
                                .font(.system(size: 14))
                                .foregroundStyle(SettingsDesign.rowSubtitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .modifier(FormFieldBox())
                        } else {
                            // 可输入 + 可下拉：获取到模型后，右侧 ⌄ 直接选用（耦合原「点此选用」菜单）
                            TextField("输入模型名称", text: llmModelBinding(id))
                                .textFieldStyle(.plain)
                                .modifier(FormFieldBox())
                                .overlay(alignment: .trailing) { fetchedModelsMenu(id: id) }
                        }
                    }
                    Text(isSTT
                         ? "转写模型由厂商固定。"
                         : (fetchedModels.isEmpty
                            ? "尚未加载模型。可先「获取模型」，或手动输入模型名称。"
                            : "已获取 \(fetchedModels.count) 个模型，点输入框右侧 ⌄ 选用，或手动输入。"))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsDesign.rowSubtitle)
                }

                Divider().overlay(Palette.borderDefault)

                advancedOptions(id: id)
            }
            .padding(GaltDesign.Spacing.xxl)
        }
    }

    @ViewBuilder
    private func advancedOptions(id: String) -> some View {
        Button {
            withAnimation(settingsTabAnimation) { showAdvancedOptions.toggle() }
        } label: {
            HStack(spacing: GaltDesign.Spacing.xs) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(showAdvancedOptions ? 90 : 0))
                Text("高级选项").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LinkButtonStyle())
        if showAdvancedOptions {
            formField(label: "上下文窗口") {
                TextField("自动检测", text: advancedBinding(id, key: "ctx"))
                    .textFieldStyle(.plain)
                    .modifier(FormFieldBox())
            }
            formField(label: "请求超时") {
                TextField("默认60秒", text: advancedBinding(id, key: "timeout"))
                    .textFieldStyle(.plain)
                    .modifier(FormFieldBox())
            }
        }
    }

    private func formField<Content: View>(label: String, required: Bool = false, optional: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.xs) {
            HStack(spacing: GaltDesign.Spacing.xxxs) {
                Text(label).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                if required { Text("*").font(.system(size: 14)).foregroundStyle(Palette.danger) }
                if optional { Text("（可选）").font(.system(size: 14)).foregroundStyle(SettingsDesign.rowSubtitle) }
            }
            content()
        }
    }

    private func formSecondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, GaltDesign.Spacing.md).frame(height: 28)
        }
        .buttonStyle(OutlineButtonStyle())
    }

    /// 仅 OpenAI 兼容厂商可用 /models 验证与获取（STT 的火山/百炼多模态不支持）
    private func providerProbable(_ id: String, isSTT: Bool) -> Bool {
        guard isSTT else { return true }
        if case .openAICompatible = STTProviderInfo.byId(id).kind { return true }
        return false
    }

    /// 是否消费通用「接口地址」(base URL)。OpenAI 兼容 STT 与所有 LLM 走通用 base；
    /// dashscope STT 走专用链路、volcano 有独立 endpoint 字段，二者均不读它。
    private func usesGenericBaseURL(_ id: String, isSTT: Bool) -> Bool {
        guard isSTT else { return true }
        if case .openAICompatible = STTProviderInfo.byId(id).kind { return true }
        return false
    }

    private func probeProvider(id: String, isSTT: Bool, fetch: Bool) {
        let key = isSTT ? (sttKeys[id] ?? "") : (llmKeys[id] ?? "")
        guard !key.isEmpty else { formMessage = "请先填写 API 密钥"; return }
        isProbing = true
        formMessage = ""
        if fetch { fetchedModels = [] }

        // 「验证」对非 OpenAI 兼容的 STT 厂商（火山 / Qwen3）走「验证音频跑真实链路」；
        // 「获取模型」以及 OpenAI 兼容 / LLM 的验证仍走免费 GET /models。
        let useAudioVerify = !fetch && isSTT && !providerProbable(id, isSTT: true)

        Task {
            do {
                if useAudioVerify {
                    try await CloudSTTProvider().verify(providerId: id)
                    await MainActor.run {
                        isProbing = false
                        formMessage = "✓ 连接成功"
                    }
                    return
                }
                let base = SettingsStore.shared.baseURL(forProvider: id, default: defaultBaseURL(id, isSTT: isSTT))
                let timeout = SettingsStore.shared.requestTimeout(forProvider: id)
                let models = try await ProviderProbe.fetchModels(base: base, key: key, timeout: timeout)
                await MainActor.run {
                    isProbing = false
                    if fetch {
                        fetchedModels = models
                        if models.isEmpty { formMessage = "连接成功，但未返回模型列表" }
                    } else {
                        formMessage = "✓ 连接成功（\(models.count) 个模型）"
                    }
                }
            } catch {
                await MainActor.run {
                    isProbing = false
                    formMessage = "失败：\(probeErrorText(error))"
                }
            }
        }
    }

    private func probeErrorText(_ error: Error) -> String {
        if case let STTError.http(code, _) = error { return "HTTP \(code)" }
        return error.localizedDescription
    }

    private func defaultBaseURL(_ id: String, isSTT: Bool) -> String {
        if isSTT {
            if case let .openAICompatible(base, _) = STTProviderInfo.byId(id).kind { return base }
            return "https://api.openai.com/v1"
        }
        return LLMProviderInfo.byId(id).base
    }

    // 接口地址 / 高级参数暂存 UserDefaults，尚未接入网络层（占位，后续消费）
    private func baseURLBinding(_ id: String) -> Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: "providerBase.\(id)") ?? "" },
                set: { UserDefaults.standard.set($0, forKey: "providerBase.\(id)") })
    }

    private func advancedBinding(_ id: String, key: String) -> Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: "providerAdv.\(key).\(id)") ?? "" },
                set: { UserDefaults.standard.set($0, forKey: "providerAdv.\(key).\(id)") })
    }

    // MARK: 火山 ASR 模型配置（预设 + 自填 endpoint/resourceId/协议）

    private var volcanoProtocolBinding: Binding<String> {
        Binding(get: { volcanoProtocol },
                set: { volcanoProtocol = $0; SettingsStore.shared.volcanoProtocol = $0 })
    }
    private var volcanoResourceIdBinding: Binding<String> {
        Binding(get: { volcanoResourceId },
                set: { volcanoResourceId = $0; SettingsStore.shared.volcanoResourceId = $0.trimmingCharacters(in: .whitespaces) })
    }
    private var volcanoEndpointBinding: Binding<String> {
        Binding(get: { volcanoEndpoint },
                set: { volcanoEndpoint = $0; SettingsStore.shared.volcanoEndpoint = $0.trimmingCharacters(in: .whitespaces) })
    }

    private func applyVolcanoPreset(_ p: VolcanoASRModel) {
        volcanoProtocol = p.proto.rawValue; SettingsStore.shared.volcanoProtocol = p.proto.rawValue
        volcanoResourceId = p.resourceId; SettingsStore.shared.volcanoResourceId = p.resourceId
        volcanoEndpoint = p.endpoint; SettingsStore.shared.volcanoEndpoint = p.endpoint
    }

    /// 预设选择：值为预设 id 或 "custom"（配置不匹配任何预设时）
    private var volcanoPresetBinding: Binding<String> {
        Binding(
            get: {
                VolcanoASRModel.matching(
                    resourceId: volcanoResourceId, endpoint: volcanoEndpoint,
                    proto: VolcanoASRProtocol(rawValue: volcanoProtocol) ?? .flash
                )?.id ?? "custom"
            },
            set: { value in
                if let preset = VolcanoASRModel.presets.first(where: { $0.id == value }) {
                    applyVolcanoPreset(preset)
                }
                // "custom"：保持当前字段不变
            }
        )
    }

    @ViewBuilder
    private func volcanoModelSection() -> some View {
        let presetOptions = VolcanoASRModel.presets.map { DropdownOption(value: $0.id, title: $0.name) }
            + [DropdownOption(value: "custom", title: "自定义")]
        formField(label: "模型预设", optional: true) {
            DropdownPicker(selection: volcanoPresetBinding, options: presetOptions, height: 36)
        }
        formField(label: "协议", required: true) {
            DropdownPicker(
                selection: volcanoProtocolBinding,
                options: VolcanoASRProtocol.allCases.map { DropdownOption(value: $0.rawValue, title: $0.displayName) },
                height: 36
            )
        }
        formField(label: "Resource ID", required: true) {
            TextField("volc.bigasr.…", text: volcanoResourceIdBinding)
                .textFieldStyle(.plain)
                .modifier(FormFieldBox())
        }
        formField(label: "接口地址", required: true) {
            TextField("https://… 或 wss://…", text: volcanoEndpointBinding)
                .textFieldStyle(.plain)
                .modifier(FormFieldBox())
        }
        Text("预设可一键带出官方配置；也可自行修改 Resource ID / 接口地址或切换协议。流式走 WebSocket（wss），一次性走 HTTP（https）。")
            .font(.system(size: 12))
            .foregroundStyle(SettingsDesign.rowSubtitle)
    }

    /// 模型输入框右侧的「已获取模型」下拉：仅在获取到模型时出现，选中即填入输入框。
    @ViewBuilder
    private func fetchedModelsMenu(id: String) -> some View {
        if !fetchedModels.isEmpty {
            Menu {
                Text("已获取 \(fetchedModels.count) 个模型")
                ForEach(fetchedModels, id: \.self) { model in
                    Button {
                        llmModelBinding(id).wrappedValue = model
                    } label: {
                        if model == llmModels[id] { Label(model, systemImage: "checkmark") }
                        else { Text(model) }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, GaltDesign.Spacing.xs)
        }
    }

    /// 转写厂商的模型名当前在代码中固定，仅只读展示
    private func sttModelName(_ provider: STTProviderInfo) -> String {
        switch provider.kind {
        case .openAICompatible(_, let model): return model
        case .dashscope: return "qwen3-asr-flash"
        case .volcano: return "bigmodel"
        }
    }

    private func sttKeyBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { sttKeys[id] ?? "" },
            set: { newValue in
                sttKeys[id] = newValue
                SettingsStore.shared.setSTTKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forProvider: id)
            }
        )
    }

    private func llmKeyBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { llmKeys[id] ?? "" },
            set: { newValue in
                llmKeys[id] = newValue
                SettingsStore.shared.setLLMKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forProvider: id)
            }
        )
    }

    private func llmModelBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { llmModels[id] ?? "" },
            set: { newValue in
                llmModels[id] = newValue
                SettingsStore.shared.setLLMModel(newValue.trimmingCharacters(in: .whitespaces), forProvider: id)
            }
        )
    }

    private var behaviorPanel: some View {
        settingsPanel(title: "") {
            settingsRow(title: "外观", subtitle: "使用浅色、深色，或匹配系统设置") {
                appearanceThumbnails
            }
            settingsToggleRow(title: "登录时启动应用", subtitle: "电脑启动时自动打开 Galt", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            settingsToggleRow(title: "在 Dock 中显示应用", subtitle: "在 Dock 中显示 Galt 图标，便于快速访问。", isOn: $showInDock)
                .onChange(of: showInDock) { _ in
                    SettingsStore.shared.applyDockVisibility()
                }
        }
    }

    // MARK: 外观预览缩略图（对照设计稿：3 个 56×44 迷你窗口，浅 / 深 / 跟随系统）

    private var appearanceThumbnails: some View {
        HStack(spacing: 5) {
            appearanceOption("light")
            appearanceOption("dark")
            appearanceOption("system")
        }
    }

    private func appearanceOption(_ mode: String) -> some View {
        Button {
            appearance = mode
            SettingsStore.shared.applyAppearance()
        } label: {
            appearancePreview(mode)
                .frame(width: 56, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            appearance == mode ? Palette.primary : SettingsDesign.contentBorder,
                            lineWidth: appearance == mode ? 2 : 1
                        )
                )
        }
        .buttonStyle(PressableButtonStyle(pressedOpacity: 0.8, pressedScale: 0.97))
        .accessibilityLabel(mode == "light" ? "浅色" : mode == "dark" ? "深色" : "跟随系统")
        .accessibilityAddTraits(appearance == mode ? .isSelected : [])
    }

    @ViewBuilder
    private func appearancePreview(_ mode: String) -> some View {
        ZStack {
            if mode == "system" {
                HStack(spacing: 0) {
                    Color(hex: 0xF5F5F5)
                    Color(hex: 0x0E100F)
                }
            } else {
                (mode == "dark" ? Color(hex: 0x0E100F) : Color(hex: 0xF5F5F5))
            }
            miniWindowCard(dark: mode == "dark")
        }
    }

    /// 迷你窗口卡片：红绿灯 + 几条占位条，深色态用深底深条
    private func miniWindowCard(dark: Bool) -> some View {
        let bar = dark ? Color(hex: 0x2F3034) : Color(hex: 0xF2F2F2)
        return VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxxs) {
            HStack(spacing: 1.5) {
                Circle().fill(Color(hex: 0xF2695A)).frame(width: 3, height: 3)
                Circle().fill(Color(hex: 0xF7BE4A)).frame(width: 3, height: 3)
                Circle().fill(Color(hex: 0x58CB49)).frame(width: 3, height: 3)
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous).fill(bar).frame(height: 6)
            RoundedRectangle(cornerRadius: 1, style: .continuous).fill(bar).frame(width: 18, height: 2)
            RoundedRectangle(cornerRadius: 1, style: .continuous).fill(bar).frame(width: 18, height: 2)
            Spacer(minLength: 0)
        }
        .padding(GaltDesign.Spacing.xxs)
        .frame(width: 40, height: 28, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(dark ? Color(hex: 0x0E100F) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(dark ? Color(hex: 0x3E3E3E) : Color(hex: 0xDADDE2), lineWidth: 0.5)
        )
    }

    /// 子区：可选 16px 子标题 + 其下整行分隔线，再以 12pt 间距铺行（对照设计稿「转写 / AI润色」）。
    /// 单区 tab（通用/语言/音频/快捷键）传空标题，仅靠页面大标题领起。
    private func settingsPanel<Content: View>(title: String, systemImage: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SettingsDesign.rowTitle)
                Divider()
                    .overlay(SettingsDesign.contentBorder)
                    .padding(.top, GaltDesign.Spacing.md)
                    .padding(.bottom, GaltDesign.Spacing.xxs)
            }
            VStack(spacing: GaltDesign.Spacing.md) {
                content()
            }
        }
    }

    private func settingsRow<Control: View>(title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: GaltDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsDesign.rowTitle)
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(SettingsDesign.rowSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
            control()
        }
        .frame(minHeight: 56)
    }

    private func settingsToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        settingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Palette.primary)
        }
    }

    private func reloadSTTFields() {
        sttKey = SettingsStore.shared.sttKey(forProvider: sttProviderId)
        sttAppKey = SettingsStore.shared.volcanoAppKey
    }

    private func reloadLLMFields() {
        llmKey = SettingsStore.shared.llmKey(forProvider: llmProviderId)
        llmModel = SettingsStore.shared.llmModel(forProvider: llmProviderId)
    }

    // MARK: 键盘快捷键

    private var hotkeySection: some View {
        Section {
            hotkeyPicker("语音输入", id: "dictation", subtitle: "按住说话，松开出字；点按进入锁定听写", selection: $dictationHotkey, allowNone: false)
            hotkeyPicker("翻译", id: "translate", subtitle: "按住说话，输出翻译目标语言的成稿", selection: $translateHotkey, allowNone: true)
            hotkeyPicker("随便问", id: "ask", subtitle: "按住提问，AI 的回答直接写到光标处", selection: $askHotkey, allowNone: true)
        } header: {
            Label("键盘快捷键", systemImage: "keyboard")
        } footer: {
            Text("均为按住说话的修饰键，不会干扰正常输入。三个功能请绑定不同的快捷键。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hotkeyPicker(_ title: String, id: String, subtitle: String, selection: Binding<String>, allowNone: Bool) -> some View {
        VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxs) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                HotkeyRecorder(
                    keyRaw: selection,
                    allowNone: allowNone,
                    accessibilityLabel: "\(title)快捷键",
                    takenRawValues: takenHotkeyRawValues(excluding: id)
                )
                    .frame(width: 196, height: 28)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func takenHotkeyRawValues(excluding id: String) -> Set<String> {
        [
            id == "dictation" ? nil : dictationHotkey,
            id == "translate" ? nil : translateHotkey,
            id == "ask" ? nil : askHotkey,
        ]
        .compactMap { $0 }
        .filter { HotkeyCombo(rawValue: $0).isEmpty == false }
        .reduce(into: Set<String>()) { result, raw in
            result.insert(HotkeyCombo(rawValue: raw).canonicalRawValue)
        }
    }

    // MARK: 语言

    private var languageSection: some View {
        Section {
            Picker("界面语言", selection: $uiLanguage) {
                Text("简体中文（中国大陆）").tag("zh-Hans")
            }
            Picker("翻译目标", selection: $translationTarget) {
                Text("关闭").tag("off")
                Text("简体中文").tag("zh-Hans")
                Text("英语（美国）").tag("en")
                Text("日语").tag("ja")
            }
            Picker("本地引擎语言变体", selection: $localLocale) {
                Text("简体中文").tag("zh-CN")
                Text("English (US)").tag("en-US")
                Text("繁體中文（台灣）").tag("zh-TW")
                Text("粤语（香港）").tag("zh-HK")
                Text("日本語").tag("ja-JP")
            }
        } header: {
            Label("语言", systemImage: "globe")
        } footer: {
            Text("「翻译目标」关闭时，翻译热键仍默认译为英文。云端与 Whisper 引擎自动检测口述语言；Apple 本地引擎需要指定语言变体。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 音频

    private var audioSection: some View {
        Section {
            Picker("麦克风", selection: $micDeviceUID) {
                Text("自动检测").tag("auto")
                ForEach(inputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            Toggle(isOn: $soundFeedback) {
                VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxxs) {
                    Text("交互声音")
                    Text("为开始/停止等关键操作播放声音")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $muteWhileDictating) {
                VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxxs) {
                    Text("语音输入时静音")
                    Text("在语音输入时自动静音其他活动音频")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("音频", systemImage: "mic")
        }
    }

    // MARK: 应用行为

    private var behaviorSection: some View {
        Section {
            Picker("外观", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _ in
                SettingsStore.shared.applyAppearance()
            }
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxxs) {
                    Text("登录时启动应用")
                    Text("当您的电脑启动时，自动打开 Galt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: launchAtLogin) { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
            Toggle(isOn: $showInDock) {
                VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxxs) {
                    Text("在 Dock 中显示应用")
                    Text("在 Dock 中显示 Galt 图标，便于快速访问")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: showInDock) { _ in
                SettingsStore.shared.applyDockVisibility()
            }
        } header: {
            Label("应用行为", systemImage: "macwindow")
        }
    }

    // MARK: 转写引擎

    private var engineSection: some View {
        Section {
            Picker("引擎", selection: $engineMode) {
                Text("自动（云端优先，离线兜底）").tag("auto")
                Text("仅云端").tag("cloud")
                Text("仅本地（离线）").tag("local")
            }
            Picker("云端转写厂商", selection: $sttProviderId) {
                ForEach(STTProviderInfo.all) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .onChange(of: sttProviderId) { _ in reloadSTTFields() }
            if STTProviderInfo.byId(sttProviderId).needsAppKey {
                TextField("App ID（X-Api-App-Key）", text: $sttAppKey)
                    .onChange(of: sttAppKey) { newValue in
                        SettingsStore.shared.volcanoAppKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
            }
            SecureField(STTProviderInfo.byId(sttProviderId).needsAppKey ? "Access Token（X-Api-Access-Key）" : "API Key", text: $sttKey)
                .onChange(of: sttKey) { newValue in
                    SettingsStore.shared.setSTTKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forProvider: sttProviderId)
                }
            Picker("本地模型", selection: activeLocalSelection) {
                Text("Apple 设备端听写（零下载）").tag("apple")
                ForEach(LocalModel.all.filter { $0.isDownloaded }) { model in
                    Text(model.name).tag(model.id)
                }
            }
        } header: {
            Label("转写引擎", systemImage: "waveform")
        } footer: {
            Text("\(STTProviderInfo.byId(sttProviderId).keyHint)。各厂商 Key 独立保存于系统钥匙串。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 润色模型

    private var llmSection: some View {
        Section {
            Picker("厂商", selection: $llmProviderId) {
                ForEach(LLMProviderInfo.all) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .onChange(of: llmProviderId) { _ in reloadLLMFields() }
            TextField("模型", text: $llmModel)
                .onChange(of: llmModel) { newValue in
                    SettingsStore.shared.setLLMModel(newValue.trimmingCharacters(in: .whitespaces), forProvider: llmProviderId)
                }
            SecureField("API Key", text: $llmKey)
                .onChange(of: llmKey) { newValue in
                    SettingsStore.shared.setLLMKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forProvider: llmProviderId)
                }
        } header: {
            Label("润色模型", systemImage: "brain")
        } footer: {
            Text("\(LLMProviderInfo.byId(llmProviderId).keyHint)。润色、翻译、语音编辑与随便问均使用此模型，可与转写厂商不同。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: AI 润色

    private var polishSection: some View {
        Section {
            Toggle(isOn: $polishEnabled) {
                VStack(alignment: .leading, spacing: GaltDesign.Spacing.xxxs) {
                    Text("启用 LLM 润色")
                    Text("去填充词、自动标点、按目标应用调整语气")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("AI 润色", systemImage: "wand.and.stars")
        } footer: {
            Text("个人词典请在控制台的「个人词典」页中管理。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
