import SwiftUI
import TidyCore

struct PanelView: View {
    @Bindable var state: AppState
    @State private var visiblePerTier: [String: Int] = [:]

    private let pageSize = 20

    private var autoMoveSuggestions: [AppState.Suggestion] {
        state.suggestions.filter { $0.decision.tier == .autoMove }
    }

    private var suggestSuggestions: [AppState.Suggestion] {
        state.suggestions.filter { $0.decision.tier == .suggest }
    }

    private var askSuggestions: [AppState.Suggestion] {
        state.suggestions.filter { $0.decision.tier == .ask }
    }

    private func visibleCount(for tier: String) -> Int {
        visiblePerTier[tier] ?? pageSize
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tidy").font(.headline)
                Spacer()
                Button(action: {
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
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                            // Overall suggestions header
                            HStack {
                                Text("Suggestions (\(state.suggestions.count))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if state.suggestions.count >= 3 {
                                    Button("Move all") { state.approveAll() }
                                        .font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal)

                            // High Confidence tier (autoMove: 80–100)
                            if !autoMoveSuggestions.isEmpty {
                                tierSection(
                                    tier: "autoMove",
                                    title: "High Confidence",
                                    suggestions: autoMoveSuggestions,
                                    accentColor: .green,
                                    showBatchAction: true
                                )
                            }

                            // Suggestions tier (suggest: 50–79)
                            if !suggestSuggestions.isEmpty {
                                tierSection(
                                    tier: "suggest",
                                    title: "Suggestions",
                                    suggestions: suggestSuggestions,
                                    accentColor: .blue,
                                    showBatchAction: true
                                )
                            }

                            // Needs Review tier (ask: 0–49)
                            if !askSuggestions.isEmpty {
                                tierSection(
                                    tier: "ask",
                                    title: "Needs Review",
                                    suggestions: askSuggestions,
                                    accentColor: .orange,
                                    showBatchAction: false
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
        tier: String,
        title: String,
        suggestions: [AppState.Suggestion],
        accentColor: Color,
        showBatchAction: Bool
    ) -> some View {
        let visible = visibleCount(for: tier)
        let shown = Array(suggestions.prefix(visible))
        let remaining = suggestions.count - shown.count

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) (\(suggestions.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Spacer()
                if showBatchAction {
                    Button("Move All") {
                        let toApprove = suggestions
                        for s in toApprove { state.approve(s) }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal)

            ForEach(shown) { suggestion in
                SuggestionCard(
                    suggestion: suggestion,
                    onApprove: { state.approve(suggestion) },
                    onReject: { state.reject(suggestion) },
                    onRedirect: { state.redirect(suggestion) }
                ).padding(.horizontal, 8)
            }

            if remaining > 0 {
                Button("Show more (\(remaining) remaining)") {
                    visiblePerTier[tier] = visible + pageSize
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }
        }
    }
}
