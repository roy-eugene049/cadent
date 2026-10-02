import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @State private var hoursText = "0"
    @State private var minutesText = "30"
    @State private var snoozeText = "5"
    @State private var dismissDraft = 60
    @FocusState private var focusedTime: TimeField?
    @State private var draftTitle = ""
    @State private var phase: RecordPhase = .idle
    @State private var message: String?
    @State private var reRecord: Reminder?
    @State private var pendingDelete: Reminder?

    var body: some View {
        Form {
            Section("Schedule") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Break every")
                    HStack(spacing: 10) {
                        timeField($hoursText, focus: .hours)
                        Text("hours")
                        timeField($minutesText, focus: .minutes)
                        Text("minutes")
                    }
                    Text("Type any length up to 24 hours. \(intervalSummary)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snooze")
                    HStack(spacing: 10) {
                        timeField($snoozeText, focus: .snooze)
                        Text("minutes")
                    }
                }
                Stepper(value: $dismissDraft, in: 15...300, step: 15) {
                    Text("Card stays \(dismissDraft) sec")
                }
                HStack {
                    Button("Save") {
                        saveSchedule()
                    }
                    .disabled(!scheduleIsDirty)
                    .buttonStyle(.borderedProminent)
                    if scheduleIsDirty {
                        Text("Save to use your new times.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            syncTimeFields()
            model.refreshLoginItemStatus()
        }
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

    private func timeField(_ text: Binding<String>, focus: TimeField) -> some View {
        TextField("", text: text, prompt: Text("0"))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
            .focused($focusedTime, equals: focus)
            .onSubmit { saveSchedule() }
    }

    private var intervalSummary: String {
        let total = model.settings.intervalMinutes
        let hours = total / 60
        let minutes = total % 60
        if hours == 0 {
            return "Cadent will remind you every \(minutes) min."
        }
        if minutes == 0 {
            return "Cadent will remind you every \(hours) h."
        }
        return "Cadent will remind you every \(hours) h \(minutes) min."
    }

    private var scheduleIsDirty: Bool {
        guard let draft = scheduleDraft else { return false }
        return draft.interval != model.settings.intervalMinutes
            || draft.snooze != model.settings.snoozeMinutes
            || dismissDraft != model.settings.autoDismissSeconds
    }

    private var scheduleDraft: (interval: Int, snooze: Int)? {
        let hours = Int(hoursText.trimmingCharacters(in: .whitespaces))
        let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces))
        let snooze = Int(snoozeText.trimmingCharacters(in: .whitespaces))
        guard let hours, let minutes, let snooze, hours >= 0, minutes >= 0, snooze > 0 else {
            return nil
        }
        let interval = min(SettingsStore.maximumIntervalMinutes, max(1, (hours * 60) + minutes))
        return (interval, min(240, snooze))
    }

    private func syncTimeFields() {
        let total = model.settings.intervalMinutes
        hoursText = String(total / 60)
        minutesText = String(total % 60)
        snoozeText = String(model.settings.snoozeMinutes)
        dismissDraft = model.settings.autoDismissSeconds
    }

    private func saveSchedule() {
        guard let draft = scheduleDraft else {
            syncTimeFields()
            return
        }
        let hours = draft.interval / 60
        let minutes = draft.interval % 60
        model.setPreferredInterval(hours: hours, minutes: minutes)
        model.settings.snoozeMinutes = draft.snooze
        model.settings.autoDismissSeconds = dismissDraft
        syncTimeFields()
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

private enum TimeField: Hashable {
    case hours
    case minutes
    case snooze
}

private func voiceDuration(_ duration: TimeInterval) -> String {
    let total = max(0, Int(duration.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
