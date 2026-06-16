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

    var icon: String {
        switch self {
        case .hotkeys: return "keyboard"
        case .language: return "globe"
        case .audio: return "mic"
        case .voiceEngine: return "waveform"
        case .modelLibrary: return "square.stack.3d.up"
        case .general: return "gearshape"
        }
    }
}

private enum SettingsDesign {
    static let outerInset: CGFloat = 8
    static let sidebarWidth: CGFloat = 232
    static let contentCornerRadius: CGFloat = 16
    static let contentMaxWidth: CGFloat = 904
    static let contentTopPadding: CGFloat = 24

    static let windowBackground = Palette.surfaceCanvas
    static let contentBackground = Palette.surfacePanel
    static let contentBorder = Palette.borderDefault
    static let selectedRowFill = Palette.selectionFill
    static let primaryText = Palette.textPrimary
    static let rowTitle = Palette.textPrimary
    static let rowSubtitle = Palette.textSecondary
    static let sectionText = Palette.textPrimary.opacity(0.5)
    static let backText = Palette.textSecondary

    static let sidebarRowHeight: CGFloat = 32
    static let sidebarRowRadius: CGFloat = 8
    static let sidebarHorizontalPadding: CGFloat = 10
    static let sidebarInnerHorizontalPadding: CGFloat = 8
    static let sidebarIconWidth: CGFloat = 18
    static let sidebarIconSize: CGFloat = 14
    static let sidebarTextSize: CGFloat = 14
}

