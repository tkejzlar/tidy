// Sources/TidyCore/Orchestrator/MoveOrchestrator.swift
import Foundation

public actor MoveOrchestrator {
    private let scoringEngine: ScoringEngine
    private let knowledgeBase: KnowledgeBase
    private let pipeline: ContentIntelligencePipeline
    private let ignoreFilter: IgnoreFilter
    private let fileMover: FileMover
    private let undoLog: UndoLog
    private let signalRecorder: SignalRecorder
    private let settleTimer: SettleTimer
    private var autoMoveThreshold: Int = 80
    private var suggestThreshold: Int = 50
    private var isPaused: Bool = false

    public init(
        scoringEngine: ScoringEngine,
        knowledgeBase: KnowledgeBase,
        pipeline: ContentIntelligencePipeline = ContentIntelligencePipeline(),
        settleSeconds: TimeInterval = 5.0
    ) {
        self.scoringEngine = scoringEngine
        self.knowledgeBase = knowledgeBase
        self.pipeline = pipeline
        self.ignoreFilter = IgnoreFilter()
        self.fileMover = FileMover()
        self.undoLog = UndoLog(knowledgeBase: knowledgeBase)
        self.signalRecorder = SignalRecorder(knowledgeBase: knowledgeBase)
        self.settleTimer = SettleTimer(settleSeconds: settleSeconds)
    }

    public func setPaused(_ paused: Bool) { isPaused = paused }
    public func setAutoMoveThreshold(_ threshold: Int) { autoMoveThreshold = threshold }
    public func setSuggestThreshold(_ threshold: Int) { suggestThreshold = threshold }

    /// Process a file with folder role awareness.
    /// - `.inbox`: full pipeline (enrich -> score -> auto-move or suggest)
    /// - `.archive`: ignored at real-time; processed on-demand via BulkCleanupEngine
    /// - `.watchOnly`: ignored at real-time; learning happens via rename detection
    public func processFile(_ candidate: FileCandidate, folderRole: FolderRole = .inbox, folderIgnorePatterns: [String] = []) async throws -> OrchestratorEvent? {
        if ignoreFilter.shouldIgnore(filename: candidate.filename, folderPatterns: folderIgnorePatterns) { return nil }
        if isPaused { return nil }

        switch folderRole {
        case .inbox:
            let context = await pipeline.enrich(candidate)
            guard let decision = try await scoringEngine.route(context) else {
                return .newFile(candidate: candidate)
            }

            switch decision.tier {
            case .autoMove:
                let moveResult = try fileMover.move(from: candidate.path, toDirectory: decision.destination)
                try undoLog.recordMove(
                    filename: candidate.filename, sourcePath: candidate.path,
                    destinationPath: moveResult.destinationPath,
                    confidence: decision.confidence, wasAuto: true
                )
                let moveRecord = try undoLog.lastMove()!
                return .autoMoved(move: moveRecord, decision: decision)
            case .suggest:
                return .suggested(candidate: candidate, decision: decision)
            case .ask:
                return .newFile(candidate: candidate)
            }

        case .archive:
            // Archive folders only process on-demand via BulkCleanupEngine
            return nil

        case .watchOnly:
            // Watch-only folders never process files — learning happens via rename detection
            return nil
        }
    }

    /// Record a learned move from a watch-only folder when a rename pair is detected.
    public func recordWatchOnlyMove(filename: String, source: String, destination: String) throws -> OrchestratorEvent? {
        let candidate = FileCandidate(path: source + "/" + filename, fileSize: 0)
        try signalRecorder.recordObservation(candidate: candidate, destination: destination)
        return .learnedMove(filename: filename, source: source, destination: destination)
    }

    public func recordUserMove(
        filename: String, fileSize: UInt64, destination: String
    ) throws -> OrchestratorEvent? {
        if ignoreFilter.shouldIgnore(filename: filename) { return nil }
        let candidate = FileCandidate(path: "/\(filename)", fileSize: fileSize)
        try signalRecorder.recordObservation(candidate: candidate, destination: destination)
        return .observed(filename: filename, destination: destination)
    }

    // MARK: - EnrichedFileContext-based methods

    public func confirmAutoMove(context: EnrichedFileContext, destination: String) throws {
        try signalRecorder.recordConfirmation(candidate: context.candidate, destination: destination)
    }

    public func approveSuggestion(context: EnrichedFileContext, destination: String) throws -> MoveRecord {
        let candidate = context.candidate
        let moveResult = try fileMover.move(from: candidate.path, toDirectory: destination)
        try undoLog.recordMove(
            filename: candidate.filename, sourcePath: candidate.path,
            destinationPath: moveResult.destinationPath, confidence: nil, wasAuto: false
        )
        try signalRecorder.recordConfirmation(candidate: candidate, destination: destination)
        return try undoLog.lastMove()!
    }

    public func redirect(
        context: EnrichedFileContext, suggestedDestination: String?, chosenDestination: String
    ) throws -> MoveRecord {
        let candidate = context.candidate
        let moveResult = try fileMover.move(from: candidate.path, toDirectory: chosenDestination)
        try undoLog.recordMove(
            filename: candidate.filename, sourcePath: candidate.path,
            destinationPath: moveResult.destinationPath, confidence: nil, wasAuto: false
        )
        if let suggested = suggestedDestination, suggested != chosenDestination {
            try signalRecorder.recordCorrection(
                candidate: candidate, wrongDestination: suggested, correctDestination: chosenDestination
            )
        } else {
            try signalRecorder.recordObservation(candidate: candidate, destination: chosenDestination)
        }
        return try undoLog.lastMove()!
    }

    // MARK: - Legacy FileCandidate-based methods (backward compatibility)

    public func confirmAutoMove(candidate: FileCandidate, destination: String) throws {
        try confirmAutoMove(context: EnrichedFileContext(candidate: candidate), destination: destination)
    }

    public func approveSuggestion(candidate: FileCandidate, destination: String) throws -> MoveRecord {
        try approveSuggestion(context: EnrichedFileContext(candidate: candidate), destination: destination)
    }

    public func redirect(
        candidate: FileCandidate, suggestedDestination: String?, chosenDestination: String
    ) throws -> MoveRecord {
        try redirect(context: EnrichedFileContext(candidate: candidate), suggestedDestination: suggestedDestination, chosenDestination: chosenDestination)
    }

    public func undoLastMove() throws -> MoveRecord? {
        guard let lastMove = try undoLog.lastUndoableMove() else { return nil }
        _ = try fileMover.undoMove(from: lastMove.destinationPath, to: lastMove.sourcePath)
        try undoLog.markUndone(moveId: lastMove.id!)
        return lastMove
    }
}
