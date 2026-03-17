// Tests/TidyCoreTests/Operations/UndoLogTests.swift
import Testing
@testable import TidyCore

@Suite("UndoLog")
struct UndoLogTests {
    @Test("records a move and retrieves it")
    func recordAndRetrieve() throws {
        let kb = try KnowledgeBase.inMemory()
        let log = UndoLog(knowledgeBase: kb)
        try log.recordMove(filename: "report.pdf", sourcePath: "/Downloads/report.pdf",
            destinationPath: "/Documents/report.pdf", confidence: 85, wasAuto: true)
        let recent = try log.recentMoves(limit: 10)
        #expect(recent.count == 1)
        #expect(recent[0].filename == "report.pdf")
    }

    @Test("marks move as undone")
    func undoMove() throws {
        let kb = try KnowledgeBase.inMemory()
        let log = UndoLog(knowledgeBase: kb)
        try log.recordMove(filename: "file.txt", sourcePath: "/a/file.txt",
            destinationPath: "/b/file.txt", confidence: 90, wasAuto: true)
        let moves = try log.recentMoves(limit: 10)
        try log.markUndone(moveId: moves[0].id!)
        let updated = try log.recentMoves(limit: 10)
        #expect(updated[0].wasUndone == true)
    }

    @Test("lastUndoableMove skips already-undone moves")
    func lastUndoableMove() throws {
        let kb = try KnowledgeBase.inMemory()
        let log = UndoLog(knowledgeBase: kb)
        try log.recordMove(filename: "first.pdf", sourcePath: "/a", destinationPath: "/b",
            confidence: 80, wasAuto: true)
        try log.recordMove(filename: "second.pdf", sourcePath: "/c", destinationPath: "/d",
            confidence: 90, wasAuto: true)
        let moves = try log.recentMoves(limit: 10)
        let secondMove = moves.first { $0.filename == "second.pdf" }!
        try log.markUndone(moveId: secondMove.id!)
        let undoable = try log.lastUndoableMove()
        #expect(undoable?.filename == "first.pdf")
    }

    @Test("prunes entries beyond 500")
    func pruning() throws {
        let kb = try KnowledgeBase.inMemory()
        let log = UndoLog(knowledgeBase: kb)
        for i in 1...505 {
            try log.recordMove(filename: "file\(i).txt", sourcePath: "/a/\(i)",
                destinationPath: "/b/\(i)", confidence: 80, wasAuto: true)
        }
        let count = try kb.totalMoveCount()
        #expect(count == 500)
        let last = try log.lastMove()
        #expect(last?.filename == "file505.txt")
    }
}
