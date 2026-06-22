import Foundation

/// 阿里云百炼（DashScope）「实时语音识别」(Paraformer realtime) WebSocket 适配器。
///
/// 协议（api-ws/v1/inference，文本帧为 JSON 指令、二进制帧为 PCM 音频）：
/// ① 发 `run-task`（指定 model / 采样率）→ ② 等 `task-started`
/// → ③ 逐包发送 PCM 音频 → ④ 发 `finish-task`
/// → ⑤ 循环接收 `result-generated` 累积句子，直到 `task-finished`。
///
/// 录音固定 16k；若所选模型要求 8k（paraformer-realtime-8k-v2），发送前本地重采样。
/// 注意：此实现按公开协议编写，需用真实账号联调后按报错微调。
enum DashScopeStreamingASR {
    private static let endpoint = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"

    static func transcribe(wav: Data, key: String, model: String,
                           sampleRate: Int, timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: endpoint) else { throw STTError.http(-1, "百炼流式接口地址无效") }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("bearer \(key)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        // task_id 为 32 位十六进制（去掉 UUID 的连字符），贯穿 run-task / finish-task
        let taskId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        // ① run-task：声明模型与音频格式
        let runTask: [String: Any] = [
            "header": ["action": "run-task", "task_id": taskId, "streaming": "duplex"],
            "payload": [
                "task_group": "audio", "task": "asr", "function": "recognition",
                "model": model,
                "parameters": ["format": "pcm", "sample_rate": sampleRate],
                "input": [:],
            ],
        ]
        try await task.send(.string(jsonString(runTask)))

        // ② 等待任务就绪
        try await waitForEvent("task-started", on: task)

        // ③ 逐包发送音频（裸 PCM，按模型采样率重采样）
        let pcm = pcmPayload(fromWAV: wav, targetRate: sampleRate)
        let chunkSize = max(sampleRate / 10, 1) * 2 // 100ms @16bit 单声道
        var offset = 0
        while offset < pcm.count {
            let end = min(offset + chunkSize, pcm.count)
            try await task.send(.data(pcm.subdata(in: offset..<end)))
            offset = end
        }

        // ④ finish-task：通知服务端音频发送完毕
        let finish: [String: Any] = [
            "header": ["action": "finish-task", "task_id": taskId, "streaming": "duplex"],
            "payload": ["input": [:]],
        ]
        try await task.send(.string(jsonString(finish)))

        // ⑤ 累积结果直到 task-finished
        //   Paraformer 实时按「句」推送：同一句的中间结果是该句的累计文本（覆盖），
        //   sentence_end=true 时该句定稿。故定稿句累加、未定稿句暂存，结束时拼接。
        var finalized = ""
        var current = ""
        while true {
            let event = try await receiveEvent(on: task)
            switch event.name {
            case "result-generated":
                if let text = event.sentence {
                    if event.sentenceEnd { finalized += text; current = "" }
                    else { current = text }
                }
            case "task-finished":
                return finalized + current
            case "task-failed":
                throw STTError.http(-1, "百炼流式：\(event.errorMessage ?? "识别失败")")
            default:
                continue
            }
        }
    }

    // MARK: 事件接收

    private struct Event {
        var name: String
        var sentence: String?
        var sentenceEnd: Bool
        var errorMessage: String?
    }

    /// 循环接收直到收到指定事件；中途遇 task-failed 抛错。
    private static func waitForEvent(_ name: String, on task: URLSessionWebSocketTask) async throws {
        while true {
            let event = try await receiveEvent(on: task)
            if event.name == name { return }
            if event.name == "task-failed" {
                throw STTError.http(-1, "百炼流式：\(event.errorMessage ?? "任务启动失败")")
            }
        }
    }

    /// 接收一帧并解析为事件；非 JSON 帧自动跳过。
    private static func receiveEvent(on task: URLSessionWebSocketTask) async throws -> Event {
        while true {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .string(let s): data = Data(s.utf8)
            case .data(let d): data = d
            @unknown default: continue
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let header = obj["header"] as? [String: Any]
            let name = header?["event"] as? String ?? ""
            let errorMessage = header?["error_message"] as? String
            var sentence: String?
            var sentenceEnd = false
            if let payload = obj["payload"] as? [String: Any],
               let output = payload["output"] as? [String: Any],
               let s = output["sentence"] as? [String: Any] {
                sentence = s["text"] as? String
                sentenceEnd = (s["sentence_end"] as? Bool) ?? false
            }
            return Event(name: name, sentence: sentence, sentenceEnd: sentenceEnd, errorMessage: errorMessage)
        }
    }

    // MARK: 工具

    private static func jsonString(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// 从本应用产出的标准 16bit/单声道 WAV 取裸 PCM；目标采样率不同则重采样。
    /// 复用 AudioRecorder.wavData 的固定头部布局（采样率 u32@24，PCM 从 44 起）。
    private static func pcmPayload(fromWAV wav: Data, targetRate: Int) -> Data {
        guard wav.count > 44 else { return Data() }
        let sourceRate = wav.withUnsafeBytes { raw -> Int in
            let b = raw.bindMemory(to: UInt8.self)
            return Int(b[24]) | Int(b[25]) << 8 | Int(b[26]) << 16 | Int(b[27]) << 24
        }
        let body = wav.subdata(in: 44..<wav.count)
        guard sourceRate > 0, sourceRate != targetRate else { return body }

        // Int16 PCM → Float → 重采样 → Int16 PCM
        let count = body.count / 2
        var samples = [Float](repeating: 0, count: count)
        body.withUnsafeBytes { raw in
            let i16 = raw.bindMemory(to: Int16.self)
            for i in 0..<count { samples[i] = Float(Int16(littleEndian: i16[i])) / 32767 }
        }
        let resampled = AudioRecorder.resample(samples, from: Double(sourceRate), to: Double(targetRate))
        var out = Data(capacity: resampled.count * 2)
        for s in resampled {
            let v = Int16(max(-1, min(1, s)) * 32767)
            withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
        }
        return out
    }
}
