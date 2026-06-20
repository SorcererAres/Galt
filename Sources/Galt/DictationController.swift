import AppKit

/// 流式增量出字会话：边生成边逐字键入，失败时撤销半成品。
/// 回滚（按字符数发退格）只有在焦点仍停在键入时那个 App 才安全——否则会删到别处，
/// 故记录起始前台 App，回滚前比对，App 已切走就放弃撤销而非误删用户内容。
private final class StreamInsertionSession {
    private(set) var typedText = ""
    /// 首次键入时的前台 App PID，作为回滚安全性判据
    private var startAppPID: pid_t?
    /// 被取消（如用户按 ESC 中断）后不再键入新增量，避免回滚后又被在途流式增量写入残留
    private var canceled = false

    var typedAny: Bool {
        !typedText.isEmpty
    }

    /// 标记取消：之后的 type(_:) 全部忽略
    func cancel() {
        canceled = true
    }

    func type(_ text: String) {
        guard !canceled else { return }
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
    private let editLearner = EditLearner()
    /// 录音时长倒计时（1Hz）；同时承担到达上限自动收尾
    private var countdownTimer: Timer?
    /// 引擎真正开始采集的时刻，倒计时由此起算
    private var recordingStartedAt: Date?
    private var keyDownAt: Date?
    private var locked = false
    private var activeMode: DictationMode = .dictation
    /// 录音开始时捕获的选中文本；非空则本次为「语音编辑」模式
    private var pendingSelection: String?

    // MARK: 启动竞态（recorder.start() 异步执行期间的松手/取消处理）

    /// 引擎就绪后要兑现的动作（启动期间用户已松手或已请求取消）
    private enum StartupAction { case none, lockOnReady, finishOnReady, cancelOnReady }
    /// 是否正处于「已按下、引擎尚未就绪」的启动窗口
    private var isStarting = false
    /// 启动代际：新会话顶替旧会话时令旧的 start() 结果作废
    private var startupGen = 0
    private var pendingStartupAction: StartupAction = .none
    /// 教学提示自动清除的延时任务
    private var hintClearWork: DispatchWorkItem?

    // MARK: ESC 取消与任务代际

    private let escMonitor = EscMonitor()
    /// 转写任务代际：ESC 中断时自增，使在途任务的回调失效、不再污染 UI / 不再注入
    private var jobGen = 0
    /// 当前在途转写任务
    private var currentJob: Task<Void, Never>?
    /// 当前在途任务的「回滚已键入半成品」闭包（ESC 中断时调用）
    private var currentRollback: (() -> Void)?

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
        // ESC：录音中等同取消、处理中中断任务并回滚半成品（按相位分流）
        escMonitor.onEsc = { [weak self] in self?.handleEsc() }
        // 仅在听写进行中（唤醒/录音/处理/失败等待）挂载 ESC 监听，回到空闲即卸载
        hud.onPhaseChanged = { [weak self] phase in self?.syncEscMonitor(for: phase) }
        // 定时回看学到新词：空闲时给一条轻量提示（录音中不打断）
        editLearner.onLearned = { [weak self] term in
            guard let self, !self.recorder.isRecording else { return }
            self.hud.state.phase = .info("已学习「\(term)」")
            self.hud.show()
            self.hud.hide(after: 2)
        }
        observeSystemInterruptions()
    }

