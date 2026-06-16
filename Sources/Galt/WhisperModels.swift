import Foundation

/// 可下载的 whisper.cpp 模型目录
struct WhisperModel: Identifiable {
    let id: String
    let name: String
    let fileName: String
    let sizeMB: Int

    var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var localURL: URL {
        HistoryStore.shared.directory.appendingPathComponent("models/\(fileName)")
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }

    /// 删除已下载到本机的模型文件
    func delete() throws {
        try FileManager.default.removeItem(at: localURL)
    }

    static let all: [WhisperModel] = [
        .init(id: "small-q5_1", name: "小型（多语言，约 190MB）", fileName: "ggml-small-q5_1.bin", sizeMB: 190),
        .init(id: "large-v3-turbo-q5_0", name: "高精度 large-v3-turbo（约 550MB）", fileName: "ggml-large-v3-turbo-q5_0.bin", sizeMB: 547),
    ]

    static func byId(_ id: String) -> WhisperModel {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 模型下载器（带进度，供设置面板展示）
final class ModelDownloader: NSObject, ObservableObject {
    static let shared = ModelDownloader()

    @Published var downloadingId: String?
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    private var observation: NSKeyValueObservation?

    func download(_ model: WhisperModel) {
        guard downloadingId == nil else { return }
        downloadingId = model.id
        progress = 0
        errorMessage = nil

        let task = URLSession.shared.downloadTask(with: model.url) { [weak self] temp, _, error in
            // 临时文件必须在回调内同步移走，回调返回后会被系统删除
            var failure = error?.localizedDescription
            if failure == nil, let temp {
                do {
                    let dir = model.localURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: model.localURL)
                    try FileManager.default.moveItem(at: temp, to: model.localURL)
                } catch {
                    failure = error.localizedDescription
                }
            } else if failure == nil {
                failure = "下载失败，请重试"
            }
            DispatchQueue.main.async {
                self?.errorMessage = failure
                self?.downloadingId = nil
                self?.observation = nil
            }
        }
        observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async { self?.progress = p.fractionCompleted }
        }
        task.resume()
    }
}
