import Foundation

/// LLM 后处理：把口述转写稿清理为成稿级文本（去填充词、自我纠正归并、标点与格式化）
/// 并根据目标应用与个人词典做上下文感知调整
struct Polisher {
    /// 按目标应用类别调整语气与格式
    private static let styleRules: [(keys: [String], hint: String)] = [
        (["mail", "outlook", "spark", "airmail"],
         "这是邮件场景：用邮件正文语气，结构清晰、表达完整礼貌。"),
        (["wechat", "xinwechat", "slack", "telegram", "discord", "imessage", "messages", "lark", "feishu", "dingtalk", "qq"],
         "这是即时聊天场景：保持简短自然的口语风格，不要添加称呼或落款。"),
        (["xcode", "vscode", "cursor", "jetbrains", "idea", "terminal", "iterm", "warp", "zed"],
         "这是技术场景：专业术语、代码标识符与英文命令保留英文原样。"),
        (["notion", "obsidian", "craft", "notes", "pages", "word", "docs", "typora", "bear"],
         "这是笔记/文档场景：适当使用列表与分段组织内容。"),
    ]

    func polish(_ raw: String, appName: String?, bundleId: String?, forceTranslationTo: String? = nil) async throws -> String {
        let key = SettingsStore.shared.llmKey(forProvider: SettingsStore.shared.llmProviderId)
        guard !key.isEmpty else { return raw }

        var system = """
        你是语音听写的后处理引擎。把口述转写稿整理为可直接发送的成稿文本：
        - 删除“嗯、呃、那个、um、uh、you know”等填充词与无意义重复
        - 说话人中途自我纠正时，只保留最终意图
        - 补全标点，必要时分段；口述的列表或步骤整理为列表格式
        - 保持原始语言与原意，不增删实质内容，不回答文中的问题
        只输出整理后的文本，不要任何解释或前后缀。
        """
        let terms = SettingsStore.shared.dictionaryTerms
        if !terms.isEmpty {
            system += "\n用户词典（这些专有名词请优先采用此写法）：\(terms.joined(separator: "、"))"
        }
        if let appName, !appName.isEmpty {
            system += "\n该文本将被粘贴到应用「\(appName)」中。"
        }
        if let hint = Self.styleHint(appName: appName, bundleId: bundleId) {
            system += hint
        }
        if let target = forceTranslationTo ?? SettingsStore.shared.translationTargetName {
            system += "\n最后一步：把整理后的文本翻译成\(target)，措辞自然地道，如同母语者所写，只输出译文。"
        }

        return try await chat(system: system, user: raw, fallback: raw)
    }

    /// 随便问：口述问题，直接输出答案
    func answer(_ question: String, appName: String?) async throws -> String {
        let key = SettingsStore.shared.llmKey(forProvider: SettingsStore.shared.llmProviderId)
        guard !key.isEmpty else { throw STTError.missingAPIKey }

        var system = """
        你是即问即答助手。直接、简洁地回答用户口述的问题：只给出答案本身，不要客套、不要复述问题。
        用与提问相同的语言回答，纯文本输出（可分段），内容将被直接粘贴到用户正在使用的应用中。
        """
        if let appName, !appName.isEmpty {
            system += "\n用户当前正在使用应用「\(appName)」。"
        }
        return try await chat(system: system, user: question, fallback: question)
    }

    /// 语音编辑：根据口述指令改写选中文本
    func edit(_ original: String, instruction: String, appName: String?) async throws -> String {
        let key = SettingsStore.shared.llmKey(forProvider: SettingsStore.shared.llmProviderId)
        guard !key.isEmpty else { throw STTError.missingAPIKey }

        var system = """
        你是文本编辑引擎。用户选中了一段文本，并口述了一条修改指令（如“改短一点”“换成正式语气”“翻译成英文”“改成列表”）。
        请对原文执行该指令，保持原文语言（除非指令要求翻译），只输出修改后的文本，不要任何解释或前后缀。
        """
        if let appName, !appName.isEmpty {
            system += "\n该文本位于应用「\(appName)」中。"
        }
        let user = "【原文】\n\(original)\n\n【修改指令】\n\(instruction)"
        return try await chat(system: system, user: user, fallback: original)
    }

    /// 调用所选 LLM 厂商的 Chat Completions（OpenAI 兼容），空结果时返回 fallback
    private func chat(system: String, user: String, fallback: String) async throws -> String {
        let providerId = SettingsStore.shared.llmProviderId
        let provider = LLMProviderInfo.byId(providerId)
        let key = SettingsStore.shared.llmKey(forProvider: providerId)
        guard !key.isEmpty else { return fallback }

        let base = SettingsStore.shared.baseURL(forProvider: providerId, default: provider.base)
        var request = URLRequest(url: URL(string: "\(base)/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = SettingsStore.shared.requestTimeout(forProvider: providerId)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": SettingsStore.shared.llmModel(forProvider: providerId),
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw STTError.http(code, String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let content = try JSONDecoder().decode(ChatResponse.self, from: data)
            .choices.first?.message.content ?? ""
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func styleHint(appName: String?, bundleId: String?) -> String? {
        let haystack = ((appName ?? "") + " " + (bundleId ?? "")).lowercased()
        guard !haystack.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        for rule in styleRules where rule.keys.contains(where: { haystack.contains($0) }) {
            return rule.hint
        }
        return nil
    }
}