    /// 监听系统休眠 / 锁屏 / 屏保：录音中途遇到这些就丢弃本次采集，
    /// 避免录音悬挂、或把锁屏后的环境音误转写。
    private func observeSystemInterruptions() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleSystemInterruption() }

        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            dnc.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in self?.handleSystemInterruption() }
        }
    }

    /// 系统中断（休眠/锁屏/屏保）时收尾：录音中（含启动窗口）丢弃本次采集
    private func handleSystemInterruption() {
        if isStarting { pendingStartupAction = .cancelOnReady; return }
        guard recorder.isRecording else { return }
        cancelDictation()
    }

    // MARK: - 热键入口

    func keyDown(_ mode: DictationMode) {
        // 全局暂停：忽略热键（不录音、不出字），用于全屏/游戏/会议等避免误触
        if SettingsStore.shared.dictationPaused { return }
        if locked {
            finishDictation() // 锁定中再次按下 → 结束
            return
        }
        // 启动窗口内或已在录音：忽略重复按下
        guard !recorder.isRecording, !isStarting else { return }
        activeMode = mode
        keyDownAt = Date()
        startRecording()
    }

    func keyUp(_ mode: DictationMode) {
        // 引擎尚未就绪就松手：按 tap/hold 记下意图，待 ready 后兑现（取消优先，不被覆盖）
        if isStarting, mode == activeMode {
            guard pendingStartupAction != .cancelOnReady else { return }
            if let down = keyDownAt, Date().timeIntervalSince(down) < tapThreshold {
                pendingStartupAction = .lockOnReady
            } else {
                pendingStartupAction = .finishOnReady
            }
            return
        }
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
        // 在采集前回看上一次插入：若用户做了就地纠正，静默学习（不弹提示，马上要进录音态）
        editLearner.recheck()
        // 语音编辑只在普通听写模式下生效
        pendingSelection = (activeMode == .dictation) ? SelectionReader.selectedText() : nil
        // 本次会用到 LLM（翻译/问答，或开启润色/语音编辑）时，趁说话间隙预热连接
        if willUseLLM { Polisher.prewarm() }
        if SettingsStore.shared.muteWhileDictating {
            AudioDucker.shared.mute()
        }

        // 进入启动窗口：recorder.start() 放到后台执行，避免引擎启动短暂阻塞主线程；
        // 主线程经 0.12s 防抖才呈现「唤醒中」胶囊，启动够快时直接进录音态、不闪 loading。
        isStarting = true
        pendingStartupAction = .none
        startupGen += 1
        let gen = startupGen
        let mode = activeMode

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.isStarting, self.startupGen == gen else { return }
            self.hud.state.phase = .starting(mode: mode)
            self.hud.show()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.recorder.start()
                DispatchQueue.main.async { self.handleRecorderStarted(gen: gen) }
            } catch {
                DispatchQueue.main.async { self.handleRecorderStartFailed(gen: gen, error: error) }
            }
        }
    }

    /// 引擎就绪（主线程）：进入录音态并兑现启动窗口内累积的松手/取消意图
    private func handleRecorderStarted(gen: Int) {
        // 已被新会话顶替：丢弃这次启动结果，避免悬挂的引擎
        guard gen == startupGen else {
            _ = recorder.stop()
            return
        }
        isStarting = false
        // 启动期间已请求取消（ESC / 系统中断）：录音刚起即丢弃
        if pendingStartupAction == .cancelOnReady {
            pendingStartupAction = .none
            cancelDictation()
            return
        }
        if SettingsStore.shared.soundFeedback {
            NSSound(named: "Pop")?.play()
        }
        recordingStartedAt = Date()
        locked = (pendingStartupAction == .lockOnReady)
        hud.state.phase = .recording(locked: locked, editing: pendingSelection != nil, mode: activeMode)
        hud.show()
        onActiveChange?(true)
        startCountdown()
        maybeShowHint()
        // 启动期间「按住后松手」：补一次结束
        if pendingStartupAction == .finishOnReady {
            pendingStartupAction = .none
            finishDictation()
            return
        }
        pendingStartupAction = .none
    }

    /// 引擎启动失败（主线程）：复用错误态短暂提示后淡出
    private func handleRecorderStartFailed(gen: Int, error: Error) {
        guard gen == startupGen else { return }
        isStarting = false
        pendingStartupAction = .none
        AudioDucker.shared.restore()
        hud.state.phase = .error("无法启动录音：\(error.localizedDescription)")
        hud.show()
        hud.hide(after: 2.5)
    }

    // MARK: - 倒计时 / 教学提示

    /// 起 1Hz 倒计时：更新剩余秒数，到达上限自动收尾
    private func startCountdown() {
        countdownTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
        tickCountdown()
    }

    private func tickCountdown() {
        guard let started = recordingStartedAt else { return }
        let remaining = Int(ceil(SettingsStore.shared.maxSessionSeconds - Date().timeIntervalSince(started)))
        if remaining <= 0 {
            finishDictation()
            return
        }
        hud.state.remainingSeconds = remaining
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recordingStartedAt = nil
        hud.state.remainingSeconds = nil
    }

    /// 前若干次录音在胶囊下方短暂展示交互教学提示，达上限后不再打扰
    private func maybeShowHint() {
        let settings = SettingsStore.shared
        guard settings.dictationHintShownCount < settings.dictationHintMaxShows else { return }
        settings.dictationHintShownCount += 1
        hud.state.recordingHint = "按住说话，松开结束 · 轻点可锁定"
        hintClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hud.state.recordingHint = nil }
        hintClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func clearHint() {
        hintClearWork?.cancel()
        hintClearWork = nil
        hud.state.recordingHint = nil
    }

    // MARK: - ESC 取消

    /// 按相位挂载/卸载 ESC 监听：仅听写进行中需要它
    private func syncEscMonitor(for phase: HUDPhase) {
        switch phase {
        case .starting, .recording, .processing, .failure:
            escMonitor.install()
        default:
            escMonitor.uninstall()
        }
    }

    /// ESC 分流：录音/唤醒态丢弃本次；处理中中断任务并回滚半成品；失败态等同关闭
    private func handleEsc() {
        switch hud.state.phase {
        case .starting, .recording:
            cancelDictation()
        case .processing:
            cancelProcessing()
        case .failure:
            dismissFailure()
        default:
            break
        }
    }

    /// 中断在途转写/润色：作废任务回调、回滚已逐字键入的半成品、收起 HUD
    private func cancelProcessing() {
        jobGen += 1
        currentJob?.cancel()
        currentJob = nil
        currentRollback?()
        currentRollback = nil
        lastFailedJob = nil
        AudioDucker.shared.restore()
        clearHint()
        hud.hide()
    }

    /// 取消听写：停止采集并丢弃音频，不进入转写流程
    private func cancelDictation() {
        // 引擎尚未就绪：待 ready 后立即丢弃
        if isStarting {
            pendingStartupAction = .cancelOnReady
            return
        }
        stopCountdown()
        clearHint()
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
        // 引擎尚未就绪：待 ready 后补一次结束
        if isStarting {
            pendingStartupAction = .finishOnReady
            return
        }
        stopCountdown()
        clearHint()
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
        // 撤销即作废这次插入的自学习快照，避免把「整段删掉」误判成纠正
        editLearner.cancel()
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

        // 新任务代际：ESC 中断时自增此值，使在途任务的回调失效
        jobGen += 1
        let gen = jobGen

        // ask 模式：结果进浮动卡片（不键入光标）；其余模式有辅助功能权限则流式增量出字
        let useCard = (job.mode == .ask)
        let streamSession = (!useCard && AXIsProcessTrusted()) ? StreamInsertionSession() : nil
        // ESC 中断时：先封停流式键入再回滚已键入的半成品
        currentRollback = streamSession.map { session in { session.cancel(); _ = session.rollback() } }
        currentJob = Task { [weak self, streamSession] in
            guard let self else { return }
            do {
                let raw = try await self.transcribe(wav: job.wav)
                let rawHasContent = !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                // 转写完成、进入 LLM 阶段前切换文案；纯听写（无润色）则保持「正在转写」直到出字
                if job.usesLLM {
                    await MainActor.run {
                        guard gen == self.jobGen else { return }
                        self.hud.state.phase = .processing(.polishing)
                    }
                }
                // ask 模式：转写有内容即开卡片、收起 HUD，答案流式填进卡片
                if useCard && rawHasContent {
                    await MainActor.run {
                        guard gen == self.jobGen else { return }
                        self.hud.hide()
                        ResultCardController.shared.begin(title: "回答")
                    }
                }
                let onDelta: (@MainActor (String) -> Void)?
                if useCard {
                    onDelta = { piece in ResultCardController.shared.append(piece) }
                } else {
                    onDelta = streamSession.map { session in { piece in session.type(piece) } }
                }
                let final = try await self.postProcess(
                    raw, mode: job.mode, selection: job.selection,
                    appName: job.appName, bundleId: job.bundleId, onDelta: onDelta
                )
                await MainActor.run {
                    // 已被 ESC 中断（代际失效）：不改 HUD、不注入、不记历史
                    guard gen == self.jobGen else { return }
                    self.currentJob = nil
                    self.currentRollback = nil
                    self.lastFailedJob = nil
                    // ask 模式：结果落在卡片，不注入光标、不记 lastInsertion（无可撤销项）
                    if useCard {
                        self.lastInsertion = nil
                        if final.isEmpty {
                            ResultCardController.shared.close()
                            self.hud.state.phase = .empty
                            self.hud.hide(after: 1.2)
                        } else {
                            ResultCardController.shared.finish(final)
                            HistoryStore.shared.append(HistoryRecord(
                                date: Date(), app: job.appName, bundleId: job.bundleId,
                                duration: job.duration, raw: raw, text: final,
                                language: HistoryStore.detectLanguage(final), status: "ok"
                            ), audio: job.wav)
                        }
                        return
                    }
                    // 后处理结果为空（未捕获到语音/无可整理内容）：不注入、不记历史、不动剪贴板，复用「未捕获到语音」反馈
                    if final.isEmpty {
                        self.lastInsertion = nil
                        self.hud.state.phase = .empty
                        self.hud.hide(after: 1.2)
                        return
                    }
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
                        duration: job.duration, raw: raw, text: final,
                        language: HistoryStore.detectLanguage(final), status: "ok"
                    ), audio: job.wav)
                    if pasted {
                        // 记录本次插入，供成功态「撤销」（焦点守卫用出字时刻的前台 App）
                        self.lastInsertion = LastInsertion(
                            charCount: insertedCount,
                            appPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                            replacedSelection: job.selection
                        )
                        // 出字落定后给焦点字段拍快照，待用户就地纠正后自学习。
                        // 延时让剪贴板粘贴/逐字键入真正写入字段，再读取其值。
                        let inserted = streamSession?.typedAny == true ? (streamSession?.typedText ?? final) : final
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.editLearner.snapshot(inserted: inserted)
                        }
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
                    // 已被 ESC 中断（含任务取消抛出）：半成品已在 cancelProcessing 回滚，这里不再处理
                    guard gen == self.jobGen else { return }
                    self.currentJob = nil
                    self.currentRollback = nil
                    // ask 模式失败：收起卡片，错误仍走 HUD 失败态（可重试）
                    if useCard { ResultCardController.shared.close() }
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
        // 转写为空/纯空白（误触、静音、识别失败）时直接返回，避免把空内容喂给 LLM 触发“请提供文本”式寒暄
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
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
