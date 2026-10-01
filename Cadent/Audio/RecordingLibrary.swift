import AVFoundation
import Foundation

@MainActor
final class RecordingLibrary {
    static let maxDuration: TimeInterval = 30

    let recordingsDirectory: URL
    let draftURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadent/recordings", isDirectory: true)
        recordingsDirectory = base
        draftURL = base.appendingPathComponent("draft.m4a")
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func url(for reminder: Reminder) -> URL {
        recordingsDirectory.appendingPathComponent(reminder.fileName)
    }

    func fileExists(_ reminder: Reminder) -> Bool {
        FileManager.default.fileExists(atPath: url(for: reminder).path)
    }

    func prepareDraft() -> URL {
        if FileManager.default.fileExists(atPath: draftURL.path) {
            try? FileManager.default.removeItem(at: draftURL)
        }
        return draftURL
    }

    func discardDraft() {
        if FileManager.default.fileExists(atPath: draftURL.path) {
            try? FileManager.default.removeItem(at: draftURL)
        }
    }

    /// Moves the draft onto the reminder's file name and returns the clip duration.
    func adoptDraft(for reminder: Reminder) throws -> TimeInterval {
        let destination = url(for: reminder)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: draftURL, to: destination)
        return duration(of: destination)
    }

    func deleteFile(for reminder: Reminder) {
        let url = url(for: reminder)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func duration(of url: URL) -> TimeInterval {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return player.duration
    }

    func importFile(at source: URL, title: String, into settings: SettingsStore) throws -> Reminder {
        let reminder = settings.addReminder(title: title, duration: 0)
        let destination = url(for: reminder)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            settings.remove(id: reminder.id)
            throw error
        }
        settings.updateDuration(id: reminder.id, duration: duration(of: destination))
        return reminder
    }
}
