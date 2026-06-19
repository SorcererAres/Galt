import Foundation

/// 本地离线识别的运行时种类（决定由哪个 Provider 加载该模型）
enum LocalRuntime: String {
    case whisperCpp          // whisper.cpp，单 .bin 文件，Metal 加速
    case sherpaOnnx          // sherpa-onnx，多文件 onnx + tokens（SenseVoice / Paraformer）
}

/// 模型需要下载到本机的单个资源文件
struct ModelAsset {
    let fileName: String
    let urlString: String

    var url: URL { URL(string: urlString)! }

    var localURL: URL {
        HistoryStore.shared.directory.appendingPathComponent("models/\(fileName)")
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }
}

/// 可下载的本地模型目录（运行时无关）。
/// 新增模型 = 往 `all` 里加一行配置，无需改动 Provider 与设置界面。
struct LocalModel: Identifiable {
    let id: String
    let name: String
    let runtime: LocalRuntime
    let assets: [ModelAsset]      // 该模型需要的全部文件（whisper.cpp 为单文件）
    let sizeMB: Int
    let note: String             // 速度/质量提示，展示在副标题

    /// 全部资源就绪才算「已下载」
    var isDownloaded: Bool { !assets.isEmpty && assets.allSatisfy { $0.isDownloaded } }

    /// whisper.cpp 主模型文件的本机路径
    var primaryPath: String? { assets.first?.localURL.path }

    /// 删除已下载到本机的全部资源文件
    func delete() throws {
        for asset in assets where asset.isDownloaded {
            try FileManager.default.removeItem(at: asset.localURL)
        }
    }

    /// 便捷构造：单文件 whisper.cpp 模型（HuggingFace ggerganov 仓库）
    private static func whisper(_ id: String, _ name: String, file: String, sizeMB: Int, note: String) -> LocalModel {
        LocalModel(
            id: id,
            name: name,
            runtime: .whisperCpp,
            assets: [ModelAsset(
                fileName: file,
                urlString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)"
            )],
            sizeMB: sizeMB,
            note: note
        )
    }

    /// 便捷构造：sherpa-onnx 离线模型（model + tokens 两个文件，各放独立子目录避免重名）
    private static func sherpa(_ id: String, _ name: String, repo: String, sizeMB: Int, note: String) -> LocalModel {
        let base = "https://huggingface.co/csukuangfj/\(repo)/resolve/main"
        return LocalModel(
            id: id,
            name: name,
            runtime: .sherpaOnnx,
            assets: [
                ModelAsset(fileName: "\(id)/model.int8.onnx", urlString: "\(base)/model.int8.onnx"),
                ModelAsset(fileName: "\(id)/tokens.txt", urlString: "\(base)/tokens.txt"),
            ],
            sizeMB: sizeMB,
            note: note
        )
    }

    /// 全部本地模型（含各运行时）。sherpa-onnx 条目需链接二进制框架后启用（见 SherpaOnnxProvider）。
    static let all: [LocalModel] = {
        var models: [LocalModel] = [
            whisper("tiny-q5_1", "Whisper tiny", file: "ggml-tiny-q5_1.bin", sizeMB: 30,
                    note: "OpenAI Whisper 最小档（39M 参数，q5_1 量化）。速度最快、内存占用最低，适合短句速记；复杂长句准确率有限。"),
            whisper("base-q5_1", "Whisper base", file: "ggml-base-q5_1.bin", sizeMB: 56,
                    note: "OpenAI Whisper 基础档（74M 参数，q5_1 量化）。比 tiny 更稳、依旧轻量省内存，日常短句够用。"),
            whisper("small-q5_1", "Whisper small", file: "ggml-small-q5_1.bin", sizeMB: 181,
                    note: "OpenAI Whisper 小型档（244M 参数，q5_1 量化）。速度与准确率均衡，多语言通用，推荐入门。"),
            whisper("medium-q5_0", "Whisper medium", file: "ggml-medium-q5_0.bin", sizeMB: 514,
                    note: "OpenAI Whisper 中型档（769M 参数，q5_0 量化）。中文与长句明显更准，资源占用随之上升。"),
            whisper("large-v3-turbo-q5_0", "Whisper large-v3-turbo", file: "ggml-large-v3-turbo-q5_0.bin", sizeMB: 547,
                    note: "Whisper large-v3 的蒸馏加速版（809M 参数，q5_0 量化）。接近 large-v3 的精度、速度快数倍，质量与速度兼顾之选。"),
            whisper("large-v3-q5_0", "Whisper large-v3", file: "ggml-large-v3-q5_0.bin", sizeMB: 1031,
                    note: "OpenAI Whisper 旗舰档（1.55B 参数，q5_0 量化）。多语言最高精度，体积最大、推理最慢。"),
        ]
        #if GALT_SHERPA
        models += [
            sherpa("sense-voice-2024-07-17", "SenseVoice Small",
                   repo: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17", sizeMB: 228,
                   note: "阿里巴巴 FunAudioLLM 多语言模型，覆盖中英日韩粤。中文识别强、自带标点与逆文本归一化，非流式但推理极快。"),
            sherpa("paraformer-zh-2024-03-09", "Paraformer-zh",
                   repo: "sherpa-onnx-paraformer-zh-2024-03-09", sizeMB: 216,
                   note: "阿里达摩院 Paraformer 中文离线模型，中英混说友好。长句稳定、标点完整，适合会议与长段口述。"),
        ]
        #endif
        return models
    }()

    /// 指定运行时的模型子集（界面分组、Provider 校验用）
    static func models(for runtime: LocalRuntime) -> [LocalModel] {
        all.filter { $0.runtime == runtime }
    }

    static func byId(_ id: String) -> LocalModel {
        all.first { $0.id == id } ?? all.first { $0.id == "small-q5_1" } ?? all[0]
    }
}

