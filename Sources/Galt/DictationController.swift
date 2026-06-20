import AppKit

/// 流式增量出字会话：边生成边逐字键入，失败时撤销半成品。
/// 回滚（按字符数发退格）只有在焦点仍停在键入时那个 App 才安全——否则会删到别处，
/// 故记录起始前台 App，回滚前比对，App 已切走就放弃撤销而非误删用户内容。
private final class StreamInsertionSession {
    private(set) var typedText = ""
    /// 首次键入时的前台 App PID，作为回滚安全性判据
    private var startAppPID: pid_t?

    var typedAny: Bool {
        !typedText.isEmpty
    }

    func type(_ text: String) {
        if typedText.isEmpty {
            startAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        guard TextInjector.typeIncremental(text) else { return }
        typedText += text
    }

    /// 撤销已键入的半成品。返回 true 表示已干净回滚（或本就没键入）；
    /// false 表示因前台 App 已切换而放弃退格——半成品仍留在原 App，调用方应提示用户。
    @discardableResult
    func rollback() -> Bool {
        guard !typedText.isEmpty else { return true }
        let nowPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard nowPID == startAppPID else {
            typedText = ""
            return false
        }
        TextInjector.deleteBackward(characterCount: typedText.count)
        typedText = ""
        return true
    }
}

/// 听写编排：热键触发录音 → 引擎路由转写 → 按模式后处理（润色/翻译/问答）→ 注入光标
/// 触发方式：按住热键说话（hold-to-talk）、点按热键锁定听写（再次点按结束）
final class DictationController {
    private let recorder = AudioRecorder()
    private let hud = HUDController()
    private let cloud = CloudSTTProvider()
    private let appleLocal = AppleSpeechProvider()
    private let whisperLocal = WhisperCppProvider()
    private let sherpaLocal = SherpaOnnxProvider()
    private let polisher = Polisher()
    private var sessionTimer: Timer?
    private var keyDownAt: Date?
    private var locked = false
    private var activeMode: DictationMode = .dictation
    /// 录音开始时捕获的选中文本；非空则本次为「语音编辑」模式
    private var pendingSelection: String?

    /// 录音活动状态变化（true=正在采集）；用于驱动菜单栏图标等外部指示
    var onActiveChange: ((Bool) -> Void)?

    /// 点按判定阈值：按下到松开短于该值视为「点按」，进入锁定听写
    private let tapThreshold: TimeInterval = 0.35

    /// 当前生效的本地引擎
    private var local: STTProvider {
        switch SettingsStore.shared.localEngine {
        case "whispercpp": return whisperLocal
        case "sherpa": return sherpaLocal
        default: return appleLocal
        }
    }

    init() {
        recorder.onLevel = { [weak self] level in
            self?.hud.state.level = level
        }
        // 锁定听写时 HUD 上的「确认 ✓」按钮：与再次点按热键等价
        hud.onStopRequested = { [weak self] in
            self?.finishDictation()
        }
        // 「取消 ✕」按钮：丢弃本次录音，不转写、不出字
        hud.onCancelRequested = { [weak self] in
            self?.cancelDictation()
        }
        // 失败态「重试」：用保留的音频重跑；「关闭 ✕」：放弃重试并收起
        hud.onRetryRequested = { [weak self] in
            self?.retry()
        }
        hud.onDismissRequested = { [weak self] in
            self?.dismissFailure()
        }
        // 成功态「撤销」：删除刚插入的文本
        hud.onUndoRequested = { [weak self] in
            self?.undo()
        }
    }

    // MARK: - 热键入口

    func keyDown(_ mode: DictationMode) {
        if locked {
            finishDictation() // 锁定中再次按下 → 结束
            return
        }
        guard !recorder.isRecording else { return }
        activeMode = mode
        keyDownAt = Date()
        startRecording()
    }

    func keyUp(_ mode: DictationMode) {
        guard recorder.isRecording, !locked, mode == activeMode else { return }
        if let down = keyDownAt, Date().timeIntervalSince(down) < tapThreshold {
            locked = true
            hud.state.phase = .recording(locked: true, editing: pendingSelection != nil, mode: activeMode)
            return
        }
        finishDictation()
    }

    // MARK: - 流程

    /// 本次会话是否会调用 LLM（决定要不要预热连接）
    private var willUseLLM: Bool {
        switch activeMode {
        case .translate, .ask:
            return true
        case .dictation:
            return pendingSelection != nil || SettingsStore.shared.polishEnabled
        }
    }

