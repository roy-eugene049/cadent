import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @State private var draftTitle = ""
    @State private var phase: RecordPhase = .idle
    @State private var message: String?
    @State private var reRecord: Reminder?
    @State private var pendingDelete: Reminder?

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

            Section("Your voice") {
                if model.settings.reminders.isEmpty {
                    Text("Record a reminder in your own voice. Cadent plays it when it's time to stretch.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.settings.reminders) { reminder in
                    reminderRow(reminder)
                }
            }

            Section("New reminder") {
                TextField("Title", text: $draftTitle, prompt: Text("Stand up and roll your shoulders"))
                recordingControls
                Text("30 seconds max. This is the clip Cadent will play.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { model.refreshLoginItemStatus() }
        .onChange(of: model.recorder.isRecording) { _, recording in
            guard reRecord == nil else { return }
            movePhaseAfterRecording(recording)
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    delete(pendingDelete)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $reRecord) { reminder in
            ReRecordSheet(model: model, reminder: reminder)
        }
    }

    private func reminderRow(_ reminder: Reminder) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { reminder.enabled },
                    set: { model.settings.setEnabled(id: reminder.id, enabled: $0) }
                )
            )
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                Text(model.library.fileExists(reminder) ? voiceDuration(reminder.duration) : "Audio file missing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Preview") {
                model.player.play(url: model.library.url(for: reminder))
            }
            .disabled(!model.library.fileExists(reminder) || model.recorder.isRecording)
            Button("Re-record") {
                message = nil
                phase = .idle
                reRecord = reminder
            }
            .disabled(model.recorder.isRecording)
            Button("Delete", role: .destructive) {
                pendingDelete = reminder
            }
            .disabled(model.recorder.isRecording)
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        if phase == .recording, let started = model.recorder.recordingStartedAt {
            TimelineView(.periodic(from: started, by: 0.1)) { context in
                Text(voiceDuration(context.date.timeIntervalSince(started)))
                    .font(.title3.monospacedDigit())
            }
            Button("Stop") {
                model.recorder.stop()
            }
        } else if phase == .preview {
            HStack {
                Button("Preview") {
                    model.player.play(url: model.library.draftURL)
                }
                Button("Save") {
                    saveDraft()
                }
                .buttonStyle(.borderedProminent)
                Button("Discard") {
                    discardDraft()
                }
            }
        } else {
            Button("Record") {
                Task { await beginRecording() }
            }
            .disabled(
                draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.recorder.isRecording
                    || reRecord != nil
            )
            .buttonStyle(.borderedProminent)
        }
    }

    private func beginRecording() async {
        message = nil
        let allowed = await model.recorder.requestPermission()
        guard allowed else {
            message = "Cadent needs microphone access to record your voice. Enable it in System Settings > Privacy & Security > Microphone."
            return
        }
        do {
            try model.recorder.start(url: model.library.prepareDraft())
            phase = .recording
        } catch {
            message = error.localizedDescription
        }
    }

    private func movePhaseAfterRecording(_ recording: Bool) {
        guard !recording, phase == .recording else { return }
        let duration = model.library.duration(of: model.library.draftURL)
        if duration < 0.3 {
            model.library.discardDraft()
            phase = .idle
            message = "Recording was too short."
        } else {
            phase = .preview
        }
    }

    private func saveDraft() {
        model.player.stop()
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let reminder = model.settings.addReminder(title: title, duration: 0)
        do {
            let duration = try model.library.adoptDraft(for: reminder)
            model.settings.updateDuration(id: reminder.id, duration: duration)
            draftTitle = ""
            phase = .idle
            message = nil
        } catch {
            model.settings.remove(id: reminder.id)
            message = error.localizedDescription
        }
    }

    private func discardDraft() {
        model.player.stop()
        model.library.discardDraft()
        phase = .idle
    }

    private func delete(_ reminder: Reminder) {
        model.player.stop()
        model.library.deleteFile(for: reminder)
        model.settings.remove(id: reminder.id)
        pendingDelete = nil
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
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

private struct ReRecordSheet: View {
    var model: AppModel
    let reminder: Reminder
    @Environment(\.dismiss) private var dismiss
    @State private var phase: RecordPhase = .idle
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Re-record")
                .font(.title2.weight(.semibold))
            Text(reminder.title)
                .foregroundStyle(.secondary)
            if phase == .recording, let started = model.recorder.recordingStartedAt {
                TimelineView(.periodic(from: started, by: 0.1)) { context in
                    Text(voiceDuration(context.date.timeIntervalSince(started)))
                        .font(.title3.monospacedDigit())
                }
                Button("Stop") { model.recorder.stop() }
            } else if phase == .preview {
                HStack {
                    Button("Preview") {
                        model.player.play(url: model.library.draftURL)
                    }
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                    Button("Discard") { discard() }
                }
            } else {
                Button("Record") { Task { await begin() } }
                    .buttonStyle(.borderedProminent)
            }
            if let message {
                Text(message)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Close") {
                    model.recorder.stop()
                    model.player.stop()
                    model.library.discardDraft()
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .onChange(of: model.recorder.isRecording) { _, recording in
            guard !recording, phase == .recording else { return }
            let duration = model.library.duration(of: model.library.draftURL)
            if duration < 0.3 {
                model.library.discardDraft()
                phase = .idle
                message = "Recording was too short."
            } else {
                phase = .preview
            }
        }
    }

    private func begin() async {
        message = nil
        let allowed = await model.recorder.requestPermission()
        guard allowed else {
            message = "Cadent needs microphone access to record your voice. Enable it in System Settings > Privacy & Security > Microphone."
            return
        }
        do {
            try model.recorder.start(url: model.library.prepareDraft())
            phase = .recording
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() {
        model.player.stop()
        do {
            let duration = try model.library.adoptDraft(for: reminder)
            model.settings.updateDuration(id: reminder.id, duration: duration)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func discard() {
        model.player.stop()
        model.library.discardDraft()
        phase = .idle
    }
}

private enum RecordPhase {
    case idle
    case recording
    case preview
}

private func voiceDuration(_ duration: TimeInterval) -> String {
    let total = max(0, Int(duration.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
