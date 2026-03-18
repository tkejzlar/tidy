// Sources/TidyCore/Operations/UndoLog.swift
import Foundation

public struct UndoLog: Sendable {
    private let knowledgeBase: KnowledgeBase
    public static let maxEntries = 500

    public init(knowledgeBase: KnowledgeBase) { self.knowledgeBase = knowledgeBase }

    public func recordMove(
        filename: String, sourcePath: String, destinationPath: String,
        confidence: Int?, wasAuto: Bool, batchId: String? = nil
    ) throws {
        try knowledgeBase.recordMove(
            filename: filename, sourcePath: sourcePath, destinationPath: destinationPath,
            confidence: confidence, wasAuto: wasAuto, batchId: batchId
        )
        try knowledgeBase.pruneOldMoves(keepLast: Self.maxEntries)
    }

    public func undoBatch(_ batchId: String) throws -> [MoveRecord] {
        let moves = try knowledgeBase.undoableBatchMoves(batchId)
        for move in moves {
            guard let id = move.id else { continue }
            if FileManager.default.fileExists(atPath: move.destinationPath) {
                try knowledgeBase.markMoveUndone(id: id)
            }
        }
        return moves
    }

    public func recentMoves(limit: Int) throws -> [MoveRecord] {
        try knowledgeBase.recentMoves(limit: min(limit, Self.maxEntries))
    }

    public func lastMove() throws -> MoveRecord? { try knowledgeBase.lastMove() }
    public func lastUndoableMove() throws -> MoveRecord? { try knowledgeBase.lastUndoableMove() }
    public func markUndone(moveId: Int64) throws { try knowledgeBase.markMoveUndone(id: moveId) }
}
