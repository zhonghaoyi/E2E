import SwiftUI

struct ExplainerPanelView: View {
    @ObservedObject var appState: AppState
    var openSettings: () -> Void = {}
    @State private var selectedTab: PanelTab = .explain
    @State private var selectedHistoryItem: WordExplanation?
    @State private var selectedHistoryRange: HistoryRange = .threeMonths
    @State private var selectedOccurrenceFilter: HistoryOccurrenceFilter = .all
    @State private var expandedHistoryKeys: Set<HistorySampleKey> = []
    @State private var selectedExplanationText: String?
    @State private var selectedStoryWordLimit: StoryWordLimit = .ten
    @State private var generatedStoryTerms: [StoryVocabularyTerm] = []
    @State private var pendingHistoryDeletion: HistoryDeletionRequest?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(PanelTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                        selectedExplanationText = nil
                        if tab == .explain {
                            selectedHistoryItem = nil
                        }
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(selectedTab == tab ? .accentColor : nil)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            switch selectedTab {
            case .explain:
                explanationTab
            case .history:
                historyTab
            case .story:
                storyTab
            }
        }
        .frame(minWidth: 540, idealWidth: 620, minHeight: 680, idealHeight: 820)
        .alert(item: $pendingHistoryDeletion) { request in
            Alert(
                title: Text(request.title),
                message: Text(request.message),
                primaryButton: .destructive(Text("Delete")) {
                    confirmHistoryDeletion(request)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var explanationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Spacer()

                    Button {
                        appState.togglePanelPin()
                    } label: {
                        Label(appState.settings.isPanelPinned ? "Pinned" : "Pin", systemImage: appState.settings.isPanelPinned ? "pin.fill" : "pin")
                    }
                    .help(appState.settings.isPanelPinned ? "Unpin window" : "Pin window on top")
                    .tint(appState.settings.isPanelPinned ? .accentColor : nil)

                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open settings")

                    Button {
                        selectedExplanationText = nil
                        appState.explainManualInput()
                    } label: {
                        Label("Explain", systemImage: "sparkle.magnifyingglass")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(appState.isLoading)
                }

                ShortcutStatusView(appState: appState)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Word Or Phrase")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("charge", text: $appState.selectionText)
                        .font(.system(size: 17))
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Context")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            translateCurrentContext()
                        } label: {
                            Label(appState.isContextTranslationLoading ? "Translating" : "中文翻译", systemImage: "character.book.closed")
                        }
                        .controlSize(.small)
                        .disabled(
                            appState.contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || appState.isContextTranslationLoading
                        )
                    }
                    SelectableContextTextView(text: $appState.contextText) { selectedText in
                        selectedExplanationText = nil
                        appState.useSelectedContextPhrase(selectedText)
                    }
                    .frame(height: 150)
                    .onChange(of: appState.contextText) { _, _ in
                        appState.clearContextTranslation()
                    }

                    if appState.isContextTranslationLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.contextTranslationStatusMessage ?? "Translating context...")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    } else if let contextTranslationErrorMessage = appState.contextTranslationErrorMessage {
                        Label(contextTranslationErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !appState.contextChineseTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContextTranslationCard(translation: appState.contextChineseTranslation)
                    }
                }

                if appState.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.statusMessage ?? "Working...")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = appState.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let statusMessage = appState.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                if let explanation = appState.currentExplanation {
                    ExplanationCard(
                        explanation: explanation,
                        occurrenceCount: occurrenceCount(for: explanation),
                        selectedText: selectedExplanationText,
                        onTextSelection: { selectedExplanationText = $0 },
                        onNewContext: { selectedText in
                            appState.useExplanationSelectionAsNewContext(selectedText)
                            selectedExplanationText = nil
                        }
                    )
                } else {
                    EmptyResultView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private var historyTab: some View {
        Group {
            if let selectedHistoryItem {
                HistoryDetailView(
                    item: selectedHistoryItem,
                    occurrenceCount: occurrenceCount(for: selectedHistoryItem),
                    selectedText: selectedExplanationText,
                    onBack: {
                        self.selectedHistoryItem = nil
                        selectedExplanationText = nil
                    },
                    onUseAgain: {
                        appState.useHistoryItem(selectedHistoryItem)
                        self.selectedHistoryItem = nil
                        selectedExplanationText = nil
                        selectedTab = .explain
                    },
                    onTextSelection: { selectedExplanationText = $0 },
                    onNewContext: { selectedText in
                        appState.useExplanationSelectionAsNewContext(selectedText)
                        self.selectedHistoryItem = nil
                        selectedExplanationText = nil
                        selectedTab = .explain
                    }
                )
            } else {
                historyList
            }
        }
    }

    private var filteredHistory: [WordExplanation] {
        selectedHistoryRange.filteredItems(from: appState.history)
    }

    private var historyGroups: [HistoryGroup] {
        Dictionary(grouping: filteredHistory, by: HistorySampleKey.init)
            .map { key, items in
                HistoryGroup(
                    key: key,
                    items: items.sorted { $0.createdAt > $1.createdAt }
                )
            }
            .filter { group in
                selectedOccurrenceFilter.includes(count: occurrenceCounts[group.key] ?? group.items.count)
            }
            .sorted { lhs, rhs in
                if lhs.latestCreatedAt == rhs.latestCreatedAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.latestCreatedAt > rhs.latestCreatedAt
            }
    }

    private var occurrenceCounts: [HistorySampleKey: Int] {
        Dictionary(grouping: appState.history, by: HistorySampleKey.init).mapValues(\.count)
    }

    private func occurrenceCount(for item: WordExplanation) -> Int {
        occurrenceCounts[HistorySampleKey(item)] ?? 0
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    pendingHistoryDeletion = .clearAll(count: appState.history.count)
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(appState.history.isEmpty)
            }

            Picker("Range", selection: $selectedHistoryRange) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Picker("Occurrences", selection: $selectedOccurrenceFilter) {
                ForEach(HistoryOccurrenceFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if appState.history.isEmpty {
                EmptyResultView()
            } else if historyGroups.isEmpty {
                EmptyResultView(message: "No history matching this filter.")
            } else {
                List(historyGroups) { group in
                    HistoryGroupRow(
                        group: group,
                        occurrenceCount: occurrenceCounts[group.key] ?? group.items.count,
                        isExpanded: expandedHistoryKeys.contains(group.key),
                        onToggle: {
                            if expandedHistoryKeys.contains(group.key) {
                                expandedHistoryKeys.remove(group.key)
                            } else {
                                expandedHistoryKeys.insert(group.key)
                            }
                        },
                        onSelectItem: { item in
                            selectedHistoryItem = item
                        },
                        onDeleteGroup: {
                            pendingHistoryDeletion = .group(group)
                        }
                    )
                }
            }
        }
        .padding(18)
    }

    private func confirmHistoryDeletion(_ request: HistoryDeletionRequest) {
        switch request.action {
        case .clearAll:
            selectedHistoryItem = nil
            expandedHistoryKeys.removeAll()
            appState.clearHistory()
        case .group(let key, let ids):
            selectedHistoryItem = nil
            expandedHistoryKeys.remove(key)
            appState.deleteHistoryItems(ids: ids)
        }
    }

    private var storyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Story")
                        .font(.headline)
                    Spacer()
                    Button {
                        translateCurrentStory()
                    } label: {
                        Label(appState.isStoryTranslationLoading ? "Translating" : "中文翻译", systemImage: "character.book.closed")
                    }
                    .disabled(
                        appState.generatedStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || appState.isStoryLoading
                            || appState.isStoryTranslationLoading
                    )

                    Button {
                        generateStoryFromHistory()
                    } label: {
                        Label(appState.isStoryLoading ? "Generating" : "Generate", systemImage: "wand.and.sparkles")
                    }
                    .disabled(appState.isStoryLoading || historyGroups.isEmpty)
                }

                Picker("Range", selection: $selectedHistoryRange) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Occurrences", selection: $selectedOccurrenceFilter) {
                    ForEach(HistoryOccurrenceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Words", selection: $selectedStoryWordLimit) {
                    ForEach(StoryWordLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                .pickerStyle(.segmented)

                Text("\(min(selectedStoryWordLimit.count, historyGroups.count)) of \(historyGroups.count) matching history words will be randomly selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.isStoryLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.storyStatusMessage ?? "Generating story...")
                            .foregroundStyle(.secondary)
                    }
                } else if let storyErrorMessage = appState.storyErrorMessage {
                    Label(storyErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else if appState.isStoryTranslationLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.storyTranslationStatusMessage ?? "Translating story...")
                            .foregroundStyle(.secondary)
                    }
                } else if let storyTranslationErrorMessage = appState.storyTranslationErrorMessage {
                    Label(storyTranslationErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let storyStatusMessage = appState.storyStatusMessage {
                    Label(storyStatusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                if appState.generatedStory.isEmpty {
                    EmptyResultView(message: historyGroups.isEmpty ? "No history matching this filter." : "No story yet.")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.book.closed")
                                .foregroundStyle(.secondary)
                            Text("\(generatedStoryTerms.count) words")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        InteractiveStoryTextView(
                            text: appState.generatedStory,
                            terms: generatedStoryTerms,
                            onTermClick: openStoryTerm
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor))
                    }

                    if !appState.storyChineseTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "character.book.closed")
                                    .foregroundStyle(.secondary)
                                Text("中文翻译")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            Text(appState.storyChineseTranslation)
                                .font(.system(size: 17))
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private func generateStoryFromHistory() {
        let groups = Array(historyGroups.shuffled().prefix(selectedStoryWordLimit.count))
        let terms = groups.map { group in
            StoryVocabularyTerm(
                sample: group.title,
                partOfSpeech: group.partOfSpeech,
                meaning: group.latestMeaning
            )
        }
        generatedStoryTerms = terms

        Task {
            await appState.generateStory(from: terms)
        }
    }

    private func translateCurrentStory() {
        Task {
            await appState.translateStoryToChinese()
        }
    }

    private func translateCurrentContext() {
        Task {
            await appState.translateContextToChinese()
        }
    }

    private func openStoryTerm(_ term: StoryVocabularyTerm) {
        guard let item = appState.history.first(where: { HistorySampleKey($0).id == term.id }) else {
            return
        }

        selectedHistoryItem = item
        expandedHistoryKeys.insert(HistorySampleKey(item))
        selectedExplanationText = nil
        selectedTab = .history
    }
}

private struct ContextTranslationCard: View {
    var translation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed")
                    .foregroundStyle(.secondary)
                Text("Context 中文翻译")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(translation)
                .font(.system(size: 17))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        }
    }
}

