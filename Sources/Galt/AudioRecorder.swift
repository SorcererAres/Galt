import AVFoundation
import AudioToolbox

/// 麦克风采集：AVAudioEngine 抓取浮点样本，停止时重采样到 16kHz 单声道并编码为 WAV
final class AudioRecorder {
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
            DispatchQueue.main.async { self.onLevel?(rms) }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
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
}
