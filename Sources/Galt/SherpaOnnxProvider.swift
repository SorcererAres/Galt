import Foundation

// 本地离线转写：sherpa-onnx 离线识别器（SenseVoice / Paraformer 等）
//
// 真实实现以编译标志 `GALT_SHERPA` 门控，默认关闭 → 编译为占位桩，不影响现有构建。
// 启用步骤（见文件末尾「接入说明」）：
//   1. 把 sherpa-onnx.xcframework 与 onnxruntime.xcframework 放入 Vendor/，在 Package.swift 注册 binaryTarget；
//   2. 把官方 swift-api-examples 里的 SherpaOnnx.swift 包装层复制进 Sources/Galt/；
//   3. 给 Galt target 加 swiftSettings: [.define("GALT_SHERPA")]。

#if GALT_SHERPA
import CSherpaOnnx  // C-API 结构体类型（SherpaOnnxOfflineModelConfig 等）

/// sherpa-onnx 离线（非流式）识别。模型常驻内存，切换模型时重建。
/// 契合 STTProvider 的批量 transcribe(wav:) 接口（SenseVoice/Paraformer 均为离线模型）。
final class SherpaOnnxProvider: STTProvider {
    let name = "本地 sherpa-onnx"

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var loadedModelId: String?

    func transcribe(wav: Data) async throws -> String {
        let model = LocalModel.byId(SettingsStore.shared.whisperModelId)
        guard model.runtime == .sherpaOnnx else { throw STTError.localUnavailable }
        guard model.isDownloaded,
              let modelPath = model.assets.first?.localURL.path,
              let tokensPath = model.assets.dropFirst().first?.localURL.path
        else { throw STTError.modelMissing }

        if recognizer == nil || loadedModelId != model.id {
            recognizer = Self.makeRecognizer(modelId: model.id, modelPath: modelPath, tokensPath: tokensPath)
            loadedModelId = model.id
        }
        guard let recognizer else { throw STTError.localUnavailable }

        let samples = Self.floatSamples(fromWav: wav)
        guard !samples.isEmpty else { throw STTError.empty }

        // sherpa-onnx 包装层：解码一段 16kHz 单声道 float 波形
        let result = recognizer.decode(samples: samples, sampleRate: 16000)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw STTError.empty }
        return text
    }

    /// 按模型种类组装对应的 sherpa-onnx 配置（SenseVoice / Paraformer 配置项不同）
    private static func makeRecognizer(modelId: String, modelPath: String, tokensPath: String) -> SherpaOnnxOfflineRecognizer {
        let threads = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        var modelConfig: SherpaOnnxOfflineModelConfig

        if modelId.hasPrefix("sense-voice") {
            let sv = sherpaOnnxOfflineSenseVoiceModelConfig(
                model: modelPath,
                language: "auto",                 // 自动判定中英日韩粤
                useInverseTextNormalization: true // 数字/日期等逆文本归一化
            )
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokensPath, numThreads: threads, senseVoice: sv
            )
        } else {
            // Paraformer 及其它离线模型（实参顺序须与包装层声明一致：paraformer 在 numThreads 之前）
            let pf = sherpaOnnxOfflineParaformerModelConfig(model: modelPath)
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokensPath, paraformer: pf, numThreads: threads
            )
        }

        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig, modelConfig: modelConfig
        )
        return SherpaOnnxOfflineRecognizer(config: &config)
    }

    /// 16-bit PCM WAV → Float 样本（跳过 44 字节头）；与 WhisperCppProvider 同源同格式
    private static func floatSamples(fromWav wav: Data) -> [Float] {
        guard wav.count > 44 else { return [] }
        return wav.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [Float] in
            let body = UnsafeRawBufferPointer(rebasing: raw[44...])
            let count = body.count / 2
            var out = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let lo = UInt16(body[i * 2])
                let hi = UInt16(body[i * 2 + 1])
                out[i] = Float(Int16(bitPattern: lo | (hi << 8))) / 32768
            }
            return out
        }
    }
}

#else

/// 占位实现：未链接 sherpa-onnx 二进制时返回明确错误。
/// 由于 `LocalModel.all` 的 sherpa 条目同样受 `GALT_SHERPA` 门控，正常路径不会走到这里。
final class SherpaOnnxProvider: STTProvider {
    let name = "本地 sherpa-onnx（未启用）"
    func transcribe(wav: Data) async throws -> String {
        throw STTError.localUnavailable
    }
}

#endif

// MARK: - 接入说明（启用 GALT_SHERPA 时）
//
// 二进制框架（k2-fsa/sherpa-onnx 发布页，选 macOS arm64 的 xcframework）：
//   Vendor/sherpa-onnx.xcframework
//   Vendor/onnxruntime.xcframework
//
// Package.swift：
//   .executableTarget(
//       name: "Galt",
//       dependencies: ["whisper", "sherpa-onnx", "onnxruntime"],
//       path: "Sources/Galt",
//       swiftSettings: [.define("GALT_SHERPA")]      // 打开真实实现
//   ),
//   .binaryTarget(name: "sherpa-onnx", path: "Vendor/sherpa-onnx.xcframework"),
//   .binaryTarget(name: "onnxruntime", path: "Vendor/onnxruntime.xcframework"),
//
// 包装层：复制官方 swift-api-examples/SherpaOnnx.swift 到 Sources/Galt/，
// 它把 C-API 封装为上面用到的 SherpaOnnxOfflineRecognizer / sherpaOnnx*Config 等符号。
// 不同版本包装层签名可能微调，若编译报错按其当前签名对齐 makeRecognizer 即可。
