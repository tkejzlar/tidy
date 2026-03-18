import SwiftUI
import TidyCore
import UserNotifications
import ServiceManagement

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
        let context: EnrichedFileContext
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
    var watchPath: String = "~/Downloads" {
        didSet { UserDefaults.standard.set(watchPath, forKey: "watchPath") }
    }
    var autoMoveThreshold: Double = 80 {
        didSet { UserDefaults.standard.set(autoMoveThreshold, forKey: "autoMoveThreshold") }
    }
    var suggestThreshold: Double = 50 {
        didSet { UserDefaults.standard.set(suggestThreshold, forKey: "suggestThreshold") }
    }
    var settleTime: Double = 5 {
        didSet { UserDefaults.standard.set(settleTime, forKey: "settleTime") }
    }
    var showNotifications: Bool = true {
        didSet { UserDefaults.standard.set(showNotifications, forKey: "showNotifications") }
    }
    var soundOnAutoMove: Bool = false {
        didSet { UserDefaults.standard.set(soundOnAutoMove, forKey: "soundOnAutoMove") }
    }

    var pinnedRules: [PinnedRule] = []
    var patternCount: Int = 0
    var launchAtLogin: Bool = false {
        didSet { updateLaunchAtLogin() }
    }
    var dropboxSyncPath: String = "~/Dropbox" {
        didSet { UserDefaults.standard.set(dropboxSyncPath, forKey: "dropboxSyncPath") }
    }

    private var orchestrator: MoveOrchestrator?
    private var pipeline: ContentIntelligencePipeline?
    private var fileWatcher: FileWatcher?
    private var watchTask: Task<Void, Never>?

    func start() async {
        // Load saved settings
        watchPath = UserDefaults.standard.string(forKey: "watchPath") ?? "~/Downloads"
        autoMoveThreshold = UserDefaults.standard.object(forKey: "autoMoveThreshold") as? Double ?? 80
        suggestThreshold = UserDefaults.standard.object(forKey: "suggestThreshold") as? Double ?? 50
        settleTime = UserDefaults.standard.object(forKey: "settleTime") as? Double ?? 5
        showNotifications = UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true
        soundOnAutoMove = UserDefaults.standard.bool(forKey: "soundOnAutoMove")
        dropboxSyncPath = UserDefaults.standard.string(forKey: "dropboxSyncPath") ?? "~/Dropbox"

        loadPinnedRules()

        do {
            let expandedPath = NSString(string: watchPath).expandingTildeInPath

            // Use configurable dropbox sync path for DB location
            let syncPath = NSString(string: dropboxSyncPath).expandingTildeInPath
            let dbPath: String
            let tidyDir = "\(syncPath)/.tidy"
            let dropboxPath = "\(tidyDir)/knowledge.db"
            if FileManager.default.fileExists(atPath: syncPath) {
                try FileManager.default.createDirectory(atPath: tidyDir, withIntermediateDirectories: true)
                dbPath = dropboxPath
            } else {
                let appSupport = NSString(string: "~/Library/Application Support/Tidy").expandingTildeInPath
                try FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
                dbPath = "\(appSupport)/knowledge.db"
            }

            let kb = try KnowledgeBase(path: dbPath)

            patternCount = (try? kb.patternCount()) ?? 0

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

            let pipeline = ContentIntelligencePipeline()
            self.pipeline = pipeline

            let orch = MoveOrchestrator(
                scoringEngine: engine, knowledgeBase: kb, pipeline: pipeline, settleSeconds: settleTime
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
                    context: suggestion.context, destination: suggestion.decision.destination
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
                        context: suggestion.context,
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

    func loadPinnedRules() {
        let path = pinnedRulesFilePath()
        if let manager = try? PinnedRulesManager.load(from: path) {
            pinnedRules = manager.rules
        }
    }

    func addPinnedRule(extension ext: String, destination: String) {
        var manager = PinnedRulesManager(rules: pinnedRules)
        manager.addRule(PinnedRule(fileExtension: ext, destination: destination))
        pinnedRules = manager.rules
        try? manager.save(to: pinnedRulesFilePath())
    }

    func removePinnedRule(extension ext: String) {
        var manager = PinnedRulesManager(rules: pinnedRules)
        manager.removeRule(forExtension: ext)
        pinnedRules = manager.rules
        try? manager.save(to: pinnedRulesFilePath())
    }

    private func pinnedRulesFilePath() -> String {
        let syncPath = NSString(string: dropboxSyncPath).expandingTildeInPath
        let tidyDir = "\(syncPath)/.tidy"
        if FileManager.default.fileExists(atPath: syncPath) {
            return "\(tidyDir)/pinned-rules.json"
        }
        return NSString(string: "~/Library/Application Support/Tidy/pinned-rules.json").expandingTildeInPath
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch { }
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
            sendAutoMoveNotification(filename: move.filename, destination: move.destinationPath)
        case .suggested(let candidate, let decision):
            let context = EnrichedFileContext(candidate: candidate)
            suggestions.append(Suggestion(candidate: candidate, context: context, decision: decision))
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

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendAutoMoveNotification(filename: String, destination: String) {
        guard showNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tidy"
        content.body = "Moved \(filename) → \((destination as NSString).lastPathComponent)"
        if soundOnAutoMove { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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

private extension Optional where Wrapped == Double {
    var orDefault: Double? {
        switch self {
        case .some(let v) where v != 0: return v
        default: return nil
        }
    }
}
