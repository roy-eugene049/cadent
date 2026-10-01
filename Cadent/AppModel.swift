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

    private(set) var loginItemMessage: String?
    private var settingsWindow: NSWindow?

    init() {
        let settings = SettingsStore()
        let library = RecordingLibrary()
        let recorder = ReminderRecorder()
        let player = ReminderPlayer()
        let scheduler = BreakScheduler(settings: settings)
        self.settings = settings
        self.library = library
        self.recorder = recorder
        self.player = player
        self.scheduler = scheduler
        Self.current = self

        scheduler.onFire = { [weak self] in
            self?.noteBreakDue()
        }
        scheduler.isBreakVisible = { false }
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

    func stretchNow() {
        noteBreakDue()
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let window = settingsWindow ?? makeSettingsWindow()
        place(window, on: screenContainingMouse())
        window.makeKeyAndOrderFront(nil)
        Log.info("settings frame \(NSStringFromRect(window.frame))")
    }

    func shutdown() {
        scheduler.stop()
        recorder.stop()
        player.stop()
    }

    #if DEBUG
    func debugArmShort() {
        scheduler.arm(after: 10)
    }
    #endif

    private func noteBreakDue() {
        guard let reminder = settings.consumeNextPlayable(fileExists: { library.fileExists($0) }) else {
            Log.info("break skipped, no recording")
            scheduler.armNextInterval()
            return
        }
        Log.info("break due \(reminder.title)")
        scheduler.armNextInterval()
    }

    private func makeSettingsWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(model: self))
        let window = NSWindow(contentViewController: host)
        window.title = "Cadent"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 680))
        window.minSize = NSSize(width: 480, height: 420)
        window.isReleasedWhenClosed = false
        settingsWindow = window
        return window
    }

    private func place(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        )
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
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
        if arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openSettings()
            }
        }
    }
    #endif
}
