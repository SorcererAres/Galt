import ApplicationServices
import Foundation

/// 纠错自学习：出字落定后给焦点字段拍一张快照，过一会儿回看用户是否就地改了某个词，
/// 把这种「就地纠正」沉淀成自动词典（喂回 STT 提示与 LLM 润色，提升专有名词命中率）。
///
/// 判定是启发式的（前后缀公共子串求差 + 变更需落在我们插入的文本范围内），刻意保守：
/// 只学短词、只在改动局部时才学，宁可漏学也不误学。后端去重/限长/开关见
/// `SettingsStore.learnTerm` / `learnedTerms` / `correctionLearningEnabled`。
@MainActor
final class EditLearner {
    /// 学到新词时回调（携带被纠正后的新词）；DictationController 据此在空闲时弹一条轻量提示
    var onLearned: ((String) -> Void)?

    /// 一次待回看的插入快照
    private struct Pending {
        /// 出字时的焦点字段（直接回读它，避免焦点已切走时读错字段）
        let element: AXUIElement
        /// 出字落定那一刻字段的全文（基线，必含 inserted）
        let baseline: String
        /// 本次注入的文本
        let inserted: String
    }

    private var pending: Pending?
    /// 定时回看：空闲时检测就地纠正并播报；无待回看快照时近乎零开销
    private var timer: Timer?

    /// 单次纠正可学习的最大片段长度（中文短词/短语；过长视作整段重写，不学）
    private static let maxSegment = 12
    /// 定时回看间隔
    private static let recheckInterval: TimeInterval = 3

    init() {
        // 加到 RunLoop.main，回调必在主线程，assumeIsolated 断言 MainActor 安全
        let timer = Timer(timeInterval: Self.recheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(announce: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 对外

    /// 出字落定后调用：拍下焦点字段全文作为基线（要求字段确含 inserted，否则不立快照）
    func snapshot(inserted: String) {
        guard SettingsStore.shared.correctionLearningEnabled else { pending = nil; return }
        let trimmed = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { pending = nil; return }
        guard let element = Self.focusedElement(),
              let value = Self.value(of: element),
              value.contains(inserted) else { pending = nil; return }
        pending = Pending(element: element, baseline: value, inserted: inserted)
    }

    /// 按需回看（如下一次录音开始前）：静默学习，不播报
    func recheck() {
        check(announce: false)
    }

    /// 作废当前快照（如用户撤销了整段插入，避免把「删掉」误判成纠正）
    func cancel() {
        pending = nil
    }

    // MARK: - 回看与判定

    /// 回看快照字段当前全文：若较基线发生了局部纠正，学习被纠正后的新词。
    /// 字段未变则保留快照继续等待；命中（无论是否真学到）即消费快照。
    private func check(announce: Bool) {
        guard let p = pending else { return }
        guard SettingsStore.shared.correctionLearningEnabled else { pending = nil; return }
        guard let current = Self.value(of: p.element) else { return }
        guard current != p.baseline else { return }  // 未改动，继续等
        pending = nil
        guard let c = Self.learnedCorrection(baseline: p.baseline, current: current, inserted: p.inserted) else { return }
        // 学「对词」（维持偏置 + toast）
        let learned = SettingsStore.shared.learnTerm(c.right)
        // 若是「错词 → 对词」的就地纠正，沉淀方向对，供确定性替换消灭复现
        if !c.wrong.isEmpty {
            SettingsStore.shared.addCorrectionPair(wrong: c.wrong, right: c.right)
        }
        if learned, announce {
            onLearned?(c.right)
        }
    }

    /// 比较基线与当前文本，求出被替换的「旧片段 → 新片段」；不构成可学纠正则返回 nil。
    /// 仅当变更落在我们插入文本所在区间、且新旧片段都短小、新片段是个不含空白的「词」时才学。
    /// `wrong` 为被替换掉的旧片段（纯插入时为空，调用方据此决定是否构成方向纠错对）。
    static func learnedCorrection(baseline: String, current: String, inserted: String) -> (wrong: String, right: String)? {
        let a = Array(baseline), b = Array(current)
        // 公共前缀
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        // 公共后缀（不与前缀重叠）
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }

        let oldSeg = String(a[p..<(a.count - s)])
        let newSeg = String(b[p..<(b.count - s)])
        guard !newSeg.isEmpty else { return nil }                 // 纯删除，不学
        guard newSeg.count <= maxSegment, oldSeg.count <= maxSegment else { return nil }
        guard !newSeg.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        // 变更区间 [p, a.count - s) 需与 inserted 在 baseline 中的位置交叠
        guard let start = indexOfSubarray(a, Array(inserted)) else { return nil }
        let end = start + inserted.count
        guard p <= end, (a.count - s) >= start else { return nil }
        // 旧片段含空白（多半是跨词大改）则不作为方向对，只把新词当作可学词
        let wrong = oldSeg.contains(where: { $0.isWhitespace || $0.isNewline }) ? "" : oldSeg
        return (wrong: wrong, right: newSeg)
    }

    /// 朴素子串定位（按字符）；找不到返回 nil
    private static func indexOfSubarray(_ haystack: [Character], _ needle: [Character]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) {
            if Array(haystack[i..<(i + needle.count)]) == needle { return i }
        }
        return nil
    }

    // MARK: - 辅助功能读取

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let focused = ref,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private static func value(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success,
              let text = ref as? String else { return nil }
        return text
    }
}