private struct HistoryDetailView: View {
    var item: WordExplanation
    var occurrenceCount: Int
    var selectedText: String?
    var onBack: () -> Void
    var onUseAgain: () -> Void
    var onTextSelection: (String?) -> Void
    var onNewContext: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Button {
                        onBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }

                    Spacer()

                    Button {
                        onUseAgain()
                    } label: {
                        Label("Use Again", systemImage: "arrow.uturn.forward")
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.selection)
                        .font(.system(size: 24, weight: .semibold))
                    HStack(spacing: 10) {
                        Text(item.partOfSpeechLabel)
                            .foregroundStyle(.secondary)
                        CountBadge(count: occurrenceCount)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
                .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Context")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(item.context)
                        .font(.system(size: 17))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                }
                .textSelection(.enabled)

                ExplanationCard(
                    explanation: item,
                    occurrenceCount: occurrenceCount,
                    selectedText: selectedText,
                    onTextSelection: onTextSelection,
                    onNewContext: onNewContext
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
}

private enum PanelTab: String, CaseIterable, Identifiable {
    case explain
    case history
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain:
            return "Explain"
        case .history:
            return "History"
        case .story:
            return "Story"
        }
    }

    var systemImage: String {
        switch self {
        case .explain:
            return "text.magnifyingglass"
        case .history:
            return "clock"
        case .story:
            return "text.book.closed"
        }
    }
}

