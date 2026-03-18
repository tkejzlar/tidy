import SwiftUI
import TidyCore

struct RulePackPreviewView: View {
    @Bindable var state: AppState
    let pack: RulePack

    @State private var selectedRuleExtensions: Set<String>

    init(state: AppState, pack: RulePack) {
        self.state = state
        self.pack = pack
        _selectedRuleExtensions = State(
            initialValue: Set(pack.pinnedRules.map { $0.fileExtension.lowercased() })
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: pack.metadata.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Rule Pack")
                        .font(.system(size: 12, weight: .semibold))
                    Text(pack.metadata.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // Metadata
                    VStack(alignment: .leading, spacing: 4) {
                        if !pack.metadata.description.isEmpty {
                            Text(pack.metadata.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Label(pack.metadata.author, systemImage: "person")
                            Label(formattedDate, systemImage: "calendar")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    }

                    Divider()

                    // Pinned Rules
                    if !pack.pinnedRules.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Pinned Rules")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("(\(pack.pinnedRules.count))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(selectedRuleExtensions.count == pack.pinnedRules.count ? "Deselect All" : "Select All") {
                                    if selectedRuleExtensions.count == pack.pinnedRules.count {
                                        selectedRuleExtensions = []
                                    } else {
                                        selectedRuleExtensions = Set(pack.pinnedRules.map { $0.fileExtension.lowercased() })
                                    }
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }

                            ForEach(pack.pinnedRules, id: \.fileExtension) { rule in
                                let ext = rule.fileExtension.lowercased()
                                Toggle(isOn: Binding(
                                    get: { selectedRuleExtensions.contains(ext) },
                                    set: { checked in
                                        if checked {
                                            selectedRuleExtensions.insert(ext)
                                        } else {
                                            selectedRuleExtensions.remove(ext)
                                        }
                                    }
                                )) {
                                    HStack(spacing: 4) {
                                        Text("*.\(rule.fileExtension)")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(selectedRuleExtensions.contains(ext) ? .primary : .secondary)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        Text(rule.destination)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }

                    // Patterns (read-only)
                    if !pack.patterns.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Patterns")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("(\(pack.patterns.count))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("All included")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            ForEach(Array(pack.patterns.prefix(5).enumerated()), id: \.offset) { _, pattern in
                                HStack(spacing: 4) {
                                    Text(pattern.feature)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text("=")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Text(pattern.value)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                    Text((pattern.destination as NSString).lastPathComponent)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            if pack.patterns.count > 5 {
                                Text("+ \(pack.patterns.count - 5) more patterns")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Folder Templates (read-only)
                    if !pack.folderTemplate.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Folder Templates")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("(\(pack.folderTemplate.count))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(pack.folderTemplate, id: \.self) { template in
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text(template)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 300)

            Divider()

            // Action buttons
            HStack {
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Import Selected") {
                    applyImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedRuleExtensions.isEmpty && pack.patterns.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .font(.system(size: 12))
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private func dismiss() {
        state.importPreviewPack = nil
        state.importPreviewPath = nil
    }

    private func applyImport() {
        guard let kb = state.knowledgeBase else {
            dismiss()
            return
        }
        let manager = RulePackManager()
        var rulesManager = PinnedRulesManager(rules: state.pinnedRules)
        let _ = try? manager.applyImport(
            pack: pack,
            acceptedRuleExtensions: selectedRuleExtensions,
            knowledgeBase: kb,
            pinnedRulesManager: &rulesManager
        )
        state.pinnedRules = rulesManager.rules
        dismiss()
    }
}
