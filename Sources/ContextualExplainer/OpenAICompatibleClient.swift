import Foundation

struct LLMClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchModels(settings: ModelSettings, apiKey: String) async throws -> [LLMModel] {
        let provider = settings.provider
        guard var components = URLComponents(string: provider.baseURL + "/models") else {
            throw ExplainerError.invalidBaseURL
        }
        if provider == .openRouter {
            components.queryItems = [URLQueryItem(name: "output_modalities", value: "text")]
        }

        guard let url = components.url else {
            throw ExplainerError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        addProviderHeaders(to: &request, provider: provider, apiKey: apiKey)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplainerError.noModels
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ExplainerError.requestFailed(httpResponse.statusCode, bodyText)
        }

        let catalog = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = catalog.data
            .filter { model in
                guard !model.id.isEmpty else { return false }
                switch provider {
                case .openRouter:
                    return model.supportsTextOutput
                case .openAI:
                    return Self.isLikelyOpenAIChatModel(model.id)
                }
            }
            .sorted { lhs, rhs in
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if comparison == .orderedSame {
                    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
                }
                return comparison == .orderedAscending
            }

        guard !models.isEmpty else {
            throw ExplainerError.noModels
        }

        return models
    }

    func explain(selection: String, context: String, settings: ModelSettings, apiKey: String) async throws -> WordExplanation {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ExplainerError.missingAPIKey }
        let content = try await completionContent(
            userPrompt: Self.userPrompt(selection: selection, context: context),
            settings: settings,
            apiKey: trimmedKey
        )
        var explanation = try Self.parseExplanation(from: content, selection: selection, context: context)

        if Self.needsRetry(explanation, selection: selection) {
            let retryContent = try await completionContent(
                userPrompt: Self.retryUserPrompt(selection: selection, context: context),
                settings: settings,
                apiKey: trimmedKey
            )
            explanation = try Self.parseExplanation(from: retryContent, selection: selection, context: context)
        }

        return explanation
    }

    func generateStory(terms: [StoryVocabularyTerm], settings: ModelSettings, apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ExplainerError.missingAPIKey }
        let maxTokens = max(settings.maxTokens, min(1800, 260 + terms.count * 10))
        let content = try await completionContent(
            userPrompt: Self.storyUserPrompt(terms: terms),
            settings: settings,
            apiKey: trimmedKey,
            systemPrompt: Self.storySystemPrompt,
            maxTokensOverride: maxTokens
        )
        return Self.cleanStory(content)
    }

    func translateStoryToChinese(_ story: String, settings: ModelSettings, apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStory = story.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ExplainerError.missingAPIKey }
        guard !trimmedStory.isEmpty else { throw ExplainerError.noText }

        let content = try await completionContent(
            userPrompt: Self.chineseTranslationUserPrompt(story: trimmedStory),
            settings: settings,
            apiKey: trimmedKey,
            systemPrompt: Self.chineseTranslationSystemPrompt,
            maxTokensOverride: max(settings.maxTokens, 900)
        )
        return Self.cleanPlainText(content)
    }

    func test(settings: ModelSettings, apiKey: String) async throws {
        _ = try await explain(
            selection: "bright",
            context: "The room felt bright after she opened the curtains.",
            settings: settings,
            apiKey: apiKey
        )
    }

    private func completionContent(
        userPrompt: String,
        settings: ModelSettings,
        apiKey: String,
        systemPrompt: String = Self.systemPrompt,
        maxTokensOverride: Int? = nil
    ) async throws -> String {
        let provider = settings.provider
        let model = ModelSettings.normalizedModel(settings.model, for: provider)
        guard let url = endpointURL(from: provider.baseURL) else { throw ExplainerError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addProviderHeaders(to: &request, provider: provider, apiKey: apiKey)
        request.timeoutInterval = 45

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: settings.temperature,
            maxTokens: maxTokensOverride ?? settings.maxTokens,
            maxTokenParameter: maxTokenParameter(for: provider, model: model),
            reasoningEffort: reasoningEffort(for: provider, model: model)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplainerError.noModelOutput
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ExplainerError.requestFailed(httpResponse.statusCode, bodyText)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = completion.choices.first?.message.contentText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            let finishReason = completion.choices.first?.finishReason ?? "unknown"
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ExplainerError.invalidModelOutput("No visible text was returned. Finish reason: \(finishReason). Raw response: \(bodyText)")
        }

        return content
    }

    private func endpointURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed.trimmedTrailingSlashes() + "/chat/completions")
    }

    private func addProviderHeaders(to request: inout URLRequest, provider: LLMProvider, apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        if provider == .openRouter {
            request.setValue("E2E", forHTTPHeaderField: "X-OpenRouter-Title")
            request.setValue("https://contextual-explainer.local", forHTTPHeaderField: "HTTP-Referer")
        }
    }

    private func maxTokenParameter(for provider: LLMProvider, model: String) -> ChatCompletionRequest.MaxTokenParameter {
        switch provider {
        case .openRouter:
            return .maxCompletionTokens
        case .openAI:
            return Self.usesMaxCompletionTokens(model: model) ? .maxCompletionTokens : .maxTokens
        }
    }

    private func reasoningEffort(for provider: LLMProvider, model: String) -> String? {
        guard provider == .openAI, Self.usesMaxCompletionTokens(model: model) else {
            return nil
        }
        if Self.usesNoneReasoningEffort(model: model) {
            return "none"
        }
        return "minimal"
    }

    private static func usesMaxCompletionTokens(model: String) -> Bool {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedModel.hasPrefix("gpt-5")
            || normalizedModel.hasPrefix("o1")
            || normalizedModel.hasPrefix("o3")
            || normalizedModel.hasPrefix("o4")
    }

    private static func usesNoneReasoningEffort(model: String) -> Bool {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedModel.hasPrefix("gpt-5.") else { return false }

        let versionPart = normalizedModel
            .dropFirst("gpt-5.".count)
            .prefix { $0.isNumber }
        guard let minorVersion = Int(versionPart) else { return false }
        return minorVersion >= 4
    }

    private static func isLikelyOpenAIChatModel(_ modelID: String) -> Bool {
        let id = modelID.lowercased()
        let excludedFragments = [
            "embedding",
            "moderation",
            "whisper",
            "tts",
            "dall-e",
            "image",
            "audio",
            "realtime",
            "transcribe",
            "search-preview"
        ]

        if excludedFragments.contains(where: { id.contains($0) }) {
            return false
        }

        return id.hasPrefix("gpt-")
            || id.hasPrefix("o1")
            || id.hasPrefix("o3")
            || id.hasPrefix("o4")
            || id.hasPrefix("chatgpt-")
            || id.hasPrefix("ft:gpt-")
            || id.hasPrefix("ft:o")
    }

    private static let systemPrompt = """
    You are an English teacher explaining vocabulary to a 10-year-old native English-speaking child.
    Explain the selected word or phrase using simple English.
    Focus only on its meaning in the given sentence or context.
    Do not translate first.
    For meaning_here, start directly with the meaning itself.
    Do not start meaning_here with "Here", "In this sentence", "In this context", "The word", "The phrase", or the selected word plus "means".
    The easy example must use the selected word or phrase itself.
    Do not replace the selected word or phrase with a synonym in the easy example.
    Identify the selected word or phrase's part of speech in this exact context.
    For part_of_speech, use only one of the fixed labels provided by the user.
    Decide how the selected word or phrase should be saved for history.
    Save it lowercase by default unless capitalization clearly has meaning in the context.
    Return JSON only. Do not wrap it in Markdown.
    """

    private static let storySystemPrompt = """
    You write clear, natural, and engaging English practice passages for a language learner.
    Use the target vocabulary naturally inside one coherent scene or small story.
    Prefer common, readable English, but do not make the writing unnaturally childish or overly simplified.
    Make the passage smooth and interesting enough that a learner would want to keep reading.
    Return plain text only. Do not add a title, bullet list, notes, explanations, Markdown, or JSON.
    """

    private static let chineseTranslationSystemPrompt = """
    You translate English practice passages into natural Chinese for a learner checking their own translation.
    Preserve the meaning of the English passage.
    Return only the Chinese translation.
    Do not add a title, notes, explanations, Markdown, or JSON.
    """

    private static func userPrompt(selection: String, context: String) -> String {
        """
        Selected word or phrase:
        \(selection)

        Sentence or nearby context:
        \(context)

        Strict rules:
        - part_of_speech must name the selected word or phrase's role in this exact context.
        - part_of_speech must be exactly one of these labels: \(PartOfSpeechCategory.promptList).
        - capitalization_kind must be exactly one of these labels: \(CapitalizationKind.promptList).
        - saved_selection is the form saved in history.
        - Lowercase saved_selection by default.
        - Keep capitalization only if it clearly matters in this context: proper name, place, brand, model, acronym, title, named work, or technical term with meaningful casing.
        - If the word is capitalized only because it begins a sentence, saved_selection must be lowercase and capitalization_kind must be "sentence_start".
        - If "May" means the month, keep "May"; if "may" means possibility, save "may".
        - If "Apple" means the company, keep "Apple"; if "apple" means fruit, save "apple".
        - meaning_here must start directly with the meaning, not with setup words.
        - Do not start meaning_here with "Here", "In this sentence", "In this context", "\(selection) means", or quoted "\(selection)".
        - Good meaning_here style: "showing clearly that something happened or worked"
        - easy_example must contain the selected word or phrase exactly as written above.
        - If the selected word is "illumination", easy_example must include "illumination".
        - Do not use only the simple replacement in easy_example.
        - easy_example should be one short, natural sentence a child could understand.

        Return this exact JSON shape:
        {
          "saved_selection": "history form, lowercase unless capitalization has clear meaning",
          "capitalization_kind": "one fixed label from the allowed list",
          "part_of_speech": "one fixed label from the allowed list",
          "meaning_here": "one or two short sentences",
          "simple_replacement": "a simpler word or phrase",
          "easy_example": "one easy example sentence"
        }
        """
    }

    private static func retryUserPrompt(selection: String, context: String) -> String {
        """
        The previous answer broke one or more required rules.

        Selected word or phrase:
        \(selection)

        Sentence or nearby context:
        \(context)

        Return JSON only. The easy_example field must contain "\(selection)" exactly.
        The part_of_speech field must describe the grammar role of "\(selection)" in this exact context.
        The part_of_speech field must be exactly one of these labels: \(PartOfSpeechCategory.promptList).
        The capitalization_kind field must be exactly one of these labels: \(CapitalizationKind.promptList).
        The saved_selection field must be lowercase unless capitalization clearly has meaning in this exact context.
        If capitalization is only from sentence position, saved_selection must be lowercase and capitalization_kind must be "sentence_start".
        The meaning_here field must start directly with the meaning itself.
        Do not start meaning_here with "Here", "In this sentence", "In this context", "\(selection) means", or quoted "\(selection)".
        Do not replace "\(selection)" with a synonym in easy_example.

        Return this exact JSON shape:
        {
          "saved_selection": "history form, lowercase unless capitalization has clear meaning",
          "capitalization_kind": "one fixed label from the allowed list",
          "part_of_speech": "one fixed label from the allowed list",
          "meaning_here": "one or two short sentences",
          "simple_replacement": "a simpler word or phrase",
          "easy_example": "one easy example sentence that contains the selected word or phrase exactly"
        }
        """
    }

    private static func storyUserPrompt(terms: [StoryVocabularyTerm]) -> String {
        let vocabularyList = terms.enumerated().map { index, term in
            "\(index + 1). \(term.sample) [\(term.partOfSpeech)]"
        }.joined(separator: "\n")
        let lengthGuide = storyLengthGuide(for: terms.count)

        return """
        Write one natural English practice passage using the vocabulary below.

        Vocabulary:
        \(vocabularyList)

        Length guide:
        \(lengthGuide)

        Strict rules:
        - Use every vocabulary item exactly as written.
        - Do not change the spelling or capitalization of a vocabulary item.
        - Use each vocabulary item in a natural, ordinary way for this new passage.
        - Treat the part-of-speech label as a guide, not as a reason to force an awkward sentence.
        - Do not reuse or imitate the original history context for a vocabulary item.
        - Put the vocabulary into one coherent scene, moment, or small story.
        - Make the passage fluent, vivid, and a little interesting.
        - Use clear everyday English for the surrounding words, but do not force every non-vocabulary word to be extremely basic.
        - If many vocabulary items are given, use short paragraphs and prioritize natural flow.
        - Do not define the words.
        - Do not make a list.
        - Do not add a title.
        - Return only the passage text.
        """
    }

    private static func storyLengthGuide(for termCount: Int) -> String {
        switch termCount {
        case 0...10:
            return "About 70-120 words."
        case 11...30:
            return "About 140-240 words."
        case 31...50:
            return "About 220-380 words."
        default:
            return "Use the shortest passage that still feels natural. Multiple short paragraphs are okay."
        }
    }

    private static func chineseTranslationUserPrompt(story: String) -> String {
        """
        Translate this English story into natural Chinese.
        Return only the Chinese translation.

        English story:
        \(story)
        """
    }

    private static func parseExplanation(from content: String, selection: String, context: String) throws -> WordExplanation {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw ExplainerError.invalidModelOutput(content)
        }

        do {
            let decoded = try JSONDecoder().decode(ModelExplanationPayload.self, from: data)
            let capitalizationKind = CapitalizationKind.normalizedLabel(decoded.capitalizationKind)
            return WordExplanation(
                selection: savedSelection(
                    decoded.savedSelection,
                    originalSelection: selection,
                    capitalizationKind: capitalizationKind
                ),
                context: context,
                partOfSpeech: PartOfSpeechCategory.normalizedLabel(decoded.partOfSpeech),
                meaningHere: directMeaningText(decoded.meaningHere, selection: selection),
                simpleReplacement: decoded.simpleReplacement,
                whyItFits: decoded.whyItFits ?? "",
                easyExample: decoded.easyExample,
                notThisMeaning: decoded.notThisMeaning,
                capitalizationKind: capitalizationKind
            )
        } catch {
            throw ExplainerError.invalidModelOutput(cleaned)
        }
    }

    private static func needsRetry(_ explanation: WordExplanation, selection: String) -> Bool {
        let partOfSpeech = PartOfSpeechCategory.normalizedLabel(explanation.partOfSpeech)
        return !containsSelectedText(explanation.easyExample, selection: selection) || partOfSpeech.isEmpty
    }

    private static func containsSelectedText(_ text: String, selection: String) -> Bool {
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return true }
        return text.range(of: trimmedSelection, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func savedSelection(
        _ modelSelection: String?,
        originalSelection: String,
        capitalizationKind: String?
    ) -> String {
        let original = originalSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = modelSelection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = proposed.isEmpty ? original : proposed
        guard !source.isEmpty else { return original }

        if CapitalizationKind.preservesCapitalization(capitalizationKind) {
            return source
        }

        return source.lowercased()
    }

    private static func directMeaningText(_ text: String, selection: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        var didStrip = true

        while didStrip {
            didStrip = false

            let contextPrefixes = [
                "In this sentence,",
                "In this context,",
                "In this use,",
                "Here,",
                "Here"
            ]
            for prefix in contextPrefixes where stripAnchoredPrefix(prefix, from: &cleaned) {
                didStrip = true
            }

            var meaningPrefixes = [
                "it means",
                "this means",
                "means"
            ]

            if !trimmedSelection.isEmpty {
                let quotedSelections = [
                    trimmedSelection,
                    "\"\(trimmedSelection)\"",
                    "'\(trimmedSelection)'",
                    "“\(trimmedSelection)”",
                    "‘\(trimmedSelection)’"
                ]

                for selectedText in quotedSelections {
                    meaningPrefixes.append("\(selectedText) means")
                    meaningPrefixes.append("\(selectedText) refers to")
                    meaningPrefixes.append("the word \(selectedText) means")
                    meaningPrefixes.append("the phrase \(selectedText) means")
                }
            }

            for prefix in meaningPrefixes where stripAnchoredPrefix(prefix, from: &cleaned) {
                didStrip = true
            }
        }

        return cleaned.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    private static func stripAnchoredPrefix(_ prefix: String, from text: inout String) -> Bool {
        guard let range = text.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else {
            return false
        }

        text.removeSubrange(range)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.first == "," || text.first == "." || text.first == ":" || text.first == ";" {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return true
    }

    private static func cleanStory(_ content: String) -> String {
        cleanPlainText(content, removablePrefixes: ["Story:", "Passage:"])
    }

    private static func cleanPlainText(
        _ content: String,
        removablePrefixes: [String] = ["Chinese:", "Translation:", "中文翻译：", "翻译："]
    ) -> String {
        var cleaned = content
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in removablePrefixes where cleaned.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
            cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }
}

private struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
    var maxTokens: Int
    var maxTokenParameter: MaxTokenParameter
    var reasoningEffort: String?

    enum MaxTokenParameter {
        case maxTokens
        case maxCompletionTokens
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(temperature, forKey: .temperature)
        switch maxTokenParameter {
        case .maxTokens:
            try container.encode(maxTokens, forKey: .maxTokens)
        case .maxCompletionTokens:
            try container.encode(maxTokens, forKey: .maxCompletionTokens)
        }
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
    }
}

private struct ChatMessage: Encodable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        var contentText: String

        enum CodingKeys: String, CodingKey {
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try? container.decode(String.self, forKey: .content) {
                contentText = text
                return
            }

            if let parts = try? container.decode([MessageContentPart].self, forKey: .content) {
                contentText = parts.compactMap(\.text).joined()
                return
            }

            contentText = ""
        }
    }

    struct MessageContentPart: Decodable {
        var text: String?
    }
}

private struct ModelsResponse: Decodable {
    var data: [LLMModel]
}

private struct ModelExplanationPayload: Decodable {
    var savedSelection: String?
    var capitalizationKind: String?
    var partOfSpeech: String?
    var meaningHere: String
    var simpleReplacement: String
    var whyItFits: String?
    var easyExample: String
    var notThisMeaning: String?

    enum CodingKeys: String, CodingKey {
        case savedSelection = "saved_selection"
        case capitalizationKind = "capitalization_kind"
        case partOfSpeech = "part_of_speech"
        case meaningHere = "meaning_here"
        case simpleReplacement = "simple_replacement"
        case whyItFits = "why_it_fits"
        case easyExample = "easy_example"
        case notThisMeaning = "not_this_meaning"
    }
}

private extension String {
    func trimmedTrailingSlashes() -> String {
        var result = self
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
