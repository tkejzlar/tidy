// Tests/TidyCoreTests/Database/KnowledgeBaseTests.swift
import Testing
@testable import TidyCore
import GRDB

@Suite("KnowledgeBase")
struct KnowledgeBaseTests {
    @Test("creates in-memory database with schema")
    func creation() throws {
        let kb = try KnowledgeBase.inMemory()
        let count = try kb.patternCount()
        #expect(count == 0)
    }

    @Test("records and retrieves patterns")
    func recordPattern() throws {
        let kb = try KnowledgeBase.inMemory()

        try kb.recordPattern(
            extension: "pdf",
            filenameTokens: ["invoice", "march"],
            sourceApp: "Safari",
            sizeBucket: .small,
            timeBucket: .morning,
            destination: "~/Documents/Finance",
            signalType: .observation
        )

        let patterns = try kb.patterns(forExtension: "pdf")
        #expect(patterns.count == 1)
        #expect(patterns[0].destination == "~/Documents/Finance")
        #expect(patterns[0].weight == 1.0)
    }

    @Test("correction signal has 3x weight")
    func correctionWeight() throws {
        let kb = try KnowledgeBase.inMemory()

        try kb.recordPattern(
            extension: "pdf",
            filenameTokens: ["report"],
            sourceApp: nil,
            sizeBucket: .medium,
            timeBucket: .afternoon,
            destination: "~/Documents/Work",
            signalType: .correction
        )

        let patterns = try kb.patterns(forExtension: "pdf")
        #expect(patterns[0].weight == 3.0)
    }

    @Test("records and retrieves moves")
    func moveLog() throws {
        let kb = try KnowledgeBase.inMemory()

        try kb.recordMove(
            filename: "report.pdf",
            sourcePath: "~/Downloads/report.pdf",
            destinationPath: "~/Documents/Work/report.pdf",
            confidence: 85,
            wasAuto: true
        )

        let moves = try kb.recentMoves(limit: 10)
        #expect(moves.count == 1)
        #expect(moves[0].filename == "report.pdf")
        #expect(moves[0].wasAuto == true)
    }

    @Test("v2 migration adds new columns and records with enriched fields")
    func migrationV2() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf",
            filenameTokens: ["invoice"],
            sourceApp: "Safari",
            sizeBucket: .medium,
            timeBucket: .morning,
            documentType: "invoice",
            sourceDomain: "email",
            sceneType: "document",
            sourceFolder: "/Users/test/Downloads",
            destination: "/Users/test/Documents/Invoices",
            signalType: .observation
        )
        let patterns = try kb.allPatterns()
        #expect(patterns.count >= 1)
        let found = patterns.first(where: { $0.documentType == "invoice" })
        #expect(found != nil)
        #expect(found?.sourceDomain == "email")
        #expect(found?.sceneType == "document")
        #expect(found?.sourceFolder == "/Users/test/Downloads")
    }

    @Test("totalMoveCount tracks history depth")
    func moveCount() throws {
        let kb = try KnowledgeBase.inMemory()
        #expect(try kb.totalMoveCount() == 0)

        try kb.recordMove(
            filename: "a.pdf", sourcePath: "/a", destinationPath: "/b",
            confidence: 90, wasAuto: true
        )
        try kb.recordMove(
            filename: "b.pdf", sourcePath: "/c", destinationPath: "/d",
            confidence: 70, wasAuto: false
        )
        #expect(try kb.totalMoveCount() == 2)
    }
}
