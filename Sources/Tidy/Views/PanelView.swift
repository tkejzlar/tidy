import SwiftUI
import TidyCore

struct PanelView: View {
    @Bindable var state: AppState

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
    }
}