private enum StoryWordLimit: Int, CaseIterable, Identifiable {
    case ten = 10
    case thirty = 30
    case fifty = 50
    case seventy = 70
    case oneHundred = 100

    var id: Int { rawValue }
    var count: Int { rawValue }
    var title: String { "\(rawValue)" }
}

private enum HistoryRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case threeMonths

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            return "1 Day"
        case .week:
            return "1 Week"
        case .month:
            return "1 Month"
        case .threeMonths:
            return "3 Months"
        }
    }

    func filteredItems(from history: [WordExplanation], now: Date = Date()) -> [WordExplanation] {
        guard let cutoffDate = cutoffDate(from: now) else {
            return history
        }
        return history.filter { $0.createdAt >= cutoffDate }
    }

    private func cutoffDate(from date: Date) -> Date? {
        switch self {
        case .day:
            return Calendar.current.date(byAdding: .day, value: -1, to: date)
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: date)
        case .month:
            return Calendar.current.date(byAdding: .month, value: -1, to: date)
        case .threeMonths:
            return Calendar.current.date(byAdding: .month, value: -3, to: date)
        }
    }
}

private enum HistoryOccurrenceFilter: String, CaseIterable, Identifiable {
    case all
    case once
    case moreThanThree
    case moreThanSeven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .once:
            return "1 Time"
        case .moreThanThree:
            return ">3"
        case .moreThanSeven:
            return ">7"
        }
    }

    func includes(count: Int) -> Bool {
        switch self {
        case .all:
            return true
        case .once:
            return count == 1
        case .moreThanThree:
            return count > 3
        case .moreThanSeven:
            return count > 7
        }
    }
}

private struct HistoryGroup: Identifiable {
    var key: HistorySampleKey
    var items: [WordExplanation]

    var id: String { key.id }
    var title: String { items.first?.selection ?? key.sample }
    var partOfSpeech: String { key.partOfSpeech }
    var latestMeaning: String { items.first?.meaningHere ?? "" }
    var latestCreatedAt: Date { items.first?.createdAt ?? .distantPast }
}

