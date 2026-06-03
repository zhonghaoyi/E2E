import Foundation

struct WordExplanation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var selection: String
    var context: String
    var partOfSpeech: String?
    var meaningHere: String
    var simpleReplacement: String
    var whyItFits: String
    var easyExample: String
    var notThisMeaning: String?
    var capitalizationKind: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        selection: String,
        context: String,
        partOfSpeech: String? = nil,
        meaningHere: String,
        simpleReplacement: String,
        whyItFits: String,
        easyExample: String,
        notThisMeaning: String? = nil,
        capitalizationKind: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.selection = selection
        self.context = context
        self.partOfSpeech = partOfSpeech
        self.meaningHere = meaningHere
        self.simpleReplacement = simpleReplacement
        self.whyItFits = whyItFits
        self.easyExample = easyExample
        self.notThisMeaning = notThisMeaning
        self.capitalizationKind = capitalizationKind
        self.createdAt = createdAt
    }
}

enum CapitalizationKind: String, CaseIterable, Sendable {
    case common
    case sentenceStart = "sentence_start"
    case properName = "proper_name"
    case acronym
    case brandOrModel = "brand_or_model"
    case titleOrNamedWork = "title_or_named_work"
    case technicalTerm = "technical_term"
    case otherMeaningful = "other_meaningful"

    static var promptList: String {
        allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
    }

    static func normalizedLabel(_ label: String?) -> String {
        let normalized = (label ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        guard !normalized.isEmpty else { return Self.common.rawValue }

        if let exactMatch = allCases.first(where: { $0.rawValue == normalized }) {
            return exactMatch.rawValue
        }

        if normalized.contains("sentence") || normalized.contains("start") {
            return Self.sentenceStart.rawValue
        }
        if normalized.contains("proper") || normalized.contains("name") || normalized.contains("person") || normalized.contains("place") {
            return Self.properName.rawValue
        }
        if normalized.contains("acronym") || normalized.contains("abbreviation") {
            return Self.acronym.rawValue
        }
        if normalized.contains("brand") || normalized.contains("model") {
            return Self.brandOrModel.rawValue
        }
        if normalized.contains("title") || normalized.contains("work") {
            return Self.titleOrNamedWork.rawValue
        }
        if normalized.contains("technical") || normalized.contains("term") {
            return Self.technicalTerm.rawValue
        }
        if normalized.contains("meaning") || normalized.contains("keep") || normalized.contains("capital") {
            return Self.otherMeaningful.rawValue
        }

        return Self.common.rawValue
    }

    static func preservesCapitalization(_ label: String?) -> Bool {
        switch normalizedLabel(label) {
        case Self.properName.rawValue,
            Self.acronym.rawValue,
            Self.brandOrModel.rawValue,
            Self.titleOrNamedWork.rawValue,
            Self.technicalTerm.rawValue,
            Self.otherMeaningful.rawValue:
            return true
        default:
            return false
        }
    }
}

struct StoryVocabularyTerm: Identifiable, Hashable, Sendable {
    var sample: String
    var partOfSpeech: String
    var meaning: String

    var id: String {
        "\(sample)||\(partOfSpeech)"
    }
}

enum PartOfSpeechCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case noun
    case verb
    case adjective
    case adverb
    case pronoun
    case determiner
    case preposition
    case conjunction
    case interjection
    case nounPhrase = "noun phrase"
    case verbPhrase = "verb phrase"
    case adjectivePhrase = "adjective phrase"
    case adverbPhrase = "adverb phrase"
    case prepositionalPhrase = "prepositional phrase"
    case other

    var id: String { rawValue }

    static var promptList: String {
        allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
    }

