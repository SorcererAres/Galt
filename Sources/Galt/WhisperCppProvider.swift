import Foundation
import whisper

/// 本地离线转写：whisper.cpp（Metal GPU 加速，自动检测语言）
/// 模型上下文常驻内存，切换模型时重新加载
final class WhisperCppProvider: STTProvider {
    let name = "本地 Whisper"
    private var ctx: OpaquePointer?
    private var loadedModelPath: String?

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    func transcribe(wav: Data) async throws -> String {
        let model = LocalModel.byId(SettingsStore.shared.whisperModelId)
        guard model.isDownloaded, let path = model.primaryPath else { throw STTError.modelMissing }

        if ctx == nil || loadedModelPath != path {
            if let old = ctx { whisper_free(old) }
            var cparams = whisper_context_default_params()
            cparams.use_gpu = true
            ctx = whisper_init_from_file_with_params(path, cparams)
            loadedModelPath = path
        }
        guard let ctx else { throw STTError.localUnavailable }

        let samples = Self.floatSamples(fromWav: wav)
        guard !samples.isEmpty else { throw STTError.empty }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))

        let status: Int32 = "auto".withCString { lang in
            params.language = lang
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
            }
        }
        guard status == 0 else { throw STTError.localUnavailable }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let segment = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segment)
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw STTError.empty }
        return trimmed
    }

    /// 16-bit PCM WAV → Float 样本（跳过 44 字节头）
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
