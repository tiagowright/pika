import AppKit
import SwiftUI

/// Click, press a key combination, done. Esc cancels. The recording logic
/// lives in SettingsModel.
struct HotkeyRecorder: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                model.recordingHotkey ? model.stopRecordingHotkey() : model.startRecordingHotkey()
            } label: {
                Text(model.recordingHotkey ? "Press a shortcut…" : model.config.hotkey)
                    .font(.custom(PikaFont.family, size: 13))
                    .frame(minWidth: 150)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(model.recordingHotkey
                ? "Recording hotkey. Press a shortcut, or Escape to cancel."
                : "Hotkey \(model.config.hotkey). Click to change.")

            if let hint = model.hotkeyHint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            } else if model.recordingHotkey {
                Text("Include ctrl, cmd, or alt. Esc cancels.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { model.stopRecordingHotkey() }
    }
}
