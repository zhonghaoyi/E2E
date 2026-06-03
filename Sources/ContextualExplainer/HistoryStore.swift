import Foundation

struct HistoryStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load(from historyFilePath: String = "") -> [WordExplanation] {
        guard let url = historyURL(for: historyFilePath), let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([WordExplanation].self, from: data)) ?? []
    }

    func save(_ history: [WordExplanation], to historyFilePath: String = "") {
        guard let url = historyURL(for: historyFilePath) else { return }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to save explanation history: \(error.localizedDescription)")
        }
    }

    func displayPath(for historyFilePath: String = "") -> String {
        historyURL(for: historyFilePath)?.path ?? ""
    }

    func defaultDisplayPath() -> String {
        defaultHistoryURL()?.path ?? ""
    }

    private func historyURL(for historyFilePath: String) -> URL? {
        let trimmedPath = historyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return defaultHistoryURL()
        }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        var url = URL(fileURLWithPath: expandedPath)
        if trimmedPath.hasSuffix("/") || ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) {
            url.appendPathComponent("history.json")
        }
        return url
    }

    private func defaultHistoryURL() -> URL? {
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportURL
            .appendingPathComponent("ContextualExplainer", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