/// 模型库表单输入框样式：36 高、圆角描边盒（对照设计稿）
private struct FormFieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .padding(.horizontal, 11)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
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
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)
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
        .padding(.top, 4)
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
        .background(SettingsDesign.windowBackground)
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
        .background(SettingsDesign.windowBackground)
    }

    private var settingsBackButton: some View {
        Button {
            if let onBack {
                onBack()
            } else {
                NSApp.keyWindow?.performClose(nil)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: SettingsDesign.sidebarIconSize, weight: .regular))
                    .frame(width: SettingsDesign.sidebarIconWidth, height: 16)
                Text("返回应用")
                    .font(.system(size: SettingsDesign.sidebarTextSize, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(SettingsDesign.backText)
            .frame(height: SettingsDesign.sidebarRowHeight)
            .padding(.horizontal, SettingsDesign.sidebarInnerHorizontalPadding)
            .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.sidebarRowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SettingsDesign.sidebarHorizontalPadding)
    }

    private func settingsSidebarSection(_ title: String, items: [SettingsSidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsDesign.sectionText)
                .padding(.leading, 18)
                .padding(.trailing, 12)
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
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: SettingsDesign.sidebarIconSize, weight: .regular))
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
        .buttonStyle(.plain)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
        return VStack(alignment: .leading, spacing: 16) {
            Text("模型库")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SettingsDesign.primaryText)
                .frame(height: 28, alignment: .leading)
            librarySegmentControl
            modelLibraryBody
        }
        .frame(maxWidth: SettingsDesign.contentMaxWidth, alignment: .leading)
        .padding(.top, SettingsDesign.contentTopPadding)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var modelLibraryBody: some View {
        switch librarySegment {
        case "local":
            ScrollView { localModelsList.padding(.bottom, 8) }
        case "llm":
            providerMasterDetail(isSTT: false)
        default:
            providerMasterDetail(isSTT: true)
        }
    }

    private var hotkeysPanel: some View {
        settingsPanel(title: "") {
            settingsRow(title: "语音输入", subtitle: "按下开始和停止语音输入。") {
                HotkeyRecorder(keyRaw: $dictationHotkey, allowNone: false)
                    .frame(width: 196, height: 36)
            }
            settingsRow(title: "翻译", subtitle: "按下开始和停止翻译。") {
                HotkeyRecorder(keyRaw: $translateHotkey, allowNone: true)
                    .frame(width: 196, height: 36)
            }
            settingsRow(title: "随便问", subtitle: "按下开始和停止随便提问。") {
                HotkeyRecorder(keyRaw: $askHotkey, allowNone: true)
                    .frame(width: 196, height: 36)
            }
        }
    }

    private var languagePanel: some View {
        settingsPanel(title: "") {
            settingsRow(title: "界面语言", subtitle: "选择用户界面使用的语言。") {
                Picker("界面语言", selection: $uiLanguage) {
                    Text("简体中文（中国大陆）").tag("zh-Hans")
                }
                .labelsHidden()
                .frame(width: 230, alignment: .trailing)
            }
            settingsRow(title: "翻译目标", subtitle: "选择翻译模式下的听写目标语言。") {
                Picker("翻译目标", selection: $translationTarget) {
                    Text("关闭").tag("off")
                    Text("简体中文").tag("zh-Hans")
                    Text("英语（美国）").tag("en")
                    Text("日语").tag("ja")
                }
                .labelsHidden()
                .frame(width: 230, alignment: .trailing)
            }
            settingsRow(title: "语言变体", subtitle: "选择您首选的语言变体，以获得最佳体验。") {
                Picker("语言变体", selection: $localLocale) {
                    Text("简体中文").tag("zh-CN")
                    Text("English (US)").tag("en-US")
                    Text("繁體中文（台灣）").tag("zh-TW")
                    Text("粤语（香港）").tag("zh-HK")
                    Text("日本語").tag("ja-JP")
                }
                .labelsHidden()
                .frame(width: 230, alignment: .trailing)
            }
        }
    }

    private var audioPanel: some View {
        settingsPanel(title: "") {
            settingsRow(title: "麦克风", subtitle: "选择语音输入使用的音频设备。") {
                Picker("麦克风", selection: $micDeviceUID) {
                    Text("自动检测").tag("auto")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .frame(width: 230, alignment: .trailing)
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
                    Picker("引擎模式", selection: $engineMode) {
                        Text("自动（云端优先，离线兜底）").tag("auto")
                        Text("仅云端").tag("cloud")
                        Text("仅本地（离线）").tag("local")
                    }
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
                }
                settingsRow(title: "云端转写厂商", subtitle: cloudProviderHint) {
                    Picker("云端转写厂商", selection: $sttProviderId) {
                        ForEach(STTProviderInfo.all) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
                }
                settingsRow(title: "本地引擎", subtitle: "选择本地离线识别方式，Whisper 模型在「模型库」下载。") {
                    Picker("本地引擎", selection: $localEngine) {
                        Text("Apple 设备端听写").tag("apple")
                        Text("Whisper 离线模型").tag("whispercpp")
                    }
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
                }
            }

            settingsPanel(title: "AI润色") {
                settingsToggleRow(title: "启用 LLM 润色", subtitle: "去填充词、自动标点、按目标应用调整语气。", isOn: $polishEnabled)
                settingsRow(title: "润色厂商", subtitle: llmProviderHint) {
                    Picker("润色厂商", selection: $llmProviderId) {
                        ForEach(LLMProviderInfo.all) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
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
        HStack(spacing: 4) {
            librarySegmentButton("转写厂商", "stt")
            librarySegmentButton("润色厂商", "llm")
            librarySegmentButton("本地模型", "local")
        }
        .padding(2)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if librarySegment == value {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.surfaceRaised)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.borderSubtle, lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 本地模型卡片列表

    private var localModelsList: some View {
        VStack(spacing: 12) {
            modelCard(title: "Apple 设备端听写", subtitle: "系统内置、零下载。首次使用会请求「语音识别」权限。") {
                Text("已授权")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.rowTitle)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
            }
            ForEach(WhisperModel.all) { model in
                modelCard(
                    title: model.name,
                    subtitle: model.isDownloaded ? "已下载到本机，可离线使用。" : whisperSubtitle(model)
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

    private func whisperSubtitle(_ model: WhisperModel) -> String {
        (model.id.contains("large") ? "高精度，约" : "多语言，约") + "\(model.sizeMB)MB"
    }

    private func modelCard<Trailing: View>(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
    }

    @ViewBuilder
    private func whisperModelControl(_ model: WhisperModel) -> some View {
        if downloader.downloadingId == model.id {
            HStack(spacing: 8) {
                ProgressView(value: downloader.progress).frame(width: 120)
                Text("\(Int(downloader.progress * 100))%").font(.caption).monospacedDigit()
            }
        } else if model.isDownloaded {
            HStack(spacing: 12) {
                if whisperModelId != model.id {
                    Button("设为默认") { whisperModelId = model.id }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.primary)
                }
                Button {
                    try? model.delete()
                    modelStateTick += 1
                } label: {
                    Text("删除").font(.system(size: 12)).foregroundStyle(Palette.danger500)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button("下载") { downloader.download(model) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(SettingsDesign.rowTitle)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
    }

    @ViewBuilder
    private func providerList(isSTT: Bool) -> some View {
        let ids: [String] = isSTT ? STTProviderInfo.all.map(\.id) : LLMProviderInfo.all.map(\.id)
        VStack(spacing: 4) {
            ForEach(ids, id: \.self) { id in
                providerListItem(id: id, name: providerDisplayName(id, isSTT: isSTT), isSTT: isSTT)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
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
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(configured ? "已配置" : "未配置")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Palette.track : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerForm(isSTT: Bool) -> some View {
        let id = isSTT ? libSelectedSTT : libSelectedLLM
        let name = providerDisplayName(id, isSTT: isSTT)
        let configured = isSTT ? !(sttKeys[id] ?? "").isEmpty : !(llmKeys[id] ?? "").isEmpty
        let needsAppKey = isSTT && STTProviderInfo.byId(id).needsAppKey
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 头部：名称/状态 + 保存（按设计稿无头像，文字直接靠左）
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                        Text(configured ? "已配置" : "未配置").font(.system(size: 12)).foregroundStyle(SettingsDesign.rowSubtitle)
                    }
                    Spacer(minLength: 12)
                    Button {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        formMessage = "已保存"
                    } label: {
                        Text("保存").font(.system(size: 12)).foregroundStyle(Palette.onPrimary)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.primary))
                    }
                    .buttonStyle(.plain)
                }

                formField(label: "API 密钥", required: true) {
                    SecureField(needsAppKey ? "Access Token（X-Api-Access-Key）" : "sk-..", text: isSTT ? sttKeyBinding(id) : llmKeyBinding(id))
                        .textFieldStyle(.plain)
                        .modifier(FormFieldBox())
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
                formField(label: "接口地址", optional: true) {
                    TextField(defaultBaseURL(id, isSTT: isSTT), text: baseURLBinding(id))
                        .textFieldStyle(.plain)
                        .modifier(FormFieldBox())
                }

                HStack(spacing: 10) {
                    formSecondaryButton("验证") { probeProvider(id: id, isSTT: isSTT, fetch: false) }
                        .disabled(!providerProbable(id, isSTT: isSTT) || isProbing)
                    formSecondaryButton("获取模型") { probeProvider(id: id, isSTT: isSTT, fetch: true) }
                        .disabled(!providerProbable(id, isSTT: isSTT) || isProbing)
                    if isProbing {
                        ProgressView().controlSize(.small)
                    } else if !formMessage.isEmpty {
                        Text(formMessage).font(.system(size: 12)).foregroundStyle(SettingsDesign.rowSubtitle).lineLimit(1)
                    } else if !providerProbable(id, isSTT: isSTT) {
                        Text("该厂商暂不支持自动获取").font(.system(size: 12)).foregroundStyle(SettingsDesign.rowSubtitle)
                    }
                }
                if !fetchedModels.isEmpty {
                    Menu {
                        ForEach(fetchedModels, id: \.self) { m in
                            Button(m) { if !isSTT { llmModelBinding(id).wrappedValue = m } }
                        }
                    } label: {
                        Text("已获取 \(fetchedModels.count) 个模型，点此选用")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.primary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Divider().overlay(Palette.borderDefault)

                formField(label: "模型", required: true) {
                    if isSTT {
                        // 转写模型固定，只读展示（沿用既有「转写只读」约定）
                        Text(sttModelName(STTProviderInfo.byId(id)))
                            .font(.system(size: 14))
                            .foregroundStyle(SettingsDesign.rowSubtitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(FormFieldBox())
                    } else {
                        TextField("输入模型名称", text: llmModelBinding(id))
                            .textFieldStyle(.plain)
                            .modifier(FormFieldBox())
                    }
                }
                Text("尚未加载模型。可先获取模型，或手动输入模型名称。")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.rowSubtitle)

                Divider().overlay(Palette.borderDefault)

                advancedOptions(id: id)
            }
            .padding(32)
        }
    }

    @ViewBuilder
    private func advancedOptions(id: String) -> some View {
        Button {
            withAnimation(settingsTabAnimation) { showAdvancedOptions.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(showAdvancedOptions ? 90 : 0))
                Text("高级选项").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
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
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.borderDefault, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// 仅 OpenAI 兼容厂商可用 /models 验证与获取（STT 的火山/百炼多模态不支持）
    private func providerProbable(_ id: String, isSTT: Bool) -> Bool {
        guard isSTT else { return true }
        if case .openAICompatible = STTProviderInfo.byId(id).kind { return true }
        return false
    }

    private func probeProvider(id: String, isSTT: Bool, fetch: Bool) {
        let key = isSTT ? (sttKeys[id] ?? "") : (llmKeys[id] ?? "")
        guard !key.isEmpty else { formMessage = "请先填写 API 密钥"; return }
        let base = SettingsStore.shared.baseURL(forProvider: id, default: defaultBaseURL(id, isSTT: isSTT))
        let timeout = SettingsStore.shared.requestTimeout(forProvider: id)
        isProbing = true
        formMessage = ""
        fetchedModels = []
        Task {
            do {
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
        .buttonStyle(.plain)
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
        return VStack(alignment: .leading, spacing: 2) {
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
        .padding(4)
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
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            VStack(spacing: 12) {
                content()
            }
        }
    }

    private func settingsRow<Control: View>(title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
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
            hotkeyPicker("语音输入", subtitle: "按住说话，松开出字；点按进入锁定听写", selection: $dictationHotkey, allowNone: false)
            hotkeyPicker("翻译", subtitle: "按住说话，输出翻译目标语言的成稿", selection: $translateHotkey, allowNone: true)
            hotkeyPicker("随便问", subtitle: "按住提问，AI 的回答直接写到光标处", selection: $askHotkey, allowNone: true)
        } header: {
            Label("键盘快捷键", systemImage: "keyboard")
        } footer: {
            Text("均为按住说话的修饰键，不会干扰正常输入。三个功能请绑定不同按键。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hotkeyPicker(_ title: String, subtitle: String, selection: Binding<String>, allowNone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                HotkeyRecorder(keyRaw: selection, allowNone: allowNone)
                    .frame(width: 150, height: 22)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("交互声音")
                    Text("为开始/停止等关键操作播放声音")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $muteWhileDictating) {
                VStack(alignment: .leading, spacing: 2) {
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
                VStack(alignment: .leading, spacing: 2) {
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
                VStack(alignment: .leading, spacing: 2) {
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
            Picker("本地引擎", selection: $localEngine) {
                Text("Apple 设备端听写（零下载）").tag("apple")
                Text("Whisper 离线模型（更准，自动检测语言）").tag("whispercpp")
            }
            if localEngine == "whispercpp" {
                Picker("模型", selection: $whisperModelId) {
                    ForEach(WhisperModel.all) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                whisperModelStatus
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

    @ViewBuilder
    private var whisperModelStatus: some View {
        let model = WhisperModel.byId(whisperModelId)
        if model.isDownloaded {
            Label("模型已就绪", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
        } else if downloader.downloadingId == model.id {
            HStack {
                ProgressView(value: downloader.progress)
                Text("\(Int(downloader.progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }
        } else {
            Button("下载模型（约 \(model.sizeMB)MB）") {
                downloader.download(model)
            }
            if let error = downloader.errorMessage {
                Text(error).font(.caption).foregroundStyle(Palette.danger)
            }
        }
    }

    // MARK: AI 润色

    private var polishSection: some View {
        Section {
            Toggle(isOn: $polishEnabled) {
                VStack(alignment: .leading, spacing: 2) {
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
