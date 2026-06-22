import AVFoundation
import AudioToolbox

/// 麦克风采集：AVAudioEngine 抓取浮点样本，停止时重采样到 16kHz 单声道并编码为 WAV
///
/// `@unchecked Sendable`：供 DictationController 后台线程调用 start()。共享的样本缓冲由 `lock`
/// 保护；start()（后台）与 stop()（主线程）在生命周期上不重叠——启动窗口内主线程不触碰 recorder，
/// 故无并发数据竞争。
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private var inputSampleRate: Double = 48000
    private(set) var isRecording = false
    /// 最近一次录音时长（秒），stop() 后有效
    private(set) var lastDuration: Double = 0

    /// 实时音量回调（RMS，主线程触发），供 HUD 波形使用
    var onLevel: ((Float) -> Void)?

    func start() throws {
        lock.lock(); samples.removeAll(); lock.unlock()

        let input = engine.inputNode
        applyPreferredInputDevice(to: input)
        let format = input.outputFormat(forBus: 0)
        inputSampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            self.lock.lock()
            self.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            self.lock.unlock()

            var sum: Float = 0
            for i in 0..<count { sum += channel[i] * channel[i] }
            let rms = (count > 0) ? sqrt(sum / Float(count)) : 0
            // 线性 RMS 对语音而言数值很小（约 0.01~0.1），直接喂可视化会被压在底部、显得「不灵敏」。
            // 改按人耳感知的分贝（对数）映射：以噪声底为 0、0dB 为 1，再乘灵敏度——正常说话即可接近打满。
            let level = Self.perceptualLevel(rms: rms)
            DispatchQueue.main.async { self.onLevel?(level) }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// 把线性 RMS 转成 0…1 的感知音量（对数/分贝映射 + 灵敏度）。
    /// db = 20·log10(rms)；以 noiseFloor..0 dB 归一，再乘灵敏度并夹到 [0,1]。
    static func perceptualLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let floor = Tuning.MicLevel.noiseFloorDB
        let db = 20 * log10(rms)
        let norm = (max(floor, db) - floor) / (0 - floor)      // floor→0, 0dB→1
        return max(0, min(1, norm * Tuning.MicLevel.sensitivity))
    }

    /// 停止录音并返回 16kHz 单声道 WAV；录音过短（<0.3s）返回 nil
    func stop() -> Data? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock()
        let raw = samples
        lock.unlock()

        lastDuration = Double(raw.count) / inputSampleRate
        let resampled = Self.resample(raw, from: inputSampleRate, to: 16000)
        guard resampled.count > 4800 else { return nil }
        return Self.wavData(from: resampled, sampleRate: 16000)
    }

    /// 设置中指定了麦克风时，把输入节点绑定到该设备（"auto" 走系统默认）
    private func applyPreferredInputDevice(to input: AVAudioInputNode) {
        let uid = SettingsStore.shared.micDeviceUID
        guard uid != "auto",
              var deviceID = AudioDevices.deviceID(forUID: uid),
              let audioUnit = input.audioUnit else { return }
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    /// 线性插值重采样（对语音足够）
    static func resample(_ input: [Float], from: Double, to: Double) -> [Float] {
        guard from != to, !input.isEmpty else { return input }
        let ratio = from / to
        let outCount = Int(Double(input.count) / ratio)
        var out = [Float]()
        out.reserveCapacity(outCount)
        for i in 0..<outCount {
            let pos = Double(i) * ratio
            let idx = Int(pos)
            guard idx < input.count else { break }
            let frac = Float(pos - Double(idx))
            let a = input[idx]
            let b = (idx + 1 < input.count) ? input[idx + 1] : a
            out.append(a + (b - a) * frac)
        }
        return out
    }

    /// Float 样本 → 16-bit PCM WAV
    static func wavData(from samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1, min(1, s))
            let v = Int16(clamped * 32767)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func str(_ s: String) { data.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    /// Float 样本 → AAC(m4a) 压缩数据；编码失败返回 nil。
    /// 仅用于「确定接受 m4a」的 OpenAI 兼容厂商，显著降低上传体积/时延。
    static func aacData(from samples: [Float], sampleRate: Int) -> Data? {
        guard !samples.isEmpty else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24000,
        ]
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("galt-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            // 写入块单独作用域：AVAudioFile 在析构时 flush，需在读回前释放
            try autoreleasepool {
                let file = try AVAudioFile(
                    forWriting: tmp, settings: settings,
                    commonFormat: .pcmFormatFloat32, interleaved: false
                )
                let frames = AVAudioFrameCount(samples.count)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
                      let channel = buffer.floatChannelData?[0] else {
                    throw NSError(domain: "Galt.AAC", code: -1)
                }
                buffer.frameLength = frames
                samples.withUnsafeBufferPointer { src in
                    channel.update(from: src.baseAddress!, count: samples.count)
                }
                try file.write(from: buffer)
            }
        } catch {
            NSLog("Galt: AAC 编码失败，回退 WAV：\(error.localizedDescription)")
            return nil
        }
        return try? Data(contentsOf: tmp)
    }

    /// 把本应用产出的 16bit/单声道 WAV 转成 AAC(m4a)；解析失败/编码失败返回 nil。
    /// 复用我们自己 wavData 的固定头部布局（采样率在 24…27，PCM 从 44 起）。
    static func aacData(fromWAV wav: Data) -> Data? {
        guard wav.count > 44 else { return nil }
        // 采样率（小端 u32 @24）
        let sampleRate = wav.withUnsafeBytes { raw -> Int in
            let b = raw.bindMemory(to: UInt8.self)
            return Int(b[24]) | Int(b[25]) << 8 | Int(b[26]) << 16 | Int(b[27]) << 24
        }
        guard sampleRate > 0 else { return nil }
        let pcm = wav.subdata(in: 44..<wav.count)
        let count = pcm.count / 2
        guard count > 0 else { return nil }
        var samples = [Float](repeating: 0, count: count)
        pcm.withUnsafeBytes { raw in
            let i16 = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                samples[i] = Float(Int16(littleEndian: i16[i])) / 32767
            }
        }
        return aacData(from: samples, sampleRate: sampleRate)
    }
}
