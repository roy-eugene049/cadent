import AppKit
import SwiftUI

@main
struct CadentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label("Cadent", systemImage: "figure.flexibility")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.current?.shutdown()
    }
}

struct MenuBarContent: View {
    var model: AppModel

    var body: some View {
        Button(model.settings.paused ? "Resume" : "Pause") {
            if model.settings.paused {
                model.resume()
            } else {
                model.pause()
            }
        }
        Button("Stretch Now") {
            model.stretchNow()
        }
        .disabled(!model.hasPlayableReminder)
        if !model.hasPlayableReminder {
            Text("Record a reminder in Settings.")
        }
        if model.settings.paused {
            Text("Paused")
        } else if let next = model.settings.nextBreakAt {
            Text("Next break \(next.formatted(date: .omitted, time: .shortened))")
        }
        Divider()
        #if DEBUG
        Button("Break in 10 Seconds") {
            model.debugArmShort()
        }
        #endif
        Button("Settings…") {
            model.openSettings()
        }
        Divider()
        Button("Quit Cadent") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
