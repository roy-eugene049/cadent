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
        Button("Settings…") {
            model.openSettings()
        }
        Divider()
        Button("Quit Cadent") {
            model.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
