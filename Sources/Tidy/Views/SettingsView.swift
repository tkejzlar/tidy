import SwiftUI
import TidyCore

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var addingRule = false
    @State private var newRuleExt = ""
    @State private var newRuleDest = ""

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

                Toggle("Launch at login", isOn: $state.launchAtLogin)

                Divider()

                // Pinned rules
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pinned rules").font(.system(size: 12, weight: .semibold))
                    ForEach(state.pinnedRules) { rule in
                        HStack {
                            Text("*.\(rule.fileExtension)")
                                .font(.caption).fontWeight(.medium)
                            Image(systemName: "arrow.right").font(.caption2)
                            Text(rule.destination)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(action: { state.removePinnedRule(extension: rule.fileExtension) }) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    if addingRule {
                        HStack {
                            TextField("ext", text: $newRuleExt).frame(width: 40).textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").font(.caption2)
                            TextField("destination", text: $newRuleDest).textFieldStyle(.roundedBorder)
                            Button("Add") {
                                if !newRuleExt.isEmpty && !newRuleDest.isEmpty {
                                    state.addPinnedRule(extension: newRuleExt, destination: newRuleDest)
                                    newRuleExt = ""
                                    newRuleDest = ""
                                    addingRule = false
                                }
                            }.font(.caption)
                            Button("Cancel") { addingRule = false }.font(.caption)
                        }
                    } else {
                        Button("+ Add rule") { addingRule = true }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
                    }
                }

                Divider()

                HStack {
                    Text("Knowledge base: \(state.patternCount) patterns")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Divider()

                LabeledContent("Sync path") {
                    HStack {
                        Text(state.dropboxSyncPath).font(.caption).foregroundStyle(.secondary)
                        Button(action: pickSyncFolder) {
                            Image(systemName: "folder")
                        }.buttonStyle(.plain)
                    }
                }

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

    private func pickSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: NSString(string: state.dropboxSyncPath).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            state.dropboxSyncPath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
    }
}
