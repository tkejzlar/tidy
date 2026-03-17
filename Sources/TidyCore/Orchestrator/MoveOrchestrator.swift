// Sources/TidyCore/Orchestrator/MoveOrchestrator.swift
import Foundation

public actor MoveOrchestrator {
    private let scoringEngine: ScoringEngine
    private let knowledgeBase: KnowledgeBase
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
        settleSeconds: TimeInterval = 5.0
    ) {
        self.scoringEngine = scoringEngine
        self.knowledgeBase = knowledgeBase
        self.ignoreFilter = IgnoreFilter()
        self.fileMover = FileMover()
        self.undoLog = UndoLog(knowledgeBase: knowledgeBase)
        self.signalRecorder = SignalRecorder(knowledgeBase: knowledgeBase)
        self.settleTimer = SettleTimer(settleSeconds: settleSeconds)
    }

    public func setPaused(_ paused: Bool) { isPaused = paused }
    public func setAutoMoveThreshold(_ threshold: Int) { autoMoveThreshold = threshold }
    public func setSuggestThreshold(_ threshold: Int) { suggestThreshold = threshold }

    public func processFile(_ candidate: FileCandidate) throws -> OrchestratorEvent? {
        if ignoreFilter.shouldIgnore(filename: candidate.filename) { return nil }
        if isPaused { return nil }

        guard let decision = try scoringEngine.route(candidate) else {
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
    }

    public func recordUserMove(
        filename: String, fileSize: UInt64, destination: String
    ) throws -> OrchestratorEvent? {
        if ignoreFilter.shouldIgnore(filename: filename) { return nil }
        let candidate = FileCandidate(path: "/\(filename)", fileSize: fileSize)
        try signalRecorder.recordObservation(candidate: candidate, destination: destination)
        return .observed(filename: filename, destination: destination)
    }

    public func confirmAutoMove(candidate: FileCandidate, destination: String) throws {
        try signalRecorder.recordConfirmation(candidate: candidate, destination: destination)
    }

    public func approveSuggestion(candidate: FileCandidate, destination: String) throws -> MoveRecord {
        let moveResult = try fileMover.move(from: candidate.path, toDirectory: destination)
        try undoLog.recordMove(
            filename: candidate.filename, sourcePath: candidate.path,
            destinationPath: moveResult.destinationPath, confidence: nil, wasAuto: false
        )
        try signalRecorder.recordConfirmation(candidate: candidate, destination: destination)
        return try undoLog.lastMove()!
    }

    public func redirect(
        candidate: FileCandidate, suggestedDestination: String?, chosenDestination: String
    ) throws -> MoveRecord {
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

    public func undoLastMove() throws -> MoveRecord? {
        guard let lastMove = try undoLog.lastUndoableMove() else { return nil }
        _ = try fileMover.undoMove(from: lastMove.destinationPath, to: lastMove.sourcePath)
        try undoLog.markUndone(moveId: lastMove.id!)
        return lastMove
    }
}
