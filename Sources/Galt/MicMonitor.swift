import AudioToolbox
import AVFoundation
import Combine

/// 诊断面板专用的轻量麦克风电平监听：只读 RMS、不落样本，与听写录音互不干扰。
/// 面板出现时 start()、消失时 stop()。
final class MicMonitor: ObservableObject {
    /// 实时电平（RMS，0…~0.3 量级），主线程发布
    @Published var level: Float = 0
    /// 是否成功启动采集（启动失败=引擎拿不到输入，多半无麦克风/无权限）
    @Published private(set) var running = false

    private let engine = AVAudioEngine()

    func start() {
        guard !running else { return }
        let input = engine.inputNode
        applyPreferredDevice(to: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += channel[i] * channel[i] }
            let rms = count > 0 ? sqrt(sum / Float(count)) : 0
            DispatchQueue.main.async { self.level = rms }
        }
        do {
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        level = 0
    }

    /// 与 AudioRecorder 一致：设置中指定了麦克风时绑定到该设备（"auto" 走系统默认）
    private func applyPreferredDevice(to input: AVAudioInputNode) {
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
}
