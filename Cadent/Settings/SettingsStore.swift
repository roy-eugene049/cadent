import Foundation
import Observation

struct Reminder: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var fileName: String
    var duration: TimeInterval
    var enabled: Bool

    static func make(title: String, duration: TimeInterval) -> Reminder {
        let id = UUID()
        return Reminder(
            id: id,
            title: title,
            fileName: "\(id.uuidString).m4a",
            duration: duration,
            enabled: true
        )
    }
}

struct StoredSettings: Codable, Equatable {
    var intervalMinutes: Int = 30
    var snoozeMinutes: Int = 5
    var autoDismissSeconds: Int = 60
    var paused: Bool = false
    var reminders: [Reminder] = []
    var rotationIndex: Int = 0
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

    var reminders: [Reminder] { settings.reminders }

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

    func addReminder(title: String, duration: TimeInterval) -> Reminder {
        let reminder = Reminder.make(title: title, duration: duration)
        settings.reminders.append(reminder)
        save()
        return reminder
    }

    func updateDuration(id: UUID, duration: TimeInterval) {
        guard let index = settings.reminders.firstIndex(where: { $0.id == id }) else { return }
        settings.reminders[index].duration = duration
        save()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = settings.reminders.firstIndex(where: { $0.id == id }) else { return }
        settings.reminders[index].enabled = enabled
        save()
    }

    func remove(id: UUID) {
        settings.reminders.removeAll { $0.id == id }
        if settings.reminders.isEmpty {
            settings.rotationIndex = 0
        } else {
            settings.rotationIndex %= settings.reminders.count
        }
        save()
    }

    /// Advances the rotation and returns the next enabled reminder that has a file.
    func consumeNextPlayable(fileExists: (Reminder) -> Bool) -> Reminder? {
        let count = settings.reminders.count
        guard count > 0 else { return nil }
        let start = positiveModulo(settings.rotationIndex, count)
        for offset in 0..<count {
            let index = (start + offset) % count
            let reminder = settings.reminders[index]
            if reminder.enabled && fileExists(reminder) {
                settings.rotationIndex = (index + 1) % count
                save()
                return reminder
            }
        }
        return nil
    }

    func hasPlayableReminder(fileExists: (Reminder) -> Bool) -> Bool {
        settings.reminders.contains { $0.enabled && fileExists($0) }
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
