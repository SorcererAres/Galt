import Foundation

/// 语音转写引擎抽象：云端（Groq Whisper）与本地（whisper.cpp，M3 接入）可切换
protocol STTProvider {
    var name: String { get }
    func transcribe(wav: Data) async throws -> String
}

enum STTError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case empty
    case speechNotAuthorized
    case localUnavailable
    case modelMissing

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未设置当前厂商的 API Key：菜单栏 → 设置… → 转写引擎 / 润色模型"
        case .http(let code, let message):
            return "请求失败（HTTP \(code)）：\(message.prefix(120))"
        case .empty:
            return "没有识别到语音内容"
        case .speechNotAuthorized:
            return "本地听写未授权：系统设置 → 隐私与安全性 → 语音识别 中允许 Galt"
        case .localUnavailable:
            return "本地听写引擎不可用，请检查设置中的语言或改用云端引擎"
        case .modelMissing:
            return "Whisper 模型尚未下载：设置 → 本地离线引擎 → 下载模型"
        }
    }
}

// 云端转写的具体厂商实现见 CloudProviders.swift（CloudSTTProvider）
