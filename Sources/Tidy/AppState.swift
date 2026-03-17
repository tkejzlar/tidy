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
    var isPaused: Bool = false {
        didSet { Task { await orchestrator?.setPaused(isPaused) } }
    }
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
        do {
            let expandedPath = NSString(string: watchPath).expandingTildeInPath

            // Try Dropbox path first, fall back to app support
            let dbPath: String
            let dropboxPath = NSString(string: "~/Dropbox/.tidy/knowledge.db").expandingTildeInPath
            let dropboxDir = (dropboxPath as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: dropboxDir) {
                try FileManager.default.createDirectory(atPath: dropboxDir, withIntermediateDirectories: true)
                dbPath = dropboxPath
            } else {
                let appSupport = NSString(string: "~/Library/Application Support/Tidy").expandingTildeInPath
                try FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
                dbPath = "\(appSupport)/knowledge.db"
            }

            let kb = try KnowledgeBase(path: dbPath)

            let roots = [
                NSString(string: "~/Documents").expandingTildeInPath,
                NSString(string: "~/Dropbox").expandingTildeInPath,
                NSString(string: "~/Desktop").expandingTildeInPath,
                NSString(string: "~/Pictures").expandingTildeInPath,
            ].filter { FileManager.default.fileExists(atPath: $0) }

            let affinities = FolderArchaeologist().scan(roots: roots)
            let clusters = TokenClusterer().buildClusters(roots: roots)
            let heuristics = HeuristicsEngine(affinities: affinities, clusters: clusters)
            let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)

            let orch = MoveOrchestrator(
                scoringEngine: engine, knowledgeBase: kb, settleSeconds: settleTime
            )
            self.orchestrator = orch

            let watcher = FileWatcher(watchPath: expandedPath)
            self.fileWatcher = watcher
            watcher.start()

            watchTask = Task { [weak self] in
                for await event in watcher.events {
                    await self?.handleFileEvent(event)
                }
            }

            recentMoves = try kb.recentMoves(limit: 20)
            updateCounts()
        } catch { }
    }

    func approve(_ suggestion: Suggestion) {
        guard let orchestrator else { return }
        Task {
            do {
                let move = try await orchestrator.approveSuggestion(
                    candidate: suggestion.candidate, destination: suggestion.decision.destination
                )
                suggestions.removeAll { $0.id == suggestion.id }
                recentMoves.insert(move, at: 0)
                if recentMoves.count > 20 { recentMoves = Array(recentMoves.prefix(20)) }
                movedTodayCount += 1
                updateIconState()
            } catch { }
        }
    }

    func reject(_ suggestion: Suggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
        updateIconState()
    }

    func redirect(_ suggestion: Suggestion) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Destination"
        if panel.runModal() == .OK, let url = panel.url {
            guard let orchestrator else { return }
            Task {
                do {
                    let move = try await orchestrator.redirect(
                        candidate: suggestion.candidate,
                        suggestedDestination: suggestion.decision.destination,
                        chosenDestination: url.path
                    )
                    suggestions.removeAll { $0.id == suggestion.id }
                    recentMoves.insert(move, at: 0)
                    if recentMoves.count > 20 { recentMoves = Array(recentMoves.prefix(20)) }
                    movedTodayCount += 1
                    updateIconState()
                } catch { }
            }
        }
    }

    func approveAll() {
        let current = suggestions
        for s in current { approve(s) }
    }

    func undoLastMove() {
        guard let orchestrator else { return }
        Task {
            if let undone = try? await orchestrator.undoLastMove() {
                recentMoves.removeAll { $0.id == undone.id }
                movedTodayCount = max(0, movedTodayCount - 1)
                updateIconState()
            }
        }
    }

    private func handleFileEvent(_ event: FileEvent) async {
        guard let orchestrator else { return }
        switch event {
        case .created(let path), .modified(let path):
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let fileSize = attrs?[.size] as? UInt64 ?? 0
            let metadata = FileMetadataExtractor().extract(from: path)
            let candidate = FileCandidate(path: path, fileSize: fileSize, metadata: metadata)

            iconState = .processing
            defer { updateIconState() }

            if let orchEvent = try? await orchestrator.processFile(candidate) {
                handleOrchestratorEvent(orchEvent)
            }

        case .movedOut(let path):
            let filename = (path as NSString).lastPathComponent
            _ = try? await orchestrator.recordUserMove(filename: filename, fileSize: 0, destination: "unknown")

        case .removed:
            break
        }
    }

    private func handleOrchestratorEvent(_ event: OrchestratorEvent) {
        switch event {
        case .autoMoved(let move, _):
            recentMoves.insert(move, at: 0)
            if recentMoves.count > 20 { recentMoves = Array(recentMoves.prefix(20)) }
            movedTodayCount += 1
        case .suggested(let candidate, let decision):
            suggestions.append(Suggestion(candidate: candidate, decision: decision))
        case .newFile:
            break // Could track unsorted count
        case .undone(let move):
            recentMoves.removeAll { $0.id == move.id }
        case .observed:
            break
        }
        updateIconState()
        updateCounts()
    }

    private func updateIconState() {
        iconState = suggestions.isEmpty ? .idle : .hasSuggestions
    }

    private func updateCounts() {
        let path = NSString(string: watchPath).expandingTildeInPath
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        unsortedCount = contents.filter { !$0.hasPrefix(".") }.count
    }
}
