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
    private(set) var loginItemMessage: String?
    private var settingsWindow: NSWindow?

    init() {
        settings = SettingsStore()
        Self.current = self
        Log.info("model init")
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

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let window = settingsWindow ?? makeSettingsWindow()
        place(window, on: screenContainingMouse())
        window.makeKeyAndOrderFront(nil)
        Log.info("settings frame \(NSStringFromRect(window.frame))")
    }

    func shutdown() {}

    private func makeSettingsWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(model: self))
        let window = NSWindow(contentViewController: host)
        window.title = "Cadent"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 420))
        window.minSize = NSSize(width: 480, height: 320)
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
}