    private func startRecording() {
        // 开始新录音即放弃上一次失败遗留的重试任务
        lastFailedJob = nil
        // 语音编辑只在普通听写模式下生效
        pendingSelection = (activeMode == .dictation) ? SelectionReader.selectedText() : nil
        // 本次会用到 LLM（翻译/问答，或开启润色/语音编辑）时，趁说话间隙预热连接
        if willUseLLM { Polisher.prewarm() }
        if SettingsStore.shared.muteWhileDictating {
            AudioDucker.shared.mute()
        }
        do {
            try recorder.start()
            if SettingsStore.shared.soundFeedback {
                NSSound(named: "Pop")?.play()
            }
            hud.state.phase = .recording(locked: false, editing: pendingSelection != nil, mode: activeMode)
            hud.show()
            onActiveChange?(true)
            // 单次会话时长上限，自动收尾
            sessionTimer = Timer.scheduledTimer(
                withTimeInterval: SettingsStore.shared.maxSessionSeconds,
                repeats: false
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.finishDictation() }
            }
        } catch {
            AudioDucker.shared.restore()
            hud.state.phase = .error("无法启动录音：\(error.localizedDescription)")
            hud.show()
            hud.hide(after: 2.5)
        }
    }

    /// 取消听写：停止采集并丢弃音频，不进入转写流程
    private func cancelDictation() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        locked = false
        pendingSelection = nil
        guard recorder.isRecording else { return }
        _ = recorder.stop()
        onActiveChange?(false)
        AudioDucker.shared.restore()
        if SettingsStore.shared.soundFeedback {
            NSSound(named: "Tink")?.play()
        }
        hud.hide()
    }

    private func finishDictation() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        locked = false
        guard recorder.isRecording else { return }

        let wav = recorder.stop()
        onActiveChange?(false)
        AudioDucker.shared.restore()
        if SettingsStore.shared.soundFeedback {
            NSSound(named: "Tink")?.play()
        }
        guard let wav else {
            // 录音过短或无声：给一次轻量反馈再淡出，避免用户以为热键失效
            hud.state.phase = .empty
            hud.hide(after: 1.2)
            return
        }

        let front = NSWorkspace.shared.frontmostApplication
        let job = PendingJob(
            wav: wav,
            duration: recorder.lastDuration,
            mode: activeMode,
            selection: pendingSelection,
            appName: front?.localizedName,
            bundleId: front?.bundleIdentifier
        )
        pendingSelection = nil
        runJob(job)
    }

    /// 一次转写任务的完整上下文。失败后据此原样重试，无需重新口述。
    private struct PendingJob {
        let wav: Data
        let duration: TimeInterval
        let mode: DictationMode
        let selection: String?
        let appName: String?
        let bundleId: String?

        /// 本次是否会经过 LLM（决定转写后是否切到「正在润色」文案）
        var usesLLM: Bool {
            switch mode {
            case .translate, .ask: return true
            case .dictation: return selection != nil || SettingsStore.shared.polishEnabled
            }
        }
    }

    /// 上次失败、可重试的任务；nil 表示当前无可重试项
    private var lastFailedJob: PendingJob?

    /// 一次成功插入的最小信息，供成功态「撤销」回退
    private struct LastInsertion {
        let charCount: Int              // 已插入的字符数（退格回退用）
        let appPID: pid_t?              // 插入时的前台 App，撤销前比对，切走则放弃
        let replacedSelection: String?  // 语音编辑被替换掉的原文；撤销后重新键回
    }

    /// 最近一次成功插入；nil 表示无可撤销项
    private var lastInsertion: LastInsertion?

    /// 用户点击 HUD 失败态的「重试」：用保留的音频重走转写→润色→出字
    func retry() {
        guard let job = lastFailedJob else { return }
        lastFailedJob = nil
        runJob(job)
    }

    /// 用户点击失败态的「关闭」：放弃重试并收起 HUD
    func dismissFailure() {
        lastFailedJob = nil
        hud.hide()
    }

    /// 用户点击成功态「撤销」：删除刚插入的文本；语音编辑则把被替换的原文键回。
    /// 仅在焦点仍停在插入时那个 App 才动手，避免删到别处。
    func undo() {
        defer { hud.hide() }
        guard let ins = lastInsertion, ins.charCount > 0 else { return }
        lastInsertion = nil
        let nowPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard nowPID == ins.appPID else { return }
        TextInjector.deleteBackward(characterCount: ins.charCount)
        if let original = ins.replacedSelection, !original.isEmpty {
            TextInjector.typeIncremental(original)
        }
    }

    /// 执行（或重试）一次转写任务：转写 → 按模式后处理 → 注入光标。
    /// 失败时保留 job 并切到可重试的失败态。
    private func runJob(_ job: PendingJob) {
        hud.cancelScheduledHide() // 取消失败态排期的自动淡出（重试场景）
        hud.state.phase = .processing(.transcribing)

        // 有辅助功能权限时启用流式增量出字：边生成边键入，体感延迟降到「首字延迟」级别
        let streamSession = AXIsProcessTrusted() ? StreamInsertionSession() : nil
        Task { [weak self, streamSession] in
            guard let self else { return }
            do {
                let raw = try await self.transcribe(wav: job.wav)
                // 转写完成、进入 LLM 阶段前切换文案；纯听写（无润色）则保持「正在转写」直到出字
                if job.usesLLM {
                    await MainActor.run { self.hud.state.phase = .processing(.polishing) }
                }
                let onDelta: (@MainActor (String) -> Void)? = streamSession.map { session in
                    { piece in session.type(piece) }
                }
                let final = try await self.postProcess(
                    raw, mode: job.mode, selection: job.selection,
                    appName: job.appName, bundleId: job.bundleId, onDelta: onDelta
                )
                await MainActor.run {
                    self.lastFailedJob = nil
                    // 已逐字键入（CGEvent 直接键入，不经剪贴板）则无需再注入，且保持用户剪贴板不被污染
                    let pasted: Bool
                    let insertedCount: Int
                    if streamSession?.typedAny == true {
                        pasted = true
                        insertedCount = streamSession?.typedText.count ?? 0
                    } else {
                        pasted = TextInjector.inject(final)
                        insertedCount = final.count
                    }
                    HistoryStore.shared.append(HistoryRecord(
                        date: Date(), app: job.appName, bundleId: job.bundleId,
                        duration: job.duration, raw: raw, text: final
                    ))
                    if pasted {
                        // 记录本次插入，供成功态「撤销」（焦点守卫用出字时刻的前台 App）
                        self.lastInsertion = LastInsertion(
                            charCount: insertedCount,
                            appPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                            replacedSelection: job.selection
                        )
                        self.hud.state.phase = .success(final)
                        self.hud.hide(after: 3)
                    } else {
                        self.lastInsertion = nil
                        self.hud.state.phase = .error("已复制到剪贴板，可手动 ⌘V")
                        self.hud.hide(after: 3)
                    }
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    // 仅在焦点仍在原 App 时安全撤销半成品；已切走则放弃退格、如实提示
                    let cleanlyRolledBack = streamSession?.rollback() ?? true
                    // 保留本次音频：失败态提供「重试」，避免从头再说一遍
                    self.lastFailedJob = job
                    self.hud.state.phase = .failure(
                        cleanlyRolledBack ? message : "\(message)（部分文字已输入，请检查）"
                    )
                    // 失败态等待用户操作，不主动淡出；超时兜底防止 HUD 永久悬挂
                    self.hud.hide(after: 12)
                }
            }
        }
    }

    /// 按模式后处理转写稿
    private func postProcess(
        _ raw: String,
        mode: DictationMode,
        selection: String?,
        appName: String?,
        bundleId: String?,
        onDelta: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        switch mode {
        case .dictation:
            if let selection {
                // 语音编辑：口述内容作为指令，改写选中文本（首个字符自动替换选区）
                return try await polisher.edit(selection, instruction: raw, appName: appName, onDelta: onDelta)
            }
            if SettingsStore.shared.polishEnabled {
                if onDelta != nil {
                    return try await polisher.polish(raw, appName: appName, bundleId: bundleId, onDelta: onDelta)
                }
                if let polished = try? await polisher.polish(raw, appName: appName, bundleId: bundleId) {
                    return polished
                }
            }
            return raw
        case .translate:
            let target = SettingsStore.shared.translationTargetName ?? "英文"
            return try await polisher.polish(raw, appName: appName, bundleId: bundleId, forceTranslationTo: target, onDelta: onDelta)
        case .ask:
            return try await polisher.answer(raw, appName: appName, onDelta: onDelta)
        }
    }

    /// 引擎路由：自动模式下云端优先、本地离线兜底
    private func transcribe(wav: Data) async throws -> String {
        switch SettingsStore.shared.engineMode {
        case "cloud":
            return try await cloud.transcribe(wav: wav)
        case "local":
            return try await local.transcribe(wav: wav)
        default:
            let settings = SettingsStore.shared
            guard !settings.sttKey(forProvider: settings.cloudSTTProviderId).isEmpty else {
                return try await local.transcribe(wav: wav)
            }
            do {
                return try await cloud.transcribe(wav: wav)
            } catch {
                NSLog("Galt: 云端转写失败，回退本地引擎：\(error.localizedDescription)")
                return try await local.transcribe(wav: wav)
            }
        }
    }
}