private struct HistorySampleKey: Hashable, Identifiable {
    var sample: String
    var partOfSpeech: String
    var id: String { "\(sample)||\(partOfSpeech)" }

    init(_ explanation: WordExplanation) {
        sample = explanation.selection.trimmingCharacters(in: .whitespacesAndNewlines)
        partOfSpeech = explanation.partOfSpeechLabel
    }
}

private struct HistoryDeletionRequest: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var action: HistoryDeletionAction

    static func clearAll(count: Int) -> HistoryDeletionRequest {
        HistoryDeletionRequest(
            title: "Clear all history?",
            message: "This will delete \(count) history records. This cannot be undone.",
            action: .clearAll
        )
    }

    static func group(_ group: HistoryGroup) -> HistoryDeletionRequest {
        let ids = Set(group.items.map(\.id))
        let recordText = ids.count == 1 ? "record" : "records"
        return HistoryDeletionRequest(
            title: "Delete \(group.title)?",
            message: "This will delete \(ids.count) \(recordText) for \(group.title) (\(group.partOfSpeech)). This cannot be undone.",
            action: .group(key: group.key, ids: ids)
        )
    }
}

private enum HistoryDeletionAction {
    case clearAll
    case group(key: HistorySampleKey, ids: Set<UUID>)
}

private struct HistoryGroupRow: View {
    var group: HistoryGroup
    var occurrenceCount: Int
    var isExpanded: Bool
    var onToggle: () -> Void
    var onSelectItem: (WordExplanation) -> Void
    var onDeleteGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    onToggle()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14, height: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(group.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(group.partOfSpeech)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                CountBadge(count: occurrenceCount)
                            }

                            if !isExpanded {
                                Text(group.latestMeaning)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text(group.latestCreatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    onDeleteGroup()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete this word from history")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.items) { item in
                        Button {
                            onSelectItem(item)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.meaningHere)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .padding(.leading, 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ShortcutStatusView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Label(appState.settings.shortcutMode.title, systemImage: "keyboard")
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 14)

            if appState.hasAccessibilityPermission {
                Label(appState.shortcutStatusTitle, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if appState.shortcutNeedsAccessibility {
                Label(appState.shortcutStatusTitle, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)

                Button {
                    appState.requestAccessibilityPermissionPrompt()
                    appState.openAccessibilitySettings()
                } label: {
                    Label("Allow", systemImage: "lock.shield")
                }
                .controlSize(.small)

                Button {
                    appState.restartApp()
                } label: {
                    Label("Restart", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
            } else if appState.settings.shortcutMode == .doubleCommandC {
                Label(appState.shortcutStatusTitle, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                Label(appState.shortcutStatusTitle, systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }

            if appState.settings.shortcutMode == .commandShiftE {
                Button {
                    appState.useDoubleCopyShortcut()
                } label: {
                    Label("Use C+C", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }

            Spacer()

            Button {
                appState.refreshAccessibilityPermission()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ExplanationCard: View {
    var explanation: WordExplanation
    var occurrenceCount: Int = 0
    var selectedText: String?
    var onTextSelection: (String?) -> Void = { _ in }
    var onNewContext: (String) -> Void = { _ in }

    private var selectedSnippet: String? {
        let trimmedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedText.isEmpty ? nil : trimmedText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(explanation.selection)
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Text(explanation.partOfSpeechLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    CountBadge(count: occurrenceCount)
                }
            }

            if let selectedSnippet {
                HStack(spacing: 8) {
                    Image(systemName: "text.cursor")
                        .foregroundStyle(.secondary)
                    Text(selectedSnippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        onNewContext(selectedSnippet)
                    } label: {
                        Label("New Context", systemImage: "text.badge.plus")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            ExplanationRow(title: "Meaning", value: explanation.meaningHere, systemImage: "book", onSelection: onTextSelection)
            ExplanationRow(title: "Simple Replacement", value: explanation.simpleReplacement, systemImage: "arrow.left.arrow.right", onSelection: onTextSelection)
            ExplanationRow(title: "Easy Example", value: explanation.easyExample, systemImage: "quote.bubble", onSelection: onTextSelection)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        }
    }
}

private struct CountBadge: View {
    var count: Int

    var body: some View {
        Text("\(max(count, 0)) \(count == 1 ? "time" : "times")")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private extension WordExplanation {
    var partOfSpeechLabel: String {
        PartOfSpeechCategory.normalizedLabel(partOfSpeech)
    }
}

private struct ExplanationRow: View {
    var title: String
    var value: String
    var systemImage: String
    var onSelection: (String?) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                SelectableExplanationTextView(text: value, onSelection: onSelection)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct EmptyResultView: View {
    var message: String = "No explanation yet."

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

#if DEBUG
#Preview {
    ExplainerPanelView(appState: AppState())
}
#endif
