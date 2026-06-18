import Foundation
import AppKit

/// 应用设置（UserDefaults 持久化；API Key 计划在 M3 迁移至 Keychain）
final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    private var cachedAPIKey: String?

    /// Groq API Key：钥匙串加密存储；旧版 UserDefaults 明文自动迁移；兜底环境变量 GROQ_API_KEY
    var groqAPIKey: String {
        get {
            if let cachedAPIKey { return cachedAPIKey }
            if let saved = KeychainStore.get("groqAPIKey"), !saved.isEmpty {
                cachedAPIKey = saved
                return saved
            }
            if let legacy = defaults.string(forKey: "groqAPIKey"), !legacy.isEmpty {
                KeychainStore.set(legacy, account: "groqAPIKey")
                defaults.removeObject(forKey: "groqAPIKey")
                cachedAPIKey = legacy
                return legacy
            }
            return ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
        }
        set {
            cachedAPIKey = newValue
            KeychainStore.set(newValue, account: "groqAPIKey")
            defaults.removeObject(forKey: "groqAPIKey")
        }
    }

    /// 是否启用 LLM 润色（默认开启）
    var polishEnabled: Bool {
        get { defaults.object(forKey: "polishEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "polishEnabled") }
    }

    /// 转写引擎模式："auto"（云端优先，离线兜底）| "cloud" | "local"
    var engineMode: String {
        get { defaults.string(forKey: "engineMode") ?? "auto" }
        set { defaults.set(newValue, forKey: "engineMode") }
    }

    /// 本地引擎（Apple Speech）识别语言
    var localLocaleId: String {
        get { defaults.string(forKey: "localLocaleId") ?? "zh-CN" }
        set { defaults.set(newValue, forKey: "localLocaleId") }
    }

    /// 本地离线引擎："apple"（设备端听写）| "whispercpp"（Whisper 离线模型）
    var localEngine: String {
        get { defaults.string(forKey: "localEngine") ?? "apple" }
        set { defaults.set(newValue, forKey: "localEngine") }
    }

    /// whisper.cpp 使用的模型 id
    var whisperModelId: String {
        get { defaults.string(forKey: "whisperModelId") ?? "small-q5_1" }
        set { defaults.set(newValue, forKey: "whisperModelId") }
    }

    /// 个人词典：设置面板中每行一个词，存为整段文本
    var dictionaryTerms: [String] {
        let text = defaults.string(forKey: "dictionaryTermsText") ?? ""
        return text
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 翻译模式目标语言："off" 关闭，或 "zh-Hans" / "en" / "ja"
    var translationTarget: String {
        get { defaults.string(forKey: "translationTarget") ?? "off" }
        set { defaults.set(newValue, forKey: "translationTarget") }
    }

    /// 翻译目标语言的显示名；关闭时返回 nil
    var translationTargetName: String? {
        switch translationTarget {
        case "zh-Hans": return "简体中文"
        case "en": return "英文"
        case "ja": return "日文"
        default: return nil
        }
    }

    /// 首次启动引导状态
    var hasCompletedOnboarding: Bool {
        get { defaults.object(forKey: "hasCompletedOnboarding") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var onboardingVersion: Int {
        get { defaults.integer(forKey: "onboardingVersion") }
        set { defaults.set(newValue, forKey: "onboardingVersion") }
    }

    func resetOnboarding() {
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "onboardingVersion")
    }

    /// 转写模型与润色模型
    let sttModel = "whisper-large-v3-turbo"
    let polishModel = "llama-3.3-70b-versatile"

    /// 单次听写时长上限（秒），对齐 Typeless 的 6 分钟
    let maxSessionSeconds: TimeInterval = 360

    /// 外观："system" 跟随系统 | "light" | "dark"
    var appearance: String {
        get { defaults.string(forKey: "appearance") ?? "system" }
        set { defaults.set(newValue, forKey: "appearance") }
    }

    /// 听写历史保存天数（0 表示永久保留，超期记录会被清理）
    var historyRetentionDays: Int {
        get { defaults.integer(forKey: "historyRetentionDays") }
        set { defaults.set(newValue, forKey: "historyRetentionDays") }
    }

    /// 厂商自定义接口地址（模型库填写，空则用厂商默认 base）
    func baseURL(forProvider id: String, default def: String) -> String {
        let saved = (defaults.string(forKey: "providerBase.\(id)") ?? "").trimmingCharacters(in: .whitespaces)
        return saved.isEmpty ? def : saved
    }

    /// 厂商请求超时（秒）；模型库「高级选项」填写，未设或非法时默认 60
    func requestTimeout(forProvider id: String) -> TimeInterval {
        let raw = defaults.string(forKey: "providerAdv.timeout.\(id)") ?? ""
        let num = Double(raw.prefix(while: { $0.isNumber || $0 == "." })) ?? 0
        return num > 0 ? num : 60
    }

    // MARK: 键盘快捷键（HotkeyKey 的 rawValue，"none" 表示未绑定）

    var dictationHotkey: String {
        get { defaults.string(forKey: "dictationHotkey") ?? "fn" }
        set { defaults.set(newValue, forKey: "dictationHotkey") }
    }

    var translateHotkey: String {
        get { defaults.string(forKey: "translateHotkey") ?? "none" }
        set { defaults.set(newValue, forKey: "translateHotkey") }
    }

    var askHotkey: String {
        get { defaults.string(forKey: "askHotkey") ?? "none" }
        set { defaults.set(newValue, forKey: "askHotkey") }
    }

    // MARK: 音频

    /// 麦克风设备 UID，"auto" 为系统默认
    var micDeviceUID: String {
        get { defaults.string(forKey: "micDeviceUID") ?? "auto" }
        set { defaults.set(newValue, forKey: "micDeviceUID") }
    }

    /// 开始/结束时播放提示音
    var soundFeedback: Bool {
        get { defaults.object(forKey: "soundFeedback") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundFeedback") }
    }

    /// 听写时静音其它音频
    var muteWhileDictating: Bool {
        get { defaults.object(forKey: "muteWhileDictating") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "muteWhileDictating") }
    }

    /// 在 Dock 中显示应用图标
    var showInDock: Bool {
        get { defaults.object(forKey: "showInDock") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showInDock") }
    }

    // MARK: 云端厂商

    /// 当前云端转写厂商 id（见 STTProviderInfo.all）
    var cloudSTTProviderId: String {
        get { defaults.string(forKey: "cloudSTTProviderId") ?? "groq" }
        set { defaults.set(newValue, forKey: "cloudSTTProviderId") }
    }

    /// 当前 LLM 厂商 id（润色/翻译/语音编辑/随便问，见 LLMProviderInfo.all）
    var llmProviderId: String {
        get { defaults.string(forKey: "llmProviderId") ?? "groq" }
        set { defaults.set(newValue, forKey: "llmProviderId") }
    }

    /// 指定厂商的转写 Key（钥匙串；Groq 兼容旧版迁移）
    func sttKey(forProvider id: String) -> String {
        if let saved = KeychainStore.get("stt.\(id)"), !saved.isEmpty { return saved }
        if id == "groq" { return groqAPIKey }
        return ""
    }

    func setSTTKey(_ value: String, forProvider id: String) {
        KeychainStore.set(value, account: "stt.\(id)")
    }

    /// 火山引擎转写的 App ID（X-Api-App-Key）
    var volcanoAppKey: String {
        get { KeychainStore.get("stt.volcano.app") ?? "" }
        set { KeychainStore.set(newValue, account: "stt.volcano.app") }
    }

    // MARK: 火山 ASR 模型（协议 + 资源 + 接口，可由预设带出或自填）

    /// 传输协议（VolcanoASRProtocol.rawValue：flash / streaming）
    var volcanoProtocol: String {
        get { defaults.string(forKey: "volcano.protocol") ?? VolcanoASRModel.default.proto.rawValue }
        set { defaults.set(newValue, forKey: "volcano.protocol") }
    }

    /// X-Api-Resource-Id
    var volcanoResourceId: String {
        get {
            let s = (defaults.string(forKey: "volcano.resourceId") ?? "").trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? VolcanoASRModel.default.resourceId : s
        }
        set { defaults.set(newValue, forKey: "volcano.resourceId") }
    }

    /// 接口地址（flash 为 https，streaming 为 wss）
    var volcanoEndpoint: String {
        get {
            let s = (defaults.string(forKey: "volcano.endpoint") ?? "").trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? VolcanoASRModel.default.endpoint : s
        }
        set { defaults.set(newValue, forKey: "volcano.endpoint") }
    }

    /// 指定 LLM 厂商的 Key（钥匙串；Groq 兼容旧版迁移）
    func llmKey(forProvider id: String) -> String {
        if let saved = KeychainStore.get("llm.\(id)"), !saved.isEmpty { return saved }
        if id == "groq" { return groqAPIKey }
        return ""
    }

    func setLLMKey(_ value: String, forProvider id: String) {
        KeychainStore.set(value, account: "llm.\(id)")
    }

    /// 指定 LLM 厂商使用的模型（可在设置中覆盖默认值）
    func llmModel(forProvider id: String) -> String {
        if let saved = defaults.string(forKey: "llmModel.\(id)"), !saved.isEmpty { return saved }
        return LLMProviderInfo.byId(id).defaultModel
    }

    func setLLMModel(_ value: String, forProvider id: String) {
        defaults.set(value, forKey: "llmModel.\(id)")
    }
}

extension SettingsStore {
    /// 应用外观设置到全局窗口（控制台/设置/HUD 同步生效）
    func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    /// 应用 Dock 图标显示策略
    func applyDockVisibility() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}
