import Foundation
import Observation

struct VoiceClip: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var fileName: String
    var duration: TimeInterval

    static func make(name: String, duration: TimeInterval) -> VoiceClip {
        let id = UUID()
        return VoiceClip(
            id: id,
            name: name,
            fileName: "\(id.uuidString).m4a",
            duration: duration
        )
    }
}

struct Reminder: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var enabled: Bool
    var voiceIDs: [UUID]
    var voiceRotationIndex: Int

    static func make(title: String) -> Reminder {
        Reminder(
            id: UUID(),
            title: title,
            enabled: true,
            voiceIDs: [],
            voiceRotationIndex: 0
        )
    }
}

struct PlayableCue: Equatable {
    var reminder: Reminder
    var voice: VoiceClip
}

struct StoredSettings: Codable, Equatable {
    var intervalMinutes: Int = 30
    var snoozeMinutes: Int = 5
    var autoDismissSeconds: Int = 60
    var paused: Bool = false
    var voices: [VoiceClip] = []
    var reminders: [Reminder] = []
    var rotationIndex: Int = 0
    var nextBreakAt: Date?

    private enum CodingKeys: String, CodingKey {
        case intervalMinutes, snoozeMinutes, autoDismissSeconds, paused
        case voices, reminders, rotationIndex, nextBreakAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 30
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
        autoDismissSeconds = try container.decodeIfPresent(Int.self, forKey: .autoDismissSeconds) ?? 60
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        voices = try container.decodeIfPresent([VoiceClip].self, forKey: .voices) ?? []
        rotationIndex = try container.decodeIfPresent(Int.self, forKey: .rotationIndex) ?? 0
        nextBreakAt = try container.decodeIfPresent(Date.self, forKey: .nextBreakAt)
        let storedReminders = try container.decodeIfPresent([DecodedReminder].self, forKey: .reminders) ?? []
        var reminders: [Reminder] = []
        for stored in storedReminders {
            var reminder = stored.reminder
            if reminder.voiceIDs.isEmpty, let fileName = stored.legacyFileName {
                let voice = VoiceClip(
                    id: UUID(),
                    name: reminder.title,
                    fileName: fileName,
                    duration: stored.legacyDuration ?? 0
                )
                voices.append(voice)
                reminder.voiceIDs = [voice.id]
            }
            reminders.append(reminder)
        }
        self.reminders = reminders
    }
}

private struct DecodedReminder: Decodable {
    var reminder: Reminder
    var legacyFileName: String?
    var legacyDuration: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case id, title, enabled, voiceIDs, voiceRotationIndex, fileName, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reminder = Reminder(
            id: try container.decode(UUID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            voiceIDs: try container.decodeIfPresent([UUID].self, forKey: .voiceIDs) ?? [],
            voiceRotationIndex: try container.decodeIfPresent(Int.self, forKey: .voiceRotationIndex) ?? 0
        )
        legacyFileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        legacyDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }
}

@MainActor
@Observable
final class SettingsStore {
    static let maximumIntervalMinutes = 24 * 60

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
        set {
            settings.intervalMinutes = min(Self.maximumIntervalMinutes, max(1, newValue))
            save()
        }
    }

    var snoozeMinutes: Int {
        get { settings.snoozeMinutes }
        set { settings.snoozeMinutes = min(240, max(1, newValue)); save() }
    }

    var autoDismissSeconds: Int {
        get { settings.autoDismissSeconds }
        set { settings.autoDismissSeconds = min(300, max(15, newValue)); save() }
    }

    var paused: Bool {
        get { settings.paused }
        set { settings.paused = newValue; save() }
    }

    var voices: [VoiceClip] { settings.voices }
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
            save()
        } else {
            settings = StoredSettings()
        }
    }

    func addVoice(name: String, duration: TimeInterval) -> VoiceClip {
        let voice = VoiceClip.make(name: name, duration: duration)
        settings.voices.append(voice)
        save()
        return voice
    }

    func updateVoiceDuration(id: UUID, duration: TimeInterval) {
        guard let index = settings.voices.firstIndex(where: { $0.id == id }) else { return }
        settings.voices[index].duration = duration
        save()
    }

    func removeVoice(id: UUID) {
        settings.voices.removeAll { $0.id == id }
        for index in settings.reminders.indices {
            settings.reminders[index].voiceIDs.removeAll { $0 == id }
        }
        save()
    }

    func addReminder(title: String) -> Reminder {
        let reminder = Reminder.make(title: title)
        settings.reminders.append(reminder)
        save()
        return reminder
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = settings.reminders.firstIndex(where: { $0.id == id }) else { return }
        settings.reminders[index].enabled = enabled
        save()
    }

    func setVoiceAttached(_ voiceID: UUID, to reminderID: UUID, attached: Bool) {
        guard settings.voices.contains(where: { $0.id == voiceID }) else { return }
        guard let index = settings.reminders.firstIndex(where: { $0.id == reminderID }) else { return }
        if attached {
            if !settings.reminders[index].voiceIDs.contains(voiceID) {
                settings.reminders[index].voiceIDs.append(voiceID)
            }
        } else {
            settings.reminders[index].voiceIDs.removeAll { $0 == voiceID }
        }
        save()
    }

    func removeReminder(id: UUID) {
        settings.reminders.removeAll { $0.id == id }
        if settings.reminders.isEmpty {
            settings.rotationIndex = 0
        } else {
            settings.rotationIndex %= settings.reminders.count
        }
        save()
    }

    func voice(id: UUID) -> VoiceClip? {
        settings.voices.first { $0.id == id }
    }

    func voices(attachedTo reminder: Reminder) -> [VoiceClip] {
        reminder.voiceIDs.compactMap { voice(id: $0) }
    }

    /// Advances reminder and voice rotation, then returns the next clip that has a file.
    func consumeNextPlayable(fileExists: (VoiceClip) -> Bool) -> PlayableCue? {
        let count = settings.reminders.count
        guard count > 0 else { return nil }
        let start = positiveModulo(settings.rotationIndex, count)
        for offset in 0..<count {
            let index = (start + offset) % count
            if let cue = nextVoice(forReminderAt: index, fileExists: fileExists) {
                settings.rotationIndex = (index + 1) % count
                save()
                return cue
            }
        }
        return nil
    }

    func hasPlayableReminder(fileExists: (VoiceClip) -> Bool) -> Bool {
        settings.reminders.contains { reminder in
            reminder.enabled && voices(attachedTo: reminder).contains(where: fileExists)
        }
    }

    private func nextVoice(forReminderAt index: Int, fileExists: (VoiceClip) -> Bool) -> PlayableCue? {
        let reminder = settings.reminders[index]
        guard reminder.enabled else { return nil }
        let available = voices(attachedTo: reminder).filter(fileExists)
        guard !available.isEmpty else { return nil }
        let voiceIndex = positiveModulo(reminder.voiceRotationIndex, available.count)
        settings.reminders[index].voiceRotationIndex = voiceIndex + 1
        return PlayableCue(reminder: settings.reminders[index], voice: available[voiceIndex])
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
