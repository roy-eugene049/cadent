import SwiftUI

struct SettingsView: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("Schedule") {
                Stepper(value: intervalBinding, in: 1...180) {
                    Text("Every \(model.settings.intervalMinutes) min")
                }
                Stepper(value: snoozeBinding, in: 1...60) {
                    Text("Snooze \(model.settings.snoozeMinutes) min")
                }
                Stepper(value: dismissBinding, in: 15...300, step: 15) {
                    Text("Card stays \(model.settings.autoDismissSeconds) sec")
                }
                Toggle("Launch at login", isOn: launchBinding)
                if let loginItemMessage = model.loginItemMessage {
                    Text(loginItemMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 320)
        .onAppear { model.refreshLoginItemStatus() }
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { model.settings.intervalMinutes },
            set: { model.settings.intervalMinutes = $0 }
        )
    }

    private var snoozeBinding: Binding<Int> {
        Binding(
            get: { model.settings.snoozeMinutes },
            set: { model.settings.snoozeMinutes = $0 }
        )
    }

    private var dismissBinding: Binding<Int> {
        Binding(
            get: { model.settings.autoDismissSeconds },
            set: { model.settings.autoDismissSeconds = $0 }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}
