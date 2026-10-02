import AVFoundation
import Foundation

@MainActor
@Observable
final class ReminderRecorder {
    private(set) var isRecording = false
    private(set) var recordingStartedAt: Date?
    private(set) var permissionDenied = false
    private(set) var lastError: String?

    var onFinished: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var capTimer: Timer?

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionDenied = false
            return true
        case .denied:
            permissionDenied = true
            return false
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            permissionDenied = !granted
            return granted
        @unknown default:
            permissionDenied = true
            return false
        }
    }

    func start(url: URL) throws {
        stopCapturing(notify: false)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = false
        guard recorder.prepareToRecord(), recorder.record() else {
            throw RecorderError.failedToStart
        }
        self.recorder = recorder
        recordingStartedAt = Date()
        isRecording = true
        lastError = nil
        let cap = Timer(timeInterval: RecordingLibrary.maxDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
        RunLoop.main.add(cap, forMode: .common)
        capTimer = cap
    }

    func stop() {
        stopCapturing(notify: true)
    }

    private func stopCapturing(notify: Bool) {
        capTimer?.invalidate()
        capTimer = nil
        let wasRecording = isRecording
        recorder?.stop()
        recorder = nil
        isRecording = false
        recordingStartedAt = nil
        if notify && wasRecording {
            onFinished?()
        }
    }
}

enum RecorderError: LocalizedError {
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            "Cadent couldn't start the microphone."
        }
    }
}
