import AppKit
import ApplicationServices
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var settings: ModelSettings
    @Published var apiKey: String
    @Published var selectionText: String = ""
    @Published var contextText: String = ""
    @Published var currentExplanation: WordExplanation?
    @Published var history: [WordExplanation]
    @Published var isLoading = false
    @Published var isLoadingModels = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var modelCatalogError: String?
    @Published var modelCatalog: [LLMModel] = []
    @Published var hasAccessibilityPermission = false
    @Published var contextChineseTranslation: String = ""
    @Published var isContextTranslationLoading = false
    @Published var contextTranslationStatusMessage: String?
    @Published var contextTranslationErrorMessage: String?
    @Published var generatedStory: String = ""
    @Published var isStoryLoading = false
    @Published var storyStatusMessage: String?
    @Published var storyErrorMessage: String?
    @Published var storyChineseTranslation: String = ""
    @Published var isStoryTranslationLoading = false
    @Published var storyTranslationStatusMessage: String?
    @Published var storyTranslationErrorMessage: String?

    private let settingsStore: SettingsStore
    private let keychainStore: KeychainStore
    private let historyStore: HistoryStore
    private let selectionReader: SelectionReader
    private let client: LLMClient
    private var activeHistoryFilePath: String

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shortcutNeedsAccessibility: Bool {
        settings.shortcutMode == .commandShiftE
    }

    var shortcutStatusTitle: String {
        switch settings.shortcutMode {
        case .doubleCommandC:
            return "Double-copy trigger ready"
        case .commandShiftE:
            return hasAccessibilityPermission ? "Accessibility enabled" : "Accessibility needs restart or permission"
        case .off:
            return "Shortcut off"
        }
    }

    var historyFileDisplayPath: String {
        historyStore.displayPath(for: settings.historyFilePath)
    }

    var defaultHistoryFileDisplayPath: String {
        historyStore.defaultDisplayPath()
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        keychainStore: KeychainStore = KeychainStore(),
        historyStore: HistoryStore = HistoryStore(),
        selectionReader: SelectionReader? = nil,
        client: LLMClient = LLMClient()
    ) {
        self.settingsStore = settingsStore
        self.keychainStore = keychainStore
        self.historyStore = historyStore
        self.selectionReader = selectionReader ?? SelectionReader()
        self.client = client
        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.apiKey = keychainStore.loadAPIKey(for: loadedSettings.provider)
        self.history = Self.deduplicatedHistoryByContext(historyStore.load(from: loadedSettings.historyFilePath))
        self.activeHistoryFilePath = loadedSettings.historyFilePath
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        historyStore.save(history, to: loadedSettings.historyFilePath)
    }

    func saveSettings() {
        do {
            settings.providerName = settings.provider.title
            settings.baseURL = settings.provider.baseURL
            settings.model = ModelSettings.normalizedModel(settings.model, for: settings.provider)
            settings.historyFilePath = settings.historyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if settings.historyFilePath != activeHistoryFilePath {
                history = mergedHistory(current: history, stored: historyStore.load(from: settings.historyFilePath))
            }
            history = Array(Self.deduplicatedHistoryByContext(history).prefix(100))
            settingsStore.save(settings)
            historyStore.save(history, to: settings.historyFilePath)
            activeHistoryFilePath = settings.historyFilePath
            try keychainStore.saveAPIKey(apiKey, for: settings.provider)
            refreshAccessibilityPermission()
            statusMessage = "Settings saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pasteAPIKeyFromClipboard() {
        guard
            let pastedKey = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !pastedKey.isEmpty
        else {
            errorMessage = "Clipboard does not contain text."
            statusMessage = nil
            return
        }

        apiKey = pastedKey
        statusMessage = "API key pasted."
        errorMessage = nil
        refreshModels()
    }

    func selectProvider(_ provider: LLMProvider) {
        guard provider != settings.provider else { return }

        do {
            try keychainStore.saveAPIKey(apiKey, for: settings.provider)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }

        settings.provider = provider
        settings.providerName = provider.title
        settings.baseURL = provider.baseURL
        settings.model = ModelSettings.modelForProviderSwitch(settings.model, to: provider)
        apiKey = keychainStore.loadAPIKey(for: provider)
        modelCatalog = []
        modelCatalogError = nil
        statusMessage = "\(provider.title) selected."
        refreshModels()
    }

    func chooseHistoryFilePath() {
        let panel = NSOpenPanel()
        panel.title = "Choose History Location"
        panel.message = "Choose a history.json file, or choose a folder where the app can save history.json."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: historyFileDisplayPath).deletingLastPathComponent()

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.settings.historyFilePath = url.path
                self?.statusMessage = "History file selected. Click Save to use it."
                self?.errorMessage = nil
            }
        }
    }

    func useDefaultHistoryFilePath() {
        settings.historyFilePath = ""
        statusMessage = "Default history file selected. Click Save to use it."
        errorMessage = nil
    }

    func revealHistoryFilePath() {
        let url = URL(fileURLWithPath: historyFileDisplayPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        NSWorkspace.shared.open(url.deletingLastPathComponent())
    }

    func loadModelsIfNeeded() {
        guard modelCatalog.isEmpty, !isLoadingModels else { return }
        refreshModels()
    }

    func refreshModels() {
        Task {
            await loadModels()
        }
    }

    func filteredModels(matching query: String) -> [LLMModel] {
        let currentModel = ModelSettings.normalizedModel(settings.model, for: settings.provider)
        var models = modelCatalog

        if !currentModel.isEmpty, !models.contains(where: { $0.id == currentModel }) {
            models.insert(LLMModel(id: currentModel, name: currentModel), at: 0)
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedQuery.isEmpty {
            return Array(models.prefix(180))
        }

        let filtered = models.filter { $0.searchText.contains(trimmedQuery) }
        return Array(filtered.prefix(180))
    }

    func modelStatusText(matching query: String) -> String {
        if isLoadingModels {
            return "Loading models..."
        }

        if let modelCatalogError {
            return modelCatalogError
        }

        let visibleCount = filteredModels(matching: query).count
        if modelCatalog.isEmpty {
            return "Click Refresh to load \(settings.provider.title) models."
        }

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(modelCatalog.count) \(settings.provider.title) models loaded."
        }

        return "\(visibleCount) matching models."
    }

    private func loadModels() async {
        isLoadingModels = true
        modelCatalogError = nil

        guard hasAPIKey else {
            modelCatalogError = "Paste \(settings.provider.title) API key, then Refresh."
            isLoadingModels = false
            return
        }

        do {
            let models = try await client.fetchModels(settings: settings, apiKey: apiKey)
            modelCatalog = models
            let normalizedModel = ModelSettings.normalizedModel(settings.model, for: settings.provider)
            if settings.model != normalizedModel {
                settings.model = normalizedModel
            }
        } catch {
            modelCatalogError = error.localizedDescription
        }

        isLoadingModels = false
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestAccessibilityPermissionPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    func useDoubleCopyShortcut() {
        var updatedSettings = settings
        updatedSettings.shortcutMode = .doubleCommandC
        settings = updatedSettings
        settingsStore.save(updatedSettings)
        statusMessage = "Shortcut set to Command+C twice."
        errorMessage = nil
    }

    func togglePanelPin() {
        var updatedSettings = settings
        updatedSettings.isPanelPinned.toggle()
        settings = updatedSettings
        settingsStore.save(updatedSettings)
        statusMessage = updatedSettings.isPanelPinned ? "Pinned." : "Unpinned."
        errorMessage = nil
    }

    func restartApp() {
        guard let appURL = Bundle.main.bundleURL as URL? else { return }
        NSWorkspace.shared.open(appURL)
        NSApp.terminate(nil)
    }

    func explainManualInput() {
        Task {
            await explain(selection: selectionText, context: contextText.isEmpty ? selectionText : contextText)
        }
    }

    func captureContext(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            errorMessage = ExplainerError.noText.localizedDescription
            statusMessage = nil
            return
        }

        contextText = trimmedText
        selectionText = ""
        currentExplanation = nil
        clearContextTranslation()
        isLoading = false
        errorMessage = nil
        statusMessage = "Context captured. Choose a phrase in the context."
    }

    func useSelectedContextPhrase(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        selectionText = trimmedText
        currentExplanation = nil
        errorMessage = nil
        statusMessage = "Phrase ready."
    }

    func useExplanationSelectionAsNewContext(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        contextText = trimmedText
        selectionText = ""
        currentExplanation = nil
        clearContextTranslation()
        isLoading = false
        errorMessage = nil
        statusMessage = "New context ready. Choose a phrase in the context."
    }

    func explainClipboard() {
        guard let payload = selectionReader.readClipboard() else {
            errorMessage = ExplainerError.noText.localizedDescription
            return
        }
        captureContext(payload.context)
    }

    func explainSystemSelection() {
        Task {
            do {
                let payload = try await selectionReader.readSelection()
                captureContext(payload.selection)
            } catch {
                errorMessage = "Select context, then allow Accessibility access or use Services: \(error.localizedDescription)"
            }
        }
    }

    func bestSelectionAfterCopy(preferredSelection: String?) async -> SelectionPayload? {
        await selectionReader.readBestSelectionAfterCopy(preferredSelection: preferredSelection)
    }

    func testConnection() {
        saveSettings()
        Task {
            isLoading = true
            statusMessage = "Testing connection..."
            errorMessage = nil
            do {
                try await client.test(settings: settings, apiKey: apiKey)
                statusMessage = "Connection works."
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isLoading = false
        }
    }

    func clearHistory() {
        history.removeAll()
        generatedStory = ""
        storyStatusMessage = nil
        storyErrorMessage = nil
        storyChineseTranslation = ""
        storyTranslationStatusMessage = nil
        storyTranslationErrorMessage = nil
        historyStore.save(history, to: activeHistoryFilePath)
    }

    func deleteHistoryItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        history.removeAll { ids.contains($0.id) }
        historyStore.save(history, to: activeHistoryFilePath)
    }

    func useHistoryItem(_ explanation: WordExplanation) {
        selectionText = explanation.selection
        contextText = explanation.context
        currentExplanation = explanation
        clearContextTranslation()
    }

    func stage(payload: SelectionPayload) {
        selectionText = payload.selection
        contextText = payload.context
        clearContextTranslation()
        if let note = payload.note {
            statusMessage = nil
            errorMessage = note
        }
    }

    func explain(payload: SelectionPayload) async {
        stage(payload: payload)
        await explain(selection: payload.selection, context: payload.context)
    }

    func generateStory(from terms: [StoryVocabularyTerm]) async {
        let cleanedTerms = terms
            .map { term in
                StoryVocabularyTerm(
                    sample: term.sample.trimmingCharacters(in: .whitespacesAndNewlines),
                    partOfSpeech: term.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
                    meaning: term.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.sample.isEmpty }

        guard !cleanedTerms.isEmpty else {
            storyErrorMessage = "No history words match this filter."
            storyStatusMessage = nil
            return
        }

        guard hasAPIKey else {
            storyErrorMessage = ExplainerError.missingAPIKey.localizedDescription
            storyStatusMessage = nil
            return
        }

        isStoryLoading = true
        generatedStory = ""
        storyChineseTranslation = ""
        storyStatusMessage = "Generating story..."
        storyErrorMessage = nil
        storyTranslationStatusMessage = nil
        storyTranslationErrorMessage = nil

        do {
            generatedStory = try await client.generateStory(
                terms: cleanedTerms,
                settings: settings,
                apiKey: apiKey
            )
            storyStatusMessage = nil
        } catch {
            storyErrorMessage = error.localizedDescription
            storyStatusMessage = nil
        }

        isStoryLoading = false
    }

    func clearContextTranslation() {
        contextChineseTranslation = ""
        contextTranslationStatusMessage = nil
        contextTranslationErrorMessage = nil
    }

    func translateContextToChinese() async {
        let context = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else {
            contextTranslationErrorMessage = "Add context first."
            contextTranslationStatusMessage = nil
            return
        }

        guard hasAPIKey else {
            contextTranslationErrorMessage = ExplainerError.missingAPIKey.localizedDescription
            contextTranslationStatusMessage = nil
            return
        }

        isContextTranslationLoading = true
        contextChineseTranslation = ""
        contextTranslationStatusMessage = "Translating context..."
        contextTranslationErrorMessage = nil

        do {
            let translatedContext = try await client.translateContextToChinese(
                context,
                settings: settings,
                apiKey: apiKey
            )
            guard Self.normalizedHistoryText(contextText) == Self.normalizedHistoryText(context) else {
                contextTranslationStatusMessage = nil
                isContextTranslationLoading = false
                return
            }
            contextChineseTranslation = translatedContext
            contextTranslationStatusMessage = nil
        } catch {
            contextTranslationErrorMessage = error.localizedDescription
            contextTranslationStatusMessage = nil
        }

        isContextTranslationLoading = false
    }

    func translateStoryToChinese() async {
        let story = generatedStory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !story.isEmpty else {
            storyTranslationErrorMessage = "Generate a story first."
            storyTranslationStatusMessage = nil
            return
        }

        guard hasAPIKey else {
            storyTranslationErrorMessage = ExplainerError.missingAPIKey.localizedDescription
            storyTranslationStatusMessage = nil
            return
        }

        isStoryTranslationLoading = true
        storyChineseTranslation = ""
        storyTranslationStatusMessage = "Translating story..."
        storyTranslationErrorMessage = nil

        do {
            storyChineseTranslation = try await client.translateStoryToChinese(
                story,
                settings: settings,
                apiKey: apiKey
            )
            storyTranslationStatusMessage = nil
        } catch {
            storyTranslationErrorMessage = error.localizedDescription
            storyTranslationStatusMessage = nil
        }

        isStoryTranslationLoading = false
    }

    private func explain(selection: String, context: String) async {
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else {
            errorMessage = ExplainerError.noText.localizedDescription
            return
        }

        isLoading = true
        statusMessage = "Explaining..."
        errorMessage = nil

        do {
            let explanation = try await client.explain(
                selection: trimmedSelection,
                context: trimmedContext.isEmpty ? trimmedSelection : trimmedContext,
                settings: settings,
                apiKey: apiKey
            )
            let storedExplanation = upsertHistory(explanation)
            currentExplanation = storedExplanation
            selectionText = storedExplanation.selection
            historyStore.save(history, to: activeHistoryFilePath)
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }

        isLoading = false
    }

    private func upsertHistory(_ explanation: WordExplanation) -> WordExplanation {
        var storedExplanation = explanation
        let matchingIndexes = history.indices.filter { index in
            isSameHistoryContext(history[index], storedExplanation)
        }

        if let existingIndex = matchingIndexes.first {
            storedExplanation.id = history[existingIndex].id
            history.removeAll { isSameHistoryContext($0, storedExplanation) }
        }

        history.insert(storedExplanation, at: 0)
        history = Array(history.prefix(100))
        return storedExplanation
    }

    private func isSameHistoryContext(_ lhs: WordExplanation, _ rhs: WordExplanation) -> Bool {
        Self.normalizedHistorySelection(lhs.selection) == Self.normalizedHistorySelection(rhs.selection)
            && Self.normalizedHistoryText(lhs.context) == Self.normalizedHistoryText(rhs.context)
    }

    private static func deduplicatedHistoryByContext(_ items: [WordExplanation]) -> [WordExplanation] {
        var seenKeys = Set<String>()
        var deduplicatedItems: [WordExplanation] = []

        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            let key = historyContextKey(for: item)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            deduplicatedItems.append(item)
        }

        return deduplicatedItems
    }

    private static func historyContextKey(for item: WordExplanation) -> String {
        "\(normalizedHistorySelection(item.selection))\u{1F}\(normalizedHistoryText(item.context))"
    }

    private static func normalizedHistorySelection(_ text: String) -> String {
        normalizedHistoryText(text).lowercased()
    }

    private static func normalizedHistoryText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func mergedHistory(current: [WordExplanation], stored: [WordExplanation]) -> [WordExplanation] {
        var seenIDs = Set<UUID>()
        var merged: [WordExplanation] = []

        for item in current + stored {
            guard !seenIDs.contains(item.id) else { continue }
            seenIDs.insert(item.id)
            merged.append(item)
        }

        return merged.sorted { $0.createdAt > $1.createdAt }
    }
}
