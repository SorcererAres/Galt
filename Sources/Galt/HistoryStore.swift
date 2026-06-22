import Foundation

struct HistoryRecord: Codable, Identifiable {
    let date: Date
    let app: String?
    /// 前台应用 bundle 标识；用于占比统计按应用聚类（名称可能有出入，bundleId 稳定）。
    /// 可选：老记录无此字段，解码为 nil。
    var bundleId: String? = nil
    let duration: Double
    let raw: String
    let text: String
    /// 识别出的主要语种（"zh"/"en"/"ja"/"mixed"）；老记录或检测失败为 nil。
    var language: String? = nil
    /// 本次结果状态（当前仅成功记录入库，恒为 "ok"；预留失败/空态以备后续）。
    var status: String? = nil
    /// 关联音频文件名（位于 recordings 子目录）；未开启「保存音频」或写入失败为 nil。
    var audioFile: String? = nil

    /// 进程内稳定的行标识（用于列表与删除匹配）
    var id: String { "\(date.timeIntervalSince1970)-\(text.hashValue)" }

    private enum CodingKeys: String, CodingKey {
        case date, app, bundleId, duration, raw, text, language, status, audioFile
    }
}

extension Notification.Name {
    /// 历史记录发生变化（新增/删除），控制台页面据此刷新
    static let galtHistoryChanged = Notification.Name("galtHistoryChanged")
}

/// 听写历史与统计（JSONL 格式，仅存本地，对齐 Typeless 的零服务端留存）
final class HistoryStore {
    static let shared = HistoryStore()

    let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Galt", isDirectory: true)
    }()

    var fileURL: URL { directory.appendingPathComponent("history.jsonl") }

    /// 解析后的记录缓存（时间正序）。全程仅在主线程读写，故无需加锁。
    /// 切页时直接命中缓存，避免每次都同步读盘 + JSON 解析整份历史造成卡顿。
    private var cache: [HistoryRecord]?

    /// 音频留存目录（与历史同级的 recordings 子目录）
    var recordingsDirectory: URL { directory.appendingPathComponent("recordings", isDirectory: true) }

    /// 启动时在后台预热缓存：解析放到子线程，解析完回主线程落入缓存，
    /// 让首次进入概览/历史页时也即时（不阻塞主线程）。
    func preload() {
        guard cache == nil else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let parsed = self.parseFile()
            DispatchQueue.main.async {
                if self.cache == nil { self.cache = parsed }
                // 启动时清一次超期记录（缓存已暖，开销小）；之后切页不再每次清理
                self.pruneExpired()
            }
        }
    }

    /// 从磁盘解析整份历史（纯函数，不触缓存，可在任意线程调用）
    private func parseFile() -> [HistoryRecord] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content.split(separator: "\n").compactMap {
            try? decoder.decode(HistoryRecord.self, from: Data($0.utf8))
        }
    }

    /// 取某条记录关联的音频文件 URL；无音频返回 nil
    func audioURL(for record: HistoryRecord) -> URL? {
        guard let name = record.audioFile, !name.isEmpty else { return nil }
        return recordingsDirectory.appendingPathComponent(name)
    }

    /// 追加一条记录；传入 audio 且开启「保存音频」时把音频落盘到 recordings/，
    /// 文件名写回记录的 audioFile 字段，供回放/重转写/调试。
    func append(_ record: HistoryRecord, audio: Data? = nil) {
        var record = record
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let audio, SettingsStore.shared.storeAudioInHistory {
            try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
            let name = record.audioFile ?? "\(UUID().uuidString).wav"
            if (try? audio.write(to: recordingsDirectory.appendingPathComponent(name))) != nil {
                record.audioFile = name
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line)
        } else {
            try? line.write(to: fileURL)
        }
        // 增量更新缓存：已建则追加，未建则留空待下次按需解析（文件已含此条）
        if cache != nil { cache?.append(record) }
        NotificationCenter.default.post(name: .galtHistoryChanged, object: nil)
    }

    /// 全部记录，按时间正序（命中缓存则免读盘）
    private func chronological() -> [HistoryRecord] {
        if let cache { return cache }
        let parsed = parseFile()
        cache = parsed
        return parsed
    }

    /// 全部记录，最新在前（供控制台展示）
    func all() -> [HistoryRecord] {
        chronological().reversed()
    }

    /// 删除一条记录（整体重写 JSONL），并清理其关联音频
    func delete(id: String) {
        let all = chronological()
        let remaining = all.filter { $0.id != id }
        for removed in all where removed.id == id {
            deleteAudio(of: removed)
        }
        writeAll(remaining)
        NotificationCenter.default.post(name: .galtHistoryChanged, object: nil)
    }

    /// 清理超过保存周期的记录（保存天数为 0 时永久保留，不清理）；
    /// 连同被删记录的音频一并删除，并顺手清理无主音频文件。
    @discardableResult
    func pruneExpired() -> Bool {
        let days = SettingsStore.shared.historyRetentionDays
        guard days > 0 else { return false }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let records = chronological()
        let kept = records.filter { $0.date >= cutoff }
        guard kept.count != records.count else { return false }
        for removed in records where removed.date < cutoff {
            deleteAudio(of: removed)
        }
        writeAll(kept)
        cleanupOrphanAudio(keeping: kept)
        NotificationCenter.default.post(name: .galtHistoryChanged, object: nil)
        return true
    }

    /// 删除某条记录的音频文件（若有）
    private func deleteAudio(of record: HistoryRecord) {
        guard let url = audioURL(for: record) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 删除 recordings 目录下不再被任何保留记录引用的孤儿音频
    private func cleanupOrphanAudio(keeping records: [HistoryRecord]) {
        let referenced = Set(records.compactMap { $0.audioFile })
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for url in files where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 按字符构成粗判主要语种：CJK 占比高→zh，含大量假名→ja，几乎全拉丁→en，混排→mixed。
    /// 仅作历史元数据展示/筛选用，非精确语言识别。
    static func detectLanguage(_ text: String) -> String? {
        var cjk = 0, kana = 0, latin = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x30FF).contains(v) { kana += 1; cjk += 1 }
            else if (0x4E00...0x9FFF).contains(v) { cjk += 1 }
            else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) { latin += 1 }
        }
        let total = cjk + latin
        guard total > 0 else { return nil }
        if kana * 3 >= cjk, kana > 0 { return "ja" }
        if cjk > 0, latin > 0, cjk * 4 < latin || latin * 4 < cjk { return "mixed" }
        return cjk >= latin ? "zh" : "en"
    }

    /// 整体重写 JSONL，并同步刷新缓存
    private func writeAll(_ records: [HistoryRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = records.compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
        let body = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? body.write(to: fileURL, atomically: true, encoding: .utf8)
        cache = records
    }

    struct Stats {
        var count = 0
        var words = 0
        var seconds: Double = 0
        var wpm: Int { seconds > 1 ? Int(Double(words) / (seconds / 60)) : 0 }
        /// 相比 45 WPM 打字速度节省的分钟数
        var savedMinutes: Int { max(0, Int(Double(words) / 45.0 - seconds / 60)) }
    }

    func stats() -> Stats {
        var stats = Stats()
        for record in chronological() {
            stats.count += 1
            stats.words += Self.wordCount(record.text)
            stats.seconds += record.duration
        }
        return stats
    }

    /// 中英混排字数：CJK 按字计，拉丁按词计
    static func wordCount(_ text: String) -> Int {
        var cjk = 0, latinWords = 0, inWord = false
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value) {
                cjk += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { latinWords += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return cjk + latinWords
    }
}
