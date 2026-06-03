import Foundation

struct SettingsStore {
    private let defaults: UserDefaults
    private let key = "modelSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ModelSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(ModelSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: ModelSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
