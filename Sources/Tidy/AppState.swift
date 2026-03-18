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

    // Multi-folder watching (replaces single watchPath)
    var watchedFolders: [WatchedFolder] = []

    /// Backward-compatible computed property — returns the first inbox folder's path (tilde-abbreviated), or ~/Downloads.
    var watchPath: String {
        get {
            if let first = watchedFolders.first(where: { $0.role == .inbox }) {
                return first.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
            return "~/Downloads"
        }
        set {
            let expandedPath = NSString(string: newValue).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
            if let idx = watchedFolders.firstIndex(where: { $0.role == .inbox }) {
                watchedFolders[idx] = WatchedFolder(
                    url: url, role: .inbox,
                    isEnabled: watchedFolders[idx].isEnabled,
                    ignorePatterns: watchedFolders[idx].ignorePatterns
                )
            } else {
                watchedFolders.insert(WatchedFolder(url: url, role: .inbox), at: 0)
            }
            saveWatchedFolders()
            restartFileWatcher()
        }
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

    // Bulk cleanup state
    private var bulkCleanupEngine: BulkCleanupEngine?
    var isCleaningUp: Bool = false
    var cleanupProgress: (current: Int, total: Int)?
    var lastCleanupBatchId: String?

    // Sync
    public var syncBackend: SyncBackend = .local
    private var syncManager: SyncManager?
    private(set) var knowledgeBase: KnowledgeBase?

    private var orchestrator: MoveOrchestrator?
    private var pipeline: ContentIntelligencePipeline?
    private var fileWatcher: FileWatcher?
    private var watchTask: Task<Void, Never>?

    func start() async {
        // Load saved settings
        autoMoveThreshold = UserDefaults.standard.object(forKey: "autoMoveThreshold") as? Double ?? 80
        suggestThreshold = UserDefaults.standard.object(forKey: "suggestThreshold") as? Double ?? 50
        settleTime = UserDefaults.standard.object(forKey: "settleTime") as? Double ?? 5
        showNotifications = UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true
        soundOnAutoMove = UserDefaults.standard.bool(forKey: "soundOnAutoMove")
        dropboxSyncPath = UserDefaults.standard.string(forKey: "dropboxSyncPath") ?? "~/Dropbox"

        // Migrate from single watchPath to watchedFolders (or load existing)
        loadWatchedFolders()

        loadPinnedRules()

        do {
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
            self.knowledgeBase = kb

            // Load sync backend from UserDefaults
            if let backendRaw = UserDefaults.standard.string(forKey: "syncBackend"),
               let backend = SyncBackend(rawValue: backendRaw) {
                syncBackend = backend
            }
            let deviceId = DeviceIdentity.deviceId()
            syncManager = SyncManager(backend: syncBackend, deviceId: deviceId, knowledgeBase: kb, dropboxPath: dropboxSyncPath)

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

            // Create BulkCleanupEngine (needs ScoringEngine + UndoLog)
            let undoLog = UndoLog(knowledgeBase: kb)
            self.bulkCleanupEngine = BulkCleanupEngine(
                scoringEngine: engine, pipeline: pipeline, undoLog: undoLog
            )

            // Create FileWatcher with all enabled folder paths
            let paths = watchedFolders.filter(\.isEnabled).map(\.url.path)
            guard !paths.isEmpty else { return }
            let watcher = FileWatcher(paths: paths)
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

    func approveAllHighConfidence() async {
        let highConfidence = suggestions.filter { $0.decision.confidence >= 80 }
        for s in highConfidence { approve(s) }
    }

    // MARK: - Watched Folder Management

    func addWatchedFolder(_ folder: WatchedFolder) {
        guard !watchedFolders.contains(where: { $0.id == folder.id }) else { return }
        watchedFolders.append(folder)
        saveWatchedFolders()
        restartFileWatcher()
    }

    func removeWatchedFolder(at index: Int) {
        guard watchedFolders.indices.contains(index) else { return }
        watchedFolders.remove(at: index)
        saveWatchedFolders()
        restartFileWatcher()
    }

    func updateWatchedFolder(at index: Int, _ folder: WatchedFolder) {
        guard watchedFolders.indices.contains(index) else { return }
        watchedFolders[index] = folder
        saveWatchedFolders()
        restartFileWatcher()
    }

    private func saveWatchedFolders() {
        if let data = try? JSONEncoder().encode(watchedFolders) {
            UserDefaults.standard.set(data, forKey: "watchedFolders")
        }
    }

    private func loadWatchedFolders() {
        // Try loading new multi-folder format first
        if let data = UserDefaults.standard.data(forKey: "watchedFolders"),
           let folders = try? JSONDecoder().decode([WatchedFolder].self, from: data),
           !folders.isEmpty {
            watchedFolders = folders
            return
        }

        // Migrate from legacy single watchPath
        if let legacyPath = UserDefaults.standard.string(forKey: "watchPath") {
            let expandedPath = NSString(string: legacyPath).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
            watchedFolders = [WatchedFolder(url: url, role: .inbox)]
            saveWatchedFolders()
            UserDefaults.standard.removeObject(forKey: "watchPath")
            return
        }

        // Default to ~/Downloads with .inbox role
        let downloadsPath = NSString(string: "~/Downloads").expandingTildeInPath
        let url = URL(fileURLWithPath: downloadsPath)
        watchedFolders = [WatchedFolder(url: url, role: .inbox)]
        saveWatchedFolders()
    }

    private func restartFileWatcher() {
        fileWatcher?.stop()
        watchTask?.cancel()

        let paths = watchedFolders.filter(\.isEnabled).map(\.url.path)
        guard !paths.isEmpty else { return }
        let watcher = FileWatcher(paths: paths)
        self.fileWatcher = watcher
        watcher.start()

        watchTask = Task { [weak self] in
            for await event in watcher.events {
                await self?.handleFileEvent(event)
            }
        }
    }

    // MARK: - Bulk Cleanup

    func startCleanup(folder: URL) async {
        guard let engine = bulkCleanupEngine else { return }
        isCleaningUp = true
        cleanupProgress = nil

        do {
            let result = try await engine.scan(folder: folder) { [weak self] progress in
                Task { @MainActor in
                    switch progress {
                    case .scanning(let current, let total):
                        self?.cleanupProgress = (current, total)
                    case .scoring(let current, let total):
                        self?.cleanupProgress = (current, total)
                    case .complete(_):
                        self?.isCleaningUp = false
                    }
                }
            }
            lastCleanupBatchId = result.batchId
            // Add proposed moves as suggestions
            for move in result.proposed {
                suggestions.append(Suggestion(
                    candidate: move.candidate,
                    context: move.context,
                    decision: move.decision
                ))
            }
            updateIconState()
        } catch {
            isCleaningUp = false
        }
    }

    func undoLastCleanup() async {
        guard lastCleanupBatchId != nil else { return }
        // Undo all moves from the last cleanup batch via orchestrator
        guard let orchestrator else { return }
        while let undone = try? await orchestrator.undoLastMove() {
            recentMoves.removeAll { $0.id == undone.id }
            movedTodayCount = max(0, movedTodayCount - 1)
        }
        lastCleanupBatchId = nil
        updateIconState()
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

    // MARK: - Sync

    func exportSync() async {
        guard let syncManager else { return }
        do {
            let _ = try await syncManager.exportChanges(pinnedRules: pinnedRules)
        } catch {
            // Silently fail for now
        }
    }

    func importSync() async {
        guard let syncManager else { return }
        do {
            let rules = PinnedRulesManager(rules: pinnedRules)
            let (updatedRules, result) = try await syncManager.importChanges(pinnedRulesManager: rules)
            if result.patternsAdded > 0 || result.patternsUpdated > 0 || result.pinnedRulesUpdated > 0 {
                pinnedRules = updatedRules.rules
                // Could show notification here
            }
        } catch {
            // Silently fail for now
        }
    }

    func setSyncBackend(_ backend: SyncBackend) {
        syncBackend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: "syncBackend")
    }

    func exportRulePack(name: String, description: String, to path: String) throws {
        let manager = RulePackManager()
        try manager.export(
            name: name, description: description, author: DeviceIdentity.deviceId(),
            pinnedRules: pinnedRules, patterns: [],
            to: path
        )
    }

    func importRulePack(from path: String) throws -> RulePack {
        let manager = RulePackManager()
        return try manager.load(from: path)
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
        case .created(let path, let sourceFolder), .modified(let path, let sourceFolder):
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let fileSize = attrs?[.size] as? UInt64 ?? 0
            let metadata = FileMetadataExtractor().extract(from: path)
            let candidate = FileCandidate(path: path, fileSize: fileSize, metadata: metadata)

            // Determine folder role from source folder
            let role = watchedFolders.first(where: { sourceFolder?.hasPrefix($0.url.path) == true })?.role ?? .inbox

            iconState = .processing
            defer { updateIconState() }

            if let orchEvent = try? await orchestrator.processFile(candidate, folderRole: role) {
                handleOrchestratorEvent(orchEvent)
            }

        case .movedOut(let path, _):
            let filename = (path as NSString).lastPathComponent
            _ = try? await orchestrator.recordUserMove(filename: filename, fileSize: 0, destination: "unknown")

        case .renamed(let oldPath, let newPath, let sourceFolder):
            let filename = (newPath as NSString).lastPathComponent
            let destination = (newPath as NSString).deletingLastPathComponent
            let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
            let fileSize = attrs?[.size] as? UInt64 ?? 0

            // For watch-only folders, record as a learned move instead of a user move
            let role = watchedFolders.first(where: { sourceFolder?.hasPrefix($0.url.path) == true })?.role ?? .inbox
            if role == .watchOnly {
                if let orchEvent = try? await orchestrator.recordWatchOnlyMove(
                    filename: filename,
                    source: (oldPath as NSString).deletingLastPathComponent,
                    destination: destination
                ) {
                    handleOrchestratorEvent(orchEvent)
                }
            } else {
                _ = try? await orchestrator.recordUserMove(filename: filename, fileSize: fileSize, destination: destination)
            }

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
        case .learnedMove:
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
        // Count unsorted files across all enabled inbox folders
        var total = 0
        for folder in watchedFolders where folder.role == .inbox && folder.isEnabled {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) ?? []
            total += contents.filter { !$0.hasPrefix(".") }.count
        }
        unsortedCount = total
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