/// 模型下载器（多文件顺序下载，合并进度，供设置面板展示）
final class ModelDownloader: NSObject, ObservableObject {
    static let shared = ModelDownloader()

    @Published var downloadingId: String?
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    private var observation: NSKeyValueObservation?

    func download(_ model: LocalModel) {
        guard downloadingId == nil else { return }
        downloadingId = model.id
        progress = 0
        errorMessage = nil

        // 仅下载尚未就绪的资源；多文件时按数量平摊进度
        let pending = model.assets.filter { !$0.isDownloaded }
        guard !pending.isEmpty else {
            downloadingId = nil
            return
        }
        downloadNext(pending, total: pending.count)
    }

    /// 顺序下载剩余资源：每完成一个，整体进度推进 1/total
    private func downloadNext(_ remaining: [ModelAsset], total: Int) {
        guard let asset = remaining.first else {
            DispatchQueue.main.async {
                self.downloadingId = nil
                self.observation = nil
                self.progress = 0
            }
            return
        }
        let completed = total - remaining.count
        let task = URLSession.shared.downloadTask(with: asset.url) { [weak self] temp, _, error in
            guard let self else { return }
            // 临时文件必须在回调内同步移走，回调返回后会被系统删除
            var failure = error?.localizedDescription
            if failure == nil, let temp {
                do {
                    let dir = asset.localURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: asset.localURL)
                    try FileManager.default.moveItem(at: temp, to: asset.localURL)
                } catch {
                    failure = error.localizedDescription
                }
            } else if failure == nil {
                failure = "下载失败，请重试"
            }
            if let failure {
                DispatchQueue.main.async {
                    self.errorMessage = failure
                    self.downloadingId = nil
                    self.observation = nil
                }
                return
            }
            self.downloadNext(Array(remaining.dropFirst()), total: total)
        }
        observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async {
                self?.progress = (Double(completed) + p.fractionCompleted) / Double(total)
            }
        }
        task.resume()
    }
}
