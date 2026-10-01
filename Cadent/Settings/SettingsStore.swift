import Foundation
import Observation

struct StoredSettings: Codable, Equatable {
    var intervalMinutes: Int = 30
    var snoozeMinutes: Int = 5
    var autoDismissSeconds: Int = 60
    var paused: Bool = false
    var nextBreakAt: Date?
}

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    private let storageKey = "cadent.settings.v1"
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private(set) var settings: StoredSettings

    var intervalMinutes: Int {
        get { settings.intervalMinutes }
        set { settings.intervalMinutes = min(180, max(1, newValue)); save() }
    }

    var snoozeMinutes: Int {
        get { settings.snoozeMinutes }
        set { settings.snoozeMinutes = min(60, max(1, newValue)); save() }
    }

    var autoDismissSeconds: Int {
        get { settings.autoDismissSeconds }
        set { settings.autoDismissSeconds = min(300, max(15, newValue)); save() }
    }

    var paused: Bool {
        get { settings.paused }
        set { settings.paused = newValue; save() }
    }

    var nextBreakAt: Date? {
        get { settings.nextBreakAt }
        set { settings.nextBreakAt = newValue; save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? decoder.decode(StoredSettings.self, from: data) {
            settings = stored
        } else {
            settings = StoredSettings()
        }
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
