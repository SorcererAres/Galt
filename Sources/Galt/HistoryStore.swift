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

    /// 进程内稳定的行标识（用于列表与删除匹配）
    var id: String { "\(date.timeIntervalSince1970)-\(text.hashValue)" }

    private enum CodingKeys: String, CodingKey {
        case date, app, bundleId, duration, raw, text
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

    func append(_ record: HistoryRecord) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        NotificationCenter.default.post(name: .galtHistoryChanged, object: nil)
    }

    /// 全部记录，按时间正序（文件顺序）
    private func chronological() -> [HistoryRecord] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content.split(separator: "\n").compactMap {
            try? decoder.decode(HistoryRecord.self, from: Data($0.utf8))
        }
    }

    /// 全部记录，最新在前（供控制台展示）
    func all() -> [HistoryRecord] {
        chronological().reversed()
    }

    /// 删除一条记录（整体重写 JSONL）
    func delete(id: String) {
        let remaining = chronological().filter { $0.id != id }
        writeAll(remaining)
        NotificationCenter.default.post(name: .galtHistoryChanged, object: nil)
    }

    /// 清理超过保存周期的记录（保存天数为 0 时永久保留，不清理）
    @discardableResult
    func pruneExpired() -> Bool {
        let days = SettingsStore.shared.historyRetentionDays
        guard days > 0 else { return false }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let records = chronological()
        let kept = records.filter { $0.date >= cutoff }
        guard kept.count != records.count else { return false }
        writeAll(kept)
        NotificationCenter.default.post(name: .galtHistoryChanged, object: nil)
        return true
    }

    /// 整体重写 JSONL
    private func writeAll(_ records: [HistoryRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = records.compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
        let body = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? body.write(to: fileURL, atomically: true, encoding: .utf8)
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
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return stats }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in content.split(separator: "\n") {
            guard let record = try? decoder.decode(HistoryRecord.self, from: Data(line.utf8)) else { continue }
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
