import Foundation

// MARK: - 厂商目录

/// 云端转写厂商
struct STTProviderInfo: Identifiable {
    enum Kind {
        /// OpenAI 兼容的 audio/transcriptions multipart 接口
        case openAICompatible(base: String, model: String)
        /// 阿里云百炼 DashScope 多模态接口（qwen3-asr-flash）
        case dashscope
        /// 火山引擎大模型录音识别极速版
        case volcano
    }

    let id: String
    let name: String
    let kind: Kind
    let keyHint: String

    /// 火山引擎需要 App ID + Access Token 双凭证
    var needsAppKey: Bool {
        if case .volcano = kind { return true }
        return false
    }

    static let all: [STTProviderInfo] = [
        .init(id: "groq", name: "Groq Whisper", kind: .openAICompatible(base: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo"), keyHint: "console.groq.com 免费获取"),
        .init(id: "siliconflow", name: "硅基流动 SenseVoice", kind: .openAICompatible(base: "https://api.siliconflow.cn/v1", model: "FunAudioLLM/SenseVoiceSmall"), keyHint: "cloud.siliconflow.cn 获取，国内直连"),
        .init(id: "dashscope", name: "阿里云百炼（Qwen3 ASR）", kind: .dashscope, keyHint: "bailian.console.aliyun.com 获取 DashScope API Key"),
        .init(id: "volcano", name: "火山引擎（大模型录音识别）", kind: .volcano, keyHint: "console.volcengine.com → 语音技术，需 App ID 与 Access Token"),
        .init(id: "openai", name: "OpenAI", kind: .openAICompatible(base: "https://api.openai.com/v1", model: "gpt-4o-mini-transcribe"), keyHint: "platform.openai.com 获取"),
    ]

    static func byId(_ id: String) -> STTProviderInfo {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - 火山 ASR 模型(配置驱动:协议 + 资源 + 接口,预设可一键带出,亦可自填)

/// 火山 ASR 的传输协议。不同协议的请求/响应处理是代码(适配器),配置只能在已实现的协议里选。
enum VolcanoASRProtocol: String, CaseIterable, Identifiable {
    case flash      // HTTP 一次性(录音文件极速版)
    case streaming  // WebSocket 流式(流式语音识别大模型)
    case fileAsync  // HTTP 异步(录音文件标准版:submit 提交 + query 轮询)

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .flash: return "一次性 (HTTP)"
        case .streaming: return "流式 (WebSocket)"
        case .fileAsync: return "异步文件 (HTTP 提交+轮询)"
        }
    }
}

/// 一个火山 ASR 模型 = 显示名 + resourceId + 接口地址 + 协议。预设供一键带出,用户可在此基础上自填。
struct VolcanoASRModel: Identifiable {
    let id: String
    let name: String
    let resourceId: String
    let endpoint: String
    let proto: VolcanoASRProtocol

    static let presets: [VolcanoASRModel] = [
        .init(id: "auc_turbo", name: "录音文件极速版", resourceId: "volc.bigasr.auc_turbo",
              endpoint: "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash", proto: .flash),
        // 标准版异步：endpoint 为基址，代码自动拼 /submit 与 /query
        .init(id: "auc", name: "录音文件标准版", resourceId: "volc.bigasr.auc",
              endpoint: "https://openspeech.bytedance.com/api/v3/auc/bigmodel", proto: .fileAsync),
        .init(id: "sauc_duration", name: "流式·小时版", resourceId: "volc.bigasr.sauc.duration",
              endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel", proto: .streaming),
        .init(id: "sauc_concurrent", name: "流式·并发版", resourceId: "volc.bigasr.sauc.concurrent",
              endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel", proto: .streaming),
    ]

    static var `default`: VolcanoASRModel { presets[0] }

    /// 与给定配置完全一致的预设;无匹配返回 nil(即「自定义」)
    static func matching(resourceId: String, endpoint: String, proto: VolcanoASRProtocol) -> VolcanoASRModel? {
        presets.first { $0.resourceId == resourceId && $0.endpoint == endpoint && $0.proto == proto }
    }
}

/// 润色/翻译/问答使用的 LLM 厂商（全部 OpenAI 兼容 chat/completions）
struct LLMProviderInfo: Identifiable {
    let id: String
    let name: String
    let base: String
    let defaultModel: String
    let keyHint: String

    static let all: [LLMProviderInfo] = [
        .init(id: "groq", name: "Groq", base: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile", keyHint: "console.groq.com 免费获取"),
        .init(id: "dashscope", name: "阿里云百炼（通义千问）", base: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus", keyHint: "bailian.console.aliyun.com 获取 DashScope API Key"),
        .init(id: "ark", name: "火山方舟（豆包）", base: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-1-5-pro-32k-250115", keyHint: "console.volcengine.com/ark 获取，模型填模型名或接入点 ID"),
        .init(id: "deepseek", name: "DeepSeek", base: "https://api.deepseek.com/v1", defaultModel: "deepseek-chat", keyHint: "platform.deepseek.com 获取"),
        .init(id: "siliconflow", name: "硅基流动", base: "https://api.siliconflow.cn/v1", defaultModel: "deepseek-ai/DeepSeek-V3", keyHint: "cloud.siliconflow.cn 获取，国内直连"),
        .init(id: "openai", name: "OpenAI", base: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", keyHint: "platform.openai.com 获取"),
    ]

    static func byId(_ id: String) -> LLMProviderInfo {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - 厂商探测（OpenAI 兼容 /models：用于「验证」与「获取模型」）

enum ProviderProbe {
    private struct ModelList: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    /// GET {base}/models，返回模型 id 列表；非 200 抛 STTError.http
    static func fetchModels(base: String, key: String, timeout: TimeInterval) async throws -> [String] {
        guard !key.isEmpty else { throw STTError.missingAPIKey }
        guard let url = URL(string: "\(base)/models") else { throw STTError.http(-1, "接口地址无效") }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw STTError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        let ids = (try? JSONDecoder().decode(ModelList.self, from: data))?.data.map(\.id) ?? []
        return ids.sorted()
    }
}

// MARK: - 云端转写统一实现

/// 按设置中选择的厂商路由的云端转写
struct CloudSTTProvider: STTProvider {
    var name: String {
        STTProviderInfo.byId(SettingsStore.shared.cloudSTTProviderId).name
    }

    func transcribe(wav: Data) async throws -> String {
        let info = STTProviderInfo.byId(SettingsStore.shared.cloudSTTProviderId)
        let text: String
        switch info.kind {
        case .openAICompatible(let base, let model):
            text = try await transcribeOpenAICompatible(wav: wav, providerId: info.id, base: base, model: model)
        case .dashscope:
            text = try await transcribeDashScope(wav: wav)
        case .volcano:
            text = try await transcribeVolcano(wav: wav)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw STTError.empty }
        return trimmed
    }

    // MARK: 连接验证（模型库「验证」按钮）

    /// 用与真实听写完全相同的链路做连接验证：
    /// - OpenAI 兼容：走免费的 `GET /models`，不消耗转写额度；
    /// - 火山 / Qwen3：发一段约 1 秒的验证音频跑真实接口。
    ///
    /// 容忍空/无意义的转写结果（验证音频本就无语义），只要传输、鉴权、厂商状态码成功即视为连通。
    /// 凭证 / 端点 / Resource ID / 协议等取自 SettingsStore（表单各绑定已实时落库）。
    func verify(providerId: String) async throws {
        let info = STTProviderInfo.byId(providerId)
        switch info.kind {
        case .openAICompatible(let base, _):
            let key = SettingsStore.shared.sttKey(forProvider: providerId)
            guard !key.isEmpty else { throw STTError.missingAPIKey }
            let effectiveBase = SettingsStore.shared.baseURL(forProvider: providerId, default: base)
            let timeout = SettingsStore.shared.requestTimeout(forProvider: providerId)
            _ = try await ProviderProbe.fetchModels(base: effectiveBase, key: key, timeout: timeout)
        case .dashscope:
            _ = try await transcribeDashScope(wav: Self.verificationWav())
        case .volcano:
            _ = try await transcribeVolcano(wav: Self.verificationWav())
        }
    }

    /// 连接验证用的最小音频载荷：约 1 秒、16k/16bit、极低音量正弦。
    /// 用有信号但无语义的音频，既能触达模型、又避免纯静音被部分厂商当作「无音频」拒绝。
    static func verificationWav() -> Data {
        let sampleRate = 16000
        let samples = (0..<sampleRate).map { i in
            0.03 * sinf(2 * Float.pi * 220 * Float(i) / Float(sampleRate))
        }
        return AudioRecorder.wavData(from: samples, sampleRate: sampleRate)
    }

    // MARK: OpenAI 兼容（Groq / OpenAI / 硅基流动）

    private func transcribeOpenAICompatible(wav: Data, providerId: String, base: String, model: String) async throws -> String {
        let key = SettingsStore.shared.sttKey(forProvider: providerId)
        guard !key.isEmpty else { throw STTError.missingAPIKey }

        let effectiveBase = SettingsStore.shared.baseURL(forProvider: providerId, default: base)
        var request = URLRequest(url: URL(string: "\(effectiveBase)/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = SettingsStore.shared.requestTimeout(forProvider: providerId)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func formField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        formField("model", model)
        formField("response_format", "json")
        // 个人词典作为引导提示，提升专有名词识别率
        let terms = SettingsStore.shared.dictionaryTerms
        if !terms.isEmpty {
            formField("prompt", terms.joined(separator: ", "))
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw STTError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        struct TranscriptionResponse: Decodable { let text: String }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
    }

    // MARK: 阿里云百炼（DashScope 多模态，base64 音频）

    private func transcribeDashScope(wav: Data) async throws -> String {
        let key = SettingsStore.shared.sttKey(forProvider: "dashscope")
        guard !key.isEmpty else { throw STTError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "qwen3-asr-flash",
            "input": [
                "messages": [
                    ["role": "system", "content": [["text": ""]]],
                    ["role": "user", "content": [["audio": "data:audio/wav;base64,\(wav.base64EncodedString())"]]],
                ],
            ],
            "parameters": [
                "asr_options": ["enable_itn": true],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw STTError.http(code, "阿里云百炼：" + (String(data: data, encoding: .utf8) ?? ""))
        }
        struct DSResponse: Decodable {
            struct Output: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable {
                        struct Content: Decodable { let text: String? }
                        let content: [Content]
                    }
                    let message: Message
                }
                let choices: [Choice]
            }
            let output: Output
        }
        let decoded = try JSONDecoder().decode(DSResponse.self, from: data)
        return decoded.output.choices.first?.message.content.compactMap(\.text).joined() ?? ""
    }

    // MARK: 火山引擎（按所选模型的协议分发：一次性 HTTP / 流式 WebSocket）

    private func transcribeVolcano(wav: Data) async throws -> String {
        let appKey = SettingsStore.shared.volcanoAppKey
        let accessKey = SettingsStore.shared.sttKey(forProvider: "volcano")
        guard !appKey.isEmpty, !accessKey.isEmpty else { throw STTError.missingAPIKey }

        let proto = VolcanoASRProtocol(rawValue: SettingsStore.shared.volcanoProtocol) ?? .flash
        let resourceId = SettingsStore.shared.volcanoResourceId
        let endpoint = SettingsStore.shared.volcanoEndpoint
        let timeout = SettingsStore.shared.requestTimeout(forProvider: "volcano")

        switch proto {
        case .flash:
            return try await transcribeVolcanoFlash(
                wav: wav, endpoint: endpoint, resourceId: resourceId,
                appKey: appKey, accessKey: accessKey, timeout: timeout
            )
        case .streaming:
            return try await VolcanoStreamingASR.transcribe(
                wav: wav, endpoint: endpoint, resourceId: resourceId,
                appKey: appKey, accessKey: accessKey, timeout: timeout
            )
        case .fileAsync:
            return try await transcribeVolcanoFileAsync(
                wav: wav, baseEndpoint: endpoint, resourceId: resourceId,
                appKey: appKey, accessKey: accessKey, timeout: timeout
            )
        }
    }

    /// 录音文件识别·一次性 HTTP（极速版 auc_turbo 等 flash 资源）
    private func transcribeVolcanoFlash(wav: Data, endpoint: String, resourceId: String,
                                        appKey: String, accessKey: String, timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: endpoint) else { throw STTError.http(-1, "火山接口地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")

        let payload: [String: Any] = [
            "user": ["uid": "galt"],
            "audio": ["format": "wav", "data": wav.base64EncodedString()],
            "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let statusCode = http?.value(forHTTPHeaderField: "X-Api-Status-Code") ?? ""
        guard statusCode == "20000000" else {
            let message = http?.value(forHTTPHeaderField: "X-Api-Message")
                ?? String(data: data, encoding: .utf8) ?? ""
            throw STTError.http(http?.statusCode ?? -1, "火山引擎 \(statusCode)：\(message)")
        }
        struct VolcResponse: Decodable {
            struct Result: Decodable { let text: String? }
            let result: Result?
        }
        return (try? JSONDecoder().decode(VolcResponse.self, from: data))?.result?.text ?? ""
    }

    /// 录音文件识别·标准版（异步 auc）：submit 提交任务 → query 轮询直至完成。
    /// baseEndpoint 为基址（如 …/api/v3/auc/bigmodel），自动拼 /submit 与 /query。
    /// 状态码：20000000 完成；20000001 排队；20000002 处理中；其它为失败。
    private func transcribeVolcanoFileAsync(wav: Data, baseEndpoint: String, resourceId: String,
                                           appKey: String, accessKey: String, timeout: TimeInterval) async throws -> String {
        let base = baseEndpoint.hasSuffix("/") ? String(baseEndpoint.dropLast()) : baseEndpoint
        guard let submitURL = URL(string: base + "/submit"),
              let queryURL = URL(string: base + "/query") else {
            throw STTError.http(-1, "火山接口地址无效")
        }
        // 同一个 Request-Id 贯穿 submit 与 query，作为任务句柄
        let requestId = UUID().uuidString

        func makeRequest(_ url: URL, body: [String: Any]) throws -> URLRequest {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = timeout
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
            req.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
            req.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
            req.setValue(requestId, forHTTPHeaderField: "X-Api-Request-Id")
            req.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }

        // 1) 提交任务
        let submitBody: [String: Any] = [
            "user": ["uid": "galt"],
            "audio": ["format": "wav", "data": wav.base64EncodedString()],
            "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true],
        ]
        let (sData, sResp) = try await URLSession.shared.data(for: try makeRequest(submitURL, body: submitBody))
        let sHTTP = sResp as? HTTPURLResponse
        let sCode = sHTTP?.value(forHTTPHeaderField: "X-Api-Status-Code") ?? ""
        guard sCode == "20000000" else {
            let msg = sHTTP?.value(forHTTPHeaderField: "X-Api-Message") ?? String(data: sData, encoding: .utf8) ?? ""
            throw STTError.http(sHTTP?.statusCode ?? -1, "火山提交失败 \(sCode)：\(msg)")
        }

        // 2) 轮询查询（请求体为空 {}），直到完成或超时
        struct VolcResponse: Decodable {
            struct Result: Decodable { let text: String? }
            let result: Result?
        }
        let interval: UInt64 = 1_500_000_000 // 1.5s
        let deadline = Date().addingTimeInterval(max(timeout, 180)) // 长音频留足时间
        while Date() < deadline {
            let (qData, qResp) = try await URLSession.shared.data(for: try makeRequest(queryURL, body: [:]))
            let qHTTP = qResp as? HTTPURLResponse
            let qCode = qHTTP?.value(forHTTPHeaderField: "X-Api-Status-Code") ?? ""
            switch qCode {
            case "20000000":
                let text = (try? JSONDecoder().decode(VolcResponse.self, from: qData))?.result?.text ?? ""
                return text
            case "20000001", "20000002": // 排队 / 处理中
                try await Task.sleep(nanoseconds: interval)
            default:
                let msg = qHTTP?.value(forHTTPHeaderField: "X-Api-Message") ?? String(data: qData, encoding: .utf8) ?? ""
                throw STTError.http(qHTTP?.statusCode ?? -1, "火山查询失败 \(qCode)：\(msg)")
            }
        }
        throw STTError.http(-1, "火山识别超时：任务长时间未完成")
    }
}
