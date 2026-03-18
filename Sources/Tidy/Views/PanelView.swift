import SwiftUI
import TidyCore

struct PanelView: View {
    @Bindable var state: AppState

    private var autoMoveSuggestions: [AppState.Suggestion] {
        state.suggestions.filter { $0.decision.tier == .autoMove }
    }

    private var suggestSuggestions: [AppState.Suggestion] {
        state.suggestions.filter { $0.decision.tier == .suggest }
    }

    private var askSuggestions: [AppState.Suggestion] {
        state.suggestions.filter { $0.decision.tier == .ask }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tidy").font(.headline)
                Spacer()
                Button(action: {
                    NSLog("[PanelView] sparkles tapped")
                    let appState = state
                    FolderPicker.pick(prompt: "Clean Up", message: "Choose a folder to scan and organize") { url in
                        Task { @MainActor in await appState.startCleanup(folder: url) }
                    }
                }) {
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
                                    state.cancelCleanup()
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
                            // Overall suggestions header with "Move all" button
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

                            // High Confidence tier (autoMove: 80–100) — green accent
                            if !autoMoveSuggestions.isEmpty {
                                tierSection(
                                    title: "High Confidence",
                                    suggestions: autoMoveSuggestions,
                                    accentColor: .green,
                                    batchActionTitle: "Move All"
                                ) {
                                    for s in autoMoveSuggestions { state.approve(s) }
                                }
                            }

                            // Suggestions tier (suggest: 50–79) — blue accent
                            if !suggestSuggestions.isEmpty {
                                tierSection(
                                    title: "Suggestions",
                                    suggestions: suggestSuggestions,
                                    accentColor: .blue,
                                    batchActionTitle: "Move All"
                                ) {
                                    for s in suggestSuggestions { state.approve(s) }
                                }
                            }

                            // Needs Review tier (ask: 0–49) — orange accent, no batch action
                            if !askSuggestions.isEmpty {
                                tierSection(
                                    title: "Needs Review",
                                    suggestions: askSuggestions,
                                    accentColor: .orange,
                                    batchActionTitle: nil,
                                    batchAction: nil
                                )
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
    }

    @ViewBuilder
    private func tierSection(
        title: String,
        suggestions: [AppState.Suggestion],
        accentColor: Color,
        batchActionTitle: String?,
        batchAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) (\(suggestions.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Spacer()
                if let title = batchActionTitle, let action = batchAction {
                    Button(title, action: action)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal)

            ForEach(suggestions) { suggestion in
                SuggestionCard(
                    suggestion: suggestion,
                    onApprove: { state.approve(suggestion) },
                    onReject: { state.reject(suggestion) },
                    onRedirect: { state.redirect(suggestion) }
                ).padding(.horizontal, 8)
            }
        }
    }
}
