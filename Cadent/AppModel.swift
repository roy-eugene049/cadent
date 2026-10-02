import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static weak var current: AppModel?

    let settings: SettingsStore
    let library: RecordingLibrary
    let recorder: ReminderRecorder
    let player: ReminderPlayer
    let scheduler: BreakScheduler
    let overlay: OverlayController

    private(set) var isPresentingBreak = false
    private(set) var isPlaying = false
    private(set) var playFailed = false
    private(set) var loginItemMessage: String?
    private var settingsWindow: NSWindow?

    init() {
        let settings = SettingsStore()
        let library = RecordingLibrary()
        let recorder = ReminderRecorder()
        let player = ReminderPlayer()
        let overlay = OverlayController()
        let scheduler = BreakScheduler(settings: settings)
        self.settings = settings
        self.library = library
        self.recorder = recorder
        self.player = player
        self.overlay = overlay
        self.scheduler = scheduler
        Self.current = self

        player.onChange = { [weak self] in
            self?.syncPlayback()
        }
        scheduler.onFire = { [weak self] in
            self?.presentNextBreak()
        }
        scheduler.isBreakVisible = { [weak self] in
            self?.isPresentingBreak ?? false
        }
        scheduler.start()
        Log.info("model init")
        #if DEBUG
        applyDebugArguments()
        #endif
    }

    var hasPlayableReminder: Bool {
        settings.hasPlayableReminder { library.fileExists($0) }
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
            loginItemMessage = loginMessage(for: service.status)
        } catch {
            loginItemMessage = error.localizedDescription
        }
    }

    func refreshLoginItemStatus() {
        loginItemMessage = loginMessage(for: SMAppService.mainApp.status)
    }

    func pause() {
        scheduler.pause()
    }

    func resume() {
        scheduler.resume()
    }

    func setPreferredInterval(hours: Int, minutes: Int) {
        let previous = settings.intervalMinutes
        settings.intervalMinutes = (hours * 60) + minutes
        guard settings.intervalMinutes != previous else { return }
        guard !settings.paused, !isPresentingBreak else { return }
        scheduler.armNextInterval()
    }

    func stretchNow() {
        guard hasPlayableReminder else {
            Log.info("stretch now skipped, no recording")
            return
        }
        presentNextBreak()
    }

    func finishBreak() {
        guard isPresentingBreak else { return }
        isPresentingBreak = false
        overlay.dismiss()
        player.stop()
        Log.info("dismiss")
        guard !settings.paused else { return }
        scheduler.armNextInterval()
    }

    func snoozeBreak() {
        guard isPresentingBreak else { return }
        isPresentingBreak = false
        overlay.dismiss()
        player.stop()
        Log.info("snooze")
        guard !settings.paused else { return }
        scheduler.snooze()
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let window = settingsWindow ?? makeSettingsWindow()
        if let screen = OverlayController.screenContainingMouse() {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(
                NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
            )
        }
        window.makeKeyAndOrderFront(nil)
        Log.info("settings frame \(NSStringFromRect(window.frame))")
    }

    private func makeSettingsWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(model: self))
        let window = NSWindow(contentViewController: host)
        window.title = "Cadent"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 760))
        window.minSize = NSSize(width: 560, height: 520)
        window.isReleasedWhenClosed = false
        settingsWindow = window
        return window
    }

    func shutdown() {
        scheduler.stop()
        recorder.stop()
        player.stop()
        overlay.dismiss()
    }

    #if DEBUG
    func debugArmShort() {
        scheduler.arm(after: 10)
    }
    #endif

    private func presentNextBreak() {
        guard let reminder = settings.consumeNextPlayable(fileExists: { library.fileExists($0) }) else {
            Log.info("break skipped, no recording")
            if !isPresentingBreak {
                scheduler.armNextInterval()
            }
            return
        }
        guard let screen = OverlayController.screenContainingMouse() ?? NSScreen.screens.first else {
            scheduler.armNextInterval()
            return
        }
        isPresentingBreak = true
        playFailed = false
        player.play(url: library.url(for: reminder))
        overlay.show(
            screen: screen,
            autoDismiss: TimeInterval(settings.autoDismissSeconds),
            onDone: { [weak self] in
                self?.finishBreak()
            },
            content: OverlayView(
                model: self,
                title: reminder.title,
                snoozeMinutes: settings.snoozeMinutes
            )
        )
        Log.info("show \(reminder.title)")
        scheduler.armNextInterval()
    }

    private func syncPlayback() {
        isPlaying = player.isPlaying
        playFailed = player.lastError != nil && !player.isPlaying
    }

    private func loginMessage(for status: SMAppService.Status) -> String? {
        switch status {
        case .enabled, .notRegistered:
            nil
        case .requiresApproval:
            "Approve Cadent in System Settings > General > Login Items."
        case .notFound:
            "Cadent has to be installed before it can open at login."
        @unknown default:
            nil
        }
    }

    #if DEBUG
    private func applyDebugArguments() {
        let arguments = CommandLine.arguments
        var argumentIndex = 0
        while argumentIndex < arguments.count {
            if arguments[argumentIndex] == "--import-sample", arguments.indices.contains(argumentIndex + 1) {
                let url = URL(fileURLWithPath: arguments[argumentIndex + 1])
                do {
                    _ = try library.importFile(at: url, title: url.deletingPathExtension().lastPathComponent, into: settings)
                    Log.info("imported sample")
                } catch {
                    Log.error("import failed \(error.localizedDescription)")
                }
                argumentIndex += 2
                continue
            }
            argumentIndex += 1
        }
        if arguments.contains("--arm-10") {
            scheduler.arm(after: 10)
        }
        if arguments.contains("--pause") {
            pause()
        }
        if arguments.contains("--stretch-now") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.stretchNow()
            }
        }
        if arguments.contains("--snooze-after-show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                self?.snoozeBreak()
            }
        }
        if arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openSettings()
            }
        }
    }
    #endif
}
