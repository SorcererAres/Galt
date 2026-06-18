import AppKit

/// 听写编排：热键触发录音 → 引擎路由转写 → 按模式后处理（润色/翻译/问答）→ 注入光标
/// 触发方式：按住热键说话（hold-to-talk）、点按热键锁定听写（再次点按结束）
final class DictationController {
    private let recorder = AudioRecorder()
    private let hud = HUDController()
    private let cloud = CloudSTTProvider()
    private let appleLocal = AppleSpeechProvider()
    private let whisperLocal = WhisperCppProvider()
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
        SettingsStore.shared.localEngine == "whispercpp" ? whisperLocal : appleLocal
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

    private func startRecording() {
        // 语音编辑只在普通听写模式下生效
        pendingSelection = (activeMode == .dictation) ? SelectionReader.selectedText() : nil
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

        let duration = recorder.lastDuration
        let front = NSWorkspace.shared.frontmostApplication
        let appName = front?.localizedName
        let bundleId = front?.bundleIdentifier
        let selection = pendingSelection
        let mode = activeMode
        pendingSelection = nil
        hud.state.phase = .processing

        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.transcribe(wav: wav)
                let final = try await self.postProcess(
                    raw, mode: mode, selection: selection, appName: appName, bundleId: bundleId
                )
                DispatchQueue.main.async {
                    let pasted = TextInjector.inject(final)
                    HistoryStore.shared.append(HistoryRecord(
                        date: Date(), app: appName, bundleId: bundleId, duration: duration, raw: raw, text: final
                    ))
                    if pasted {
                        self.hud.state.phase = .success(final)
                        self.hud.hide(after: 1.8)
                    } else {
                        self.hud.state.phase = .error("已复制到剪贴板，可手动 ⌘V")
                        self.hud.hide(after: 3)
                    }
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.hud.state.phase = .error(message)
                    self.hud.hide(after: 3.5)
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
        bundleId: String?
    ) async throws -> String {
        switch mode {
        case .dictation:
            if let selection {
                // 语音编辑：口述内容作为指令，改写选中文本（粘贴时自动替换选区）
                return try await polisher.edit(selection, instruction: raw, appName: appName)
            }
            if SettingsStore.shared.polishEnabled,
               let polished = try? await polisher.polish(raw, appName: appName, bundleId: bundleId) {
                return polished
            }
            return raw
        case .translate:
            let target = SettingsStore.shared.translationTargetName ?? "英文"
            return try await polisher.polish(raw, appName: appName, bundleId: bundleId, forceTranslationTo: target)
        case .ask:
            return try await polisher.answer(raw, appName: appName)
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
