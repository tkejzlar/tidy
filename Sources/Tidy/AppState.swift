import SwiftUI
import TidyCore

@Observable
@MainActor
final class AppState {
    enum IconState { case idle, hasSuggestions, processing }
    var iconState: IconState = .idle

    var iconName: String {
        switch iconState {
        case .idle: "diamond"
        case .hasSuggestions: "diamond.fill"
        case .processing: "arrow.trianglehead.2.clockwise"
        }
    }

    struct Suggestion: Identifiable {
        let id = UUID()
        let candidate: FileCandidate
        let decision: RoutingDecision
    }

    var suggestions: [Suggestion] = []
    var recentMoves: [MoveRecord] = []
    var unsortedCount: Int = 0
    var movedTodayCount: Int = 0
    var isPaused: Bool = false
    var showSettings: Bool = false
    var watchPath: String = "~/Downloads"
    var autoMoveThreshold: Double = 80
    var suggestThreshold: Double = 50
    var settleTime: Double = 5
    var showNotifications: Bool = true
    var soundOnAutoMove: Bool = false

    private var orchestrator: MoveOrchestrator?
    private var fileWatcher: FileWatcher?
    private var watchTask: Task<Void, Never>?

    func start() async {
        // Will be implemented in Task 2
    }

    func approve(_ suggestion: Suggestion) {}
    func reject(_ suggestion: Suggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }
    func redirect(_ suggestion: Suggestion) {}
    func approveAll() {}
    func undoLastMove() {}
}
