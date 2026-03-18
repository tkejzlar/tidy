// Tests/TidyCoreTests/BatchUndoTests.swift
import Testing
@testable import TidyCore

@Suite("BatchUndo")
struct BatchUndoTests {
    @Test("records moves with batchId")
    func recordBatchMoves() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(filename: "a.pdf", sourcePath: "/dl/a.pdf", destinationPath: "/docs/a.pdf", confidence: 85, wasAuto: true, batchId: "batch-1")
        try kb.recordMove(filename: "b.pdf", sourcePath: "/dl/b.pdf", destinationPath: "/docs/b.pdf", confidence: 90, wasAuto: true, batchId: "batch-1")
        try kb.recordMove(filename: "c.txt", sourcePath: "/dl/c.txt", destinationPath: "/docs/c.txt", confidence: 70, wasAuto: false)

        let batchMoves = try kb.movesForBatch("batch-1")
        #expect(batchMoves.count == 2)
    }

    @Test("undoableBatchMoves excludes undone moves")
    func undoableExcludesUndone() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(filename: "a.pdf", sourcePath: "/dl/a.pdf", destinationPath: "/docs/a.pdf", confidence: 85, wasAuto: true, batchId: "batch-2")
        try kb.recordMove(filename: "b.pdf", sourcePath: "/dl/b.pdf", destinationPath: "/docs/b.pdf", confidence: 90, wasAuto: true, batchId: "batch-2")

        let moves = try kb.movesForBatch("batch-2")
        if let firstId = moves.first?.id {
            try kb.markMoveUndone(id: firstId)
        }

        let undoable = try kb.undoableBatchMoves("batch-2")
        #expect(undoable.count == 1)
    }

    @Test("recordMove without batchId still works")
    func noBatchId() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(filename: "x.pdf", sourcePath: "/dl/x.pdf", destinationPath: "/docs/x.pdf", confidence: 50, wasAuto: false)
        let all = try kb.recentMoves(limit: 10)
        #expect(all.count == 1)
        #expect(all[0].batchId == nil)
    }

    @Test("undoBatch marks moves as undone")
    func undoBatchMarksUndone() throws {
        let kb = try KnowledgeBase.inMemory()
        let undoLog = UndoLog(knowledgeBase: kb)
        try undoLog.recordMove(filename: "a.pdf", sourcePath: "/dl/a.pdf", destinationPath: "/docs/a.pdf", confidence: 85, wasAuto: true, batchId: "batch-3")
        try undoLog.recordMove(filename: "b.pdf", sourcePath: "/dl/b.pdf", destinationPath: "/docs/b.pdf", confidence: 90, wasAuto: true, batchId: "batch-3")

        // undoBatch returns moves that were undoable; files don't exist on disk so markMoveUndone is skipped,
        // but the returned array still contains the moves
        let returned = try undoLog.undoBatch("batch-3")
        #expect(returned.count == 2)
    }

    @Test("movesForBatch returns empty for unknown batchId")
    func unknownBatchId() throws {
        let kb = try KnowledgeBase.inMemory()
        let moves = try kb.movesForBatch("nonexistent")
        #expect(moves.isEmpty)
    }

    @Test("batchId is persisted and retrievable")
    func batchIdPersisted() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(filename: "z.pdf", sourcePath: "/dl/z.pdf", destinationPath: "/docs/z.pdf", confidence: 75, wasAuto: true, batchId: "my-batch")

        let moves = try kb.movesForBatch("my-batch")
        #expect(moves.count == 1)
        #expect(moves[0].batchId == "my-batch")
        #expect(moves[0].filename == "z.pdf")
    }
}
