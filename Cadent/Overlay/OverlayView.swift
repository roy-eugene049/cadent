import SwiftUI

struct OverlayView: View {
    var model: AppModel
    let title: String
    let voiceName: String
    let snoozeMinutes: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "figure.flexibility")
                    .font(.system(size: 44, weight: .medium))
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(status)
                    .font(.body)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Snooze \(snoozeMinutes) min", action: model.snoozeBreak)
                        .controlSize(.large)
                    Button("Done", action: model.finishBreak)
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .frame(maxWidth: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var status: String {
        if model.playFailed {
            "Couldn't play this recording."
        } else if model.isPlaying {
            "Playing \(voiceName)"
        } else {
            "Take a moment to stretch"
        }
    }
}
