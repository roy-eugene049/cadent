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

    func url(for voice: VoiceClip) -> URL {
        recordingsDirectory.appendingPathComponent(voice.fileName)
    }

    func fileExists(_ voice: VoiceClip) -> Bool {
        FileManager.default.fileExists(atPath: url(for: voice).path)
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

    /// Moves the draft onto the voice's file name and returns the clip duration.
    func adoptDraft(for voice: VoiceClip) throws -> TimeInterval {
        let destination = url(for: voice)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: draftURL, to: destination)
        return duration(of: destination)
    }

    func deleteFile(for voice: VoiceClip) {
        let url = url(for: voice)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func duration(of url: URL) -> TimeInterval {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return player.duration
    }

    func importFile(at source: URL, title: String, into settings: SettingsStore) throws -> VoiceClip {
        let voice = settings.addVoice(name: title, duration: 0)
        let destination = url(for: voice)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            settings.removeVoice(id: voice.id)
            throw error
        }
        settings.updateVoiceDuration(id: voice.id, duration: duration(of: destination))
        let reminder = settings.addReminder(title: title)
        settings.setVoiceAttached(voice.id, to: reminder.id, attached: true)
        return voice
    }
}