    static func normalizedLabel(_ label: String?) -> String {
        let normalized = (label ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        guard !normalized.isEmpty else { return Self.other.rawValue }

        if let exactMatch = allCases.first(where: { $0.rawValue == normalized }) {
            return exactMatch.rawValue
        }

        if normalized.contains("prepositional") {
            return Self.prepositionalPhrase.rawValue
        }
        if normalized.contains("noun phrase") || normalized.contains("nominal phrase") {
            return Self.nounPhrase.rawValue
        }
        if normalized.contains("verb phrase") || normalized.contains("phrasal verb") {
            return Self.verbPhrase.rawValue
        }
        if normalized.contains("adjective phrase") || normalized.contains("adjectival phrase") {
            return Self.adjectivePhrase.rawValue
        }
        if normalized.contains("adverb phrase") || normalized.contains("adverbial phrase") {
            return Self.adverbPhrase.rawValue
        }
        if normalized.contains("pronoun") {
            return Self.pronoun.rawValue
        }
        if normalized.contains("determiner") || normalized.contains("article") {
            return Self.determiner.rawValue
        }
        if normalized.contains("preposition") {
            return Self.preposition.rawValue
        }
        if normalized.contains("conjunction") {
            return Self.conjunction.rawValue
        }
        if normalized.contains("interjection") {
            return Self.interjection.rawValue
        }
        if normalized.contains("adjective") || normalized.contains("adjectival") {
            return Self.adjective.rawValue
        }
        if normalized.contains("adverb") || normalized.contains("adverbial") {
            return Self.adverb.rawValue
        }
        if normalized.contains("verb") || normalized.contains("participle") || normalized.contains("gerund") {
            return Self.verb.rawValue
        }
        if normalized.contains("noun") || normalized.contains("nominal") {
            return Self.noun.rawValue
        }

        return Self.other.rawValue
    }
}

struct ModelSettings: Codable, Equatable, Sendable {
    static let openRouterBaseURL = "https://openrouter.ai/api/v1"
    static let openAIBaseURL = "https://api.openai.com/v1"
    static let openRouterDefaultModel = "openai/gpt-5-nano"
    static let openAIDefaultModel = "gpt-5-nano"

    var provider: LLMProvider
    var providerName: String
    var baseURL: String
    var model: String
    var temperature: Double
    var maxTokens: Int
    var shortcutMode: ShortcutMode
    var isPanelPinned: Bool
    var historyFilePath: String

    static let defaults = ModelSettings(
        provider: .openRouter,
        providerName: "OpenRouter",
        baseURL: openRouterBaseURL,
        model: openRouterDefaultModel,
        temperature: 0.2,
        maxTokens: 700,
        shortcutMode: .doubleCommandC,
        isPanelPinned: false,
        historyFilePath: ""
    )

    init(
        provider: LLMProvider,
        providerName: String,
        baseURL: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        shortcutMode: ShortcutMode,
        isPanelPinned: Bool,
        historyFilePath: String
    ) {
        self.provider = provider
        self.providerName = providerName
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.shortcutMode = shortcutMode
        self.isPanelPinned = isPanelPinned
        self.historyFilePath = historyFilePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .provider)
        let decodedProviderName = try container.decodeIfPresent(String.self, forKey: .providerName)
        let decodedBaseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        provider = decodedProvider ?? Self.inferredProvider(providerName: decodedProviderName, baseURL: decodedBaseURL)
        providerName = provider.title
        baseURL = provider.baseURL
        let savedModel = try container.decodeIfPresent(String.self, forKey: .model) ?? provider.defaultModel
        model = Self.normalizedModel(savedModel, for: provider)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? Self.defaults.temperature
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? Self.defaults.maxTokens
        shortcutMode = try container.decodeIfPresent(ShortcutMode.self, forKey: .shortcutMode) ?? Self.defaults.shortcutMode
        isPanelPinned = try container.decodeIfPresent(Bool.self, forKey: .isPanelPinned) ?? Self.defaults.isPanelPinned
        historyFilePath = try container.decodeIfPresent(String.self, forKey: .historyFilePath) ?? Self.defaults.historyFilePath
    }

    static func normalizedModel(_ model: String, for provider: LLMProvider) -> String {
        switch provider {
        case .openRouter:
            return normalizedOpenRouterModel(model)
        case .openAI:
            return normalizedOpenAIModel(model)
        }
    }

    static func modelForProviderSwitch(_ model: String, to provider: LLMProvider) -> String {
        switch provider {
        case .openRouter:
            return normalizedOpenRouterModel(model)
        case .openAI:
            let openAIModel = normalizedOpenAIModel(model)
            return openAIModel.contains("/") ? provider.defaultModel : openAIModel
        }
    }

