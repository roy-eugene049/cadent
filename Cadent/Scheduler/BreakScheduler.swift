import AppKit
import Foundation

@MainActor
final class BreakScheduler {
    private let settings: SettingsStore
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    var onFire: (() -> Void)?
    var isBreakVisible: () -> Bool = { false }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWake()
                }
            }
        }
        if settings.paused {
            return
        }
        if settings.nextBreakAt == nil {
            armNextInterval()
        } else {
            schedule()
        }
    }

    func pause() {
        settings.paused = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        settings.paused = false
        if let next = settings.nextBreakAt, next > Date() {
            schedule()
        } else {
            armNextInterval()
        }
    }

    func armNextInterval() {
        let minutes = max(1, settings.intervalMinutes)
        arm(after: TimeInterval(minutes * 60))
    }

    func snooze() {
        let minutes = max(1, settings.snoozeMinutes)
        arm(after: TimeInterval(minutes * 60))
    }

    func arm(after seconds: TimeInterval) {
        settings.nextBreakAt = Date().addingTimeInterval(max(1, seconds))
        Log.info("armed \(self.settings.nextBreakAt?.formatted(.iso8601) ?? "nil")")
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard !settings.paused, let next = settings.nextBreakAt else { return }
        let delay = next.timeIntervalSinceNow
        if delay <= 0.05 {
            DispatchQueue.main.async { [weak self] in
                self?.fireIfDue()
            }
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fireIfDue()
            }
        }
        timer.tolerance = min(5, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fireIfDue() {
        guard !settings.paused else { return }
        guard !isBreakVisible() else { return }
        guard let next = settings.nextBreakAt, next.timeIntervalSinceNow <= 0.5 else {
            schedule()
            return
        }
        onFire?()
    }

    private func handleWake() {
        Log.info("wake")
        guard !settings.paused else { return }
        guard !isBreakVisible() else { return }
        guard let next = settings.nextBreakAt else {
            armNextInterval()
            return
        }
        if next <= Date() {
            onFire?()
        } else {
            schedule()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
}
