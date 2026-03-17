import SwiftUI
import TidyCore

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Watch folder") {
                    HStack {
                        Text(state.watchPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(action: pickWatchFolder) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Auto-move confidence")
                        Spacer()
                        Text("\(Int(state.autoMoveThreshold))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $state.autoMoveThreshold, in: 50...100, step: 5)

                    HStack {
                        Text("Suggestion confidence")
                        Spacer()
                        Text("\(Int(state.suggestThreshold))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $state.suggestThreshold, in: 20...80, step: 5)
                }

                Divider()

                HStack {
                    Text("Settle time (seconds)")
                    Spacer()
                    TextField("", value: $state.settleTime, format: .number)
                        .frame(width: 40)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Wait before acting on new files")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()

                Toggle("Show notifications for auto-moves", isOn: $state.showNotifications)
                Toggle("Sound on auto-move", isOn: $state.soundOnAutoMove)

                Divider()

                Button(action: { state.showSettings = false }) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .font(.system(size: 12))
    }

    private func pickWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSString(string: state.watchPath).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            state.watchPath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
    }
}
