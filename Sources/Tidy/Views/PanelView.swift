import SwiftUI
import TidyCore

struct PanelView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tidy").font(.headline)
                Spacer()
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
