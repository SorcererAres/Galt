import Foundation
import Speech

/// 本地离线转写：Apple 设备端语音识别（无需联网与 API Key）
struct AppleSpeechProvider: STTProvider {
    let name = "本地听写（Apple Speech）"

    func transcribe(wav: Data) async throws -> String {
        let status = await Self.requestAuthorization()
        guard status == .authorized else { throw STTError.speechNotAuthorized }

        let locale = Locale(identifier: SettingsStore.shared.localLocaleId)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw STTError.localUnavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("galt-\(UUID().uuidString).wav")
        try wav.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // 个人词典（含自动学习词）：提升专有名词识别率
        request.contextualStrings = SettingsStore.shared.effectiveDictionaryTerms

        let text: String = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw STTError.empty }
        return trimmed
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
