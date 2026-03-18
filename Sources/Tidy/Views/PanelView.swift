import SwiftUI
import TidyCore

struct PanelView: View {
    @Bindable var state: AppState
    @State private var showCleanupPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tidy").font(.headline)
                Spacer()
                Button(action: { showCleanupPicker = true }) {
                    Image(systemName: "sparkles")
                        .help("Clean up a folder")
                }.buttonStyle(.plain)
                Button(action: { state.showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain)
                Button(action: { state.isPaused.toggle() }) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if state.showSettings {
                SettingsView(state: state)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Cleanup progress indicator
                        if state.isCleaningUp, let progress = state.cleanupProgress {
                            HStack {
                                ProgressView(value: Double(progress.current), total: Double(progress.total))
                                Text("\(progress.current)/\(progress.total)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button("Cancel") {
                                    // appState.cancelCleanup()
                                }
                                .font(.caption)
                            }
                            .padding(.horizontal)
                        }

                        // Batch undo button
                        if state.lastCleanupBatchId != nil {
                            Button(action: {
                                Task { await state.undoLastCleanup() }
                            }) {
                                Label("Undo Cleanup", systemImage: "arrow.uturn.backward")
                            }
                            .padding(.horizontal)
                        }

                        if !state.suggestions.isEmpty {
                            HStack {
                                Text("Suggestions")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if state.suggestions.count >= 3 {
                                    Button("Move all") { state.approveAll() }
                                        .font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal)

                            // Move All High-Confidence button
                            if state.suggestions.count >= 3 {
                                let highConfidence = state.suggestions.filter { $0.decision.confidence >= 80 }
                                if !highConfidence.isEmpty {
                                    Button(action: {
                                        Task { await state.approveAllHighConfidence() }
                                    }) {
                                        Label("Move All High-Confidence (\(highConfidence.count))", systemImage: "checkmark.circle.fill")
                                    }
                                    .padding(.horizontal)
                                }
                            }

                            ForEach(state.suggestions) { suggestion in
                                SuggestionCard(
                                    suggestion: suggestion,
                                    onApprove: { state.approve(suggestion) },
                                    onReject: { state.reject(suggestion) },
                                    onRedirect: { state.redirect(suggestion) }
                                ).padding(.horizontal, 8)
                            }
                        }

                        if !state.recentMoves.isEmpty {
                            Text("Recent moves")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            ForEach(state.recentMoves.prefix(5), id: \.id) { move in
                                RecentMoveRow(move: move) { state.undoLastMove() }
                                    .padding(.horizontal, 8)
                            }
                        }

                        if state.suggestions.isEmpty && state.recentMoves.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.largeTitle).foregroundStyle(.tertiary)
                                Text("All tidy!")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.vertical, 8)
                }

                StatusFooter(
                    watchPath: state.watchPath,
                    unsortedCount: state.unsortedCount,
                    movedTodayCount: state.movedTodayCount
                )
            }
        }
        .frame(width: 360, height: 480)
        .onChange(of: showCleanupPicker) { _, newValue in
            guard newValue else { return }
            showCleanupPicker = false
            pickCleanupFolder()
        }
    }

    private func pickCleanupFolder() {
        // MenuBarExtra panels have hidesOnDeactivate — we must prevent
        // the panel from stealing focus back from NSOpenPanel.
        // Temporarily disable hidesOnDeactivate on all windows.
        let windows = NSApp.windows
        let originalHides = windows.map { ($0, ($0 as? NSPanel)?.hidesOnDeactivate ?? false) }
        for window in windows {
            (window as? NSPanel)?.hidesOnDeactivate = false
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Clean Up"
        panel.message = "Choose a folder to scan and organize"

        let response = panel.runModal()

        // Restore original hidesOnDeactivate
        for (window, hides) in originalHides {
            (window as? NSPanel)?.hidesOnDeactivate = hides
        }

        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in
            await state.startCleanup(folder: url)
        }
    }
}
