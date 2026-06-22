import AppKit
import ApplicationServices

/// 纠错自学习：出字后给焦点字段拍一张快照，待用户就地改动后回看，
/// 把「干净的单词级纠正」（如 galt→Galt、Github→GitHub）沉淀进自动词典。
///
/// 设计取舍（高精度、低误报，对齐 Typeless 的 track-edit-text 思路但更克制）：
/// - 只对「插入文本占据了整个字段」的场景学习（聊天输入框/搜索框等），长文档不学，避免噪声；
/// - 只学「含字母的词」（人名/品牌/代码标识），纯中文同音字改动太易误判，不学；
/// - 要求一次改动恰好是「一个旧词→一个相像的新词」的清爽替换，否则放弃。
final class EditLearner {
    /// 一次待回看的插入快照
    private struct Pending {
        let element: AXUIElement      // 出字时的焦点元素（持有引用，便于稍后重读其值）
        let valueAtInsert: String     // 出字后字段全文
        let inserted: String          // 本次插入的文本
        let appPID: pid_t?
    }

    private var pending: Pending?
    private var timer: Timer?

    /// 定时回看学到新词时回调（主线程）；点按再次听写触发的回看不走此回调（即将进入录音态）
    var onLearned: ((String) -> Void)?

    /// 丢弃待回看的快照（如用户点了「撤销」，那次插入不应再被当作纠正来源）
    func cancel() {
        timer?.invalidate()
        timer = nil
        pending = nil
    }

    /// 出字成功后调用：记录当前焦点字段快照，并起一个延时回看兜底
    func snapshot(inserted: String) {
        guard SettingsStore.shared.correctionLearningEnabled,
              inserted.count >= 2,
              let element = Self.focusedElement(),
              let value = Self.value(of: element) else {
            pending = nil
            return
        }
        // 插入文本须占字段多数（≥50%），即「这个字段基本就是我们写进去的」，长文档不纳入学习
        guard inserted.count * 2 >= value.count else {
            pending = nil
            return
        }
        pending = Pending(
            element: element,
            valueAtInsert: value,
            inserted: inserted,
            appPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self, let term = self.recheck() else { return }
            self.onLearned?(term)
        }
    }

    /// 回看上一次插入：若用户做了清爽的单词级纠正则学习并返回该词，否则返回 nil。
    /// 调用即消费快照（一次性），同时取消延时兜底。
    @discardableResult
    func recheck() -> String? {
        timer?.invalidate()
        timer = nil
        guard let job = pending else { return nil }
        pending = nil

        guard let current = Self.value(of: job.element), current != job.valueAtInsert else { return nil }
        // 仍是同一个字段被「小改」：要求首尾公共部分占多数，排除整段被替换成无关内容
        let overlap = Self.commonPrefixLength(job.valueAtInsert, current)
            + Self.commonSuffixLength(job.valueAtInsert, current)
        guard overlap * 2 >= min(job.valueAtInsert.count, current.count) else { return nil }

        guard let term = Self.learnableCorrection(before: job.valueAtInsert, after: current) else { return nil }
        return SettingsStore.shared.learnTerm(term) ? term : nil
    }

    // MARK: - 词级纠正提取

    /// 比较改动前后的「含字母候选词」集合：恰好移除 ≤2 个、新增 1 个、且新增词与某个被移除词相像时，
    /// 认为是一次纠正，返回新增（正确）写法。
    static func learnableCorrection(before: String, after: String) -> String? {
        let beforeTerms = candidateTerms(before)
        let afterTerms = candidateTerms(after)
        let removed = subtractingMultiset(beforeTerms, afterTerms)
        let added = subtractingMultiset(afterTerms, beforeTerms)
        guard added.count == 1, removed.count <= 2 else { return nil }
        let new = added[0]
        guard isLearnable(new) else { return nil }
        // 要求存在一个「相像」的被移除词（仅大小写不同 / 前缀包含 / 编辑距离近）才算纠正；
        // 纯新增（无对应旧词）不学，避免误收用户随后补写的普通内容。
        guard removed.contains(where: { looksLikeCorrection($0, new) }) else { return nil }
        return new
    }

    /// 候选词：以拉丁字母开头的 ASCII 串，可含字母/数字/`_ + . -`，长度≥2。
    /// 刻意只认 ASCII（品牌、代码标识、英文名/混排名词），把 CJK 当分隔符——
    /// 纯中文同音字改动（如「在做→再做」）不产生候选词，从而不会被误学。
    static func candidateTerms(_ text: String) -> [String] {
        var terms: [String] = []
        var current = ""
        func isWordChar(_ ch: Character) -> Bool {
            guard let a = ch.asciiValue else { return false }
            let isAlnum = (a >= 65 && a <= 90) || (a >= 97 && a <= 122) || (a >= 48 && a <= 57)
            return isAlnum || ch == "_" || ch == "+" || ch == "." || ch == "-"
        }
        func flush() {
            // 首字符须为拉丁字母（排除以数字/符号开头的串）
            if current.count >= 2, let f = current.first, f.isLetter { terms.append(current) }
            current = ""
        }
        for ch in text {
            if isWordChar(ch) { current.append(ch) } else { flush() }
        }
        flush()
        return terms
    }

    /// 可学习过滤：含字母、长度 2…40、不是纯数字串、不是常见英文停用词
    static func isLearnable(_ term: String) -> Bool {
        guard (2...40).contains(term.count), term.contains(where: { $0.isLetter }) else { return false }
        let lower = term.lowercased()
        let stop: Set<String> = ["the", "and", "you", "for", "are", "this", "that", "with", "have", "was", "but"]
        return !stop.contains(lower)
    }

    /// 旧词→新词是否像一次纠正：仅大小写不同 / 一方是另一方前缀 / 编辑距离足够小
    static func looksLikeCorrection(_ old: String, _ new: String) -> Bool {
        let a = old.lowercased(), b = new.lowercased()
        if a == b { return true } // 仅大小写订正（galt→Galt）
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        let tolerance = max(1, b.count / 3)
        return levenshtein(a, b) <= tolerance
    }

    // MARK: - 工具

    /// 多重集差：a 中逐元素扣减 b 出现过的，返回剩余（保持顺序）
    private static func subtractingMultiset(_ a: [String], _ b: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for x in b { counts[x, default: 0] += 1 }
        var out: [String] = []
        for x in a {
            if let c = counts[x], c > 0 { counts[x] = c - 1 } else { out.append(x) }
        }
        return out
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        let sa = Array(a), sb = Array(b)
        var i = 0
        while i < sa.count, i < sb.count, sa[i] == sb[i] { i += 1 }
        return i
    }

    private static func commonSuffixLength(_ a: String, _ b: String) -> Int {
        let sa = Array(a), sb = Array(b)
        var i = 0
        while i < sa.count, i < sb.count, sa[sa.count - 1 - i] == sb[sb.count - 1 - i] { i += 1 }
        return i
    }

    // MARK: - 辅助功能读取

    /// 当前系统焦点元素（无权限/读不到返回 nil）
    private static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    /// 读取元素的 kAXValue 文本；非字符串、为空或过长（>2000，多半是大文档）时返回 nil
    private static func value(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String, !text.isEmpty, text.count <= 2000 else { return nil }
        return text
    }
}
