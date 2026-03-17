// Sources/TidyCore/Operations/UndoLog.swift
import Foundation

public struct UndoLog: Sendable {
    private let knowledgeBase: KnowledgeBase
    public static let maxEntries = 500

    public init(knowledgeBase: KnowledgeBase) { self.knowledgeBase = knowledgeBase }

    public func recordMove(
        filename: String, sourcePath: String, destinationPath: String,
        confidence: Int?, wasAuto: Bool
    ) throws {
        try knowledgeBase.recordMove(
            filename: filename, sourcePath: sourcePath, destinationPath: destinationPath,
            confidence: confidence, wasAuto: wasAuto
        )
        try knowledgeBase.pruneOldMoves(keepLast: Self.maxEntries)
    }

    public func recentMoves(limit: Int) throws -> [MoveRecord] {
        try knowledgeBase.recentMoves(limit: min(limit, Self.maxEntries))
    }

    public func lastMove() throws -> MoveRecord? { try knowledgeBase.lastMove() }
    public func lastUndoableMove() throws -> MoveRecord? { try knowledgeBase.lastUndoableMove() }
    public func markUndone(moveId: Int64) throws { try knowledgeBase.markMoveUndone(id: moveId) }
}