    static func normalizedOpenRouterModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return openRouterDefaultModel }

        if trimmed.contains("/") {
            return trimmed
        }

        if trimmed.hasPrefix("gpt-") || trimmed.hasPrefix("o1") || trimmed.hasPrefix("o3") || trimmed.hasPrefix("o4") {
            return "openai/\(trimmed)"
        }

        return trimmed
    }

    static func normalizedOpenAIModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return openAIDefaultModel }

        if trimmed.hasPrefix("openai/") {
            return String(trimmed.dropFirst("openai/".count))
        }

        return trimmed
    }

    private static func inferredProvider(providerName: String?, baseURL: String?) -> LLMProvider {
        let name = providerName?.lowercased() ?? ""
        let url = baseURL?.lowercased() ?? ""

        if url.contains("api.openai.com") || (name.contains("openai") && !name.contains("openrouter")) {
            return .openAI
        }

        return .openRouter
    }
}

enum LLMProvider: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case openRouter
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openRouter:
            return "OpenRouter"
        case .openAI:
            return "OpenAI"
        }
    }

    var baseURL: String {
        switch self {
        case .openRouter:
            return ModelSettings.openRouterBaseURL
        case .openAI:
            return ModelSettings.openAIBaseURL
        }
    }

    var defaultModel: String {
        switch self {
        case .openRouter:
            return ModelSettings.openRouterDefaultModel
        case .openAI:
            return ModelSettings.openAIDefaultModel
        }
    }

    var apiKeyHint: String {
        switch self {
        case .openRouter:
            return "OpenRouter API Key"
        case .openAI:
            return "OpenAI API Key"
        }
    }
}

struct LLMModel: Identifiable, Decodable, Equatable, Sendable {
    var id: String
    var name: String
    var contextLength: Int?
    var supportedParameters: [String]?
    var architecture: LLMModelArchitecture?

    init(
        id: String,
        name: String? = nil,
        contextLength: Int? = nil,
        supportedParameters: [String]? = nil,
        architecture: LLMModelArchitecture? = nil
    ) {
        self.id = id
        self.name = name ?? id
        self.contextLength = contextLength
        self.supportedParameters = supportedParameters
        self.architecture = architecture
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contextLength = "context_length"
        case supportedParameters = "supported_parameters"
        case architecture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
        supportedParameters = try container.decodeIfPresent([String].self, forKey: .supportedParameters)
        architecture = try container.decodeIfPresent(LLMModelArchitecture.self, forKey: .architecture)
    }

    var displayName: String {
        name.isEmpty ? id : name
    }

    var pickerTitle: String {
        displayName == id ? id : "\(displayName) - \(id)"
    }

    var searchText: String {
        "\(displayName) \(id)".lowercased()
    }

    var supportsTextOutput: Bool {
        guard let outputModalities = architecture?.outputModalities, !outputModalities.isEmpty else {
            return true
        }
        return outputModalities.contains("text")
    }
}

struct LLMModelArchitecture: Decodable, Equatable, Sendable {
    var outputModalities: [String]?

    enum CodingKeys: String, CodingKey {
        case outputModalities = "output_modalities"
    }
}

enum ShortcutMode: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case doubleCommandC
    case commandShiftE
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleCommandC:
            return "Command+C twice"
        case .commandShiftE:
            return "Command+Shift+E"
        case .off:
            return "Off"
        }
    }

    var detail: String {
        switch self {
        case .doubleCommandC:
            return "Select the full context, then press Command-C twice to bring it into the app."
        case .commandShiftE:
            return "Select the full context, then press Command-Shift-E to bring it into the app."
        case .off:
            return "Keyboard listening is disabled. You can still use the menu bar and Services actions."
        }
    }
}

enum ExplainerError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case noModels
    case noText
    case noModelOutput
    case invalidModelOutput(String)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an API key in Settings first."
        case .invalidBaseURL:
            return "The API base URL is not valid."
        case .noModels:
            return "No models were found."
        case .noText:
            return "No selected text was found."
        case .noModelOutput:
            return "The model returned an empty response."
        case .invalidModelOutput(let output):
            return "The model response could not be read as an explanation: \(output)"
        case .requestFailed(let status, let body):
            return "The API request failed with HTTP \(status): \(body)"
        }
    }
}
