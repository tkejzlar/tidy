// Tests/TidyCoreTests/Orchestrator/MoveOrchestratorTests.swift
import Testing
@testable import TidyCore

@Suite("MoveOrchestrator")
struct MoveOrchestratorTests {
    @Test("processes a file through the scoring pipeline")
    func fullPipeline() async throws {
        let dir = makeTemporaryDirectory(prefix: "tidy-orch")
        let downloads = "\(dir)/Downloads"
        let destDir = "\(dir)/Documents/PDFs"
        try createDirectory(atPath: downloads)
        try createDirectory(atPath: destDir)
        defer { removeItem(atPath: dir) }

        for i in 1...25 { createFile(atPath: "\(destDir)/doc\(i).pdf") }

        let kb = try KnowledgeBase.inMemory()
        let affinities = FolderArchaeologist().scan(roots: [dir])
        let heuristics = HeuristicsEngine(affinities: affinities, clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb, settleSeconds: 0)

        let filePath = "\(downloads)/report.pdf"
        createFile(atPath: filePath, text: "test")
        let candidate = FileCandidate(path: filePath, fileSize: 100)
        let event = try await orchestrator.processFile(candidate)
        #expect(event != nil)
    }

    @Test("ignore filter rejects dotfiles")
    func ignoreFilter() async throws {
        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb, settleSeconds: 0)
        let candidate = FileCandidate(path: "/Downloads/.DS_Store", fileSize: 100)
        let event = try await orchestrator.processFile(candidate)
        #expect(event == nil)
    }

    @Test("paused orchestrator returns nil")
    func paused() async throws {
        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb, settleSeconds: 0)
        await orchestrator.setPaused(true)
        let candidate = FileCandidate(path: "/Downloads/report.pdf", fileSize: 1000)
        let event = try await orchestrator.processFile(candidate)
        #expect(event == nil)
    }

    @Test("records observation when file moves out of watched directory")
    func observeUserMove() async throws {
        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb, settleSeconds: 0)
        let event = try await orchestrator.recordUserMove(
            filename: "invoice.pdf", fileSize: 50_000, destination: "~/Documents/Finance"
        )
        #expect(event != nil)
        let patterns = try kb.patterns(forExtension: "pdf")
        #expect(patterns.count == 1)
        #expect(patterns[0].signalType == .observation)
        #expect(patterns[0].destination == "~/Documents/Finance")
    }

    @Test("undo reverses a move")
    func undoMove() async throws {
        let dir = makeTemporaryDirectory(prefix: "tidy-undo")
        let srcDir = "\(dir)/src"
        let destDir = "\(dir)/dest"
        try createDirectory(atPath: srcDir)
        try createDirectory(atPath: destDir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb, settleSeconds: 0)

        let destPath = "\(destDir)/file.pdf"
        createFile(atPath: destPath, text: "data")
        try kb.recordMove(filename: "file.pdf", sourcePath: "\(srcDir)/file.pdf",
            destinationPath: destPath, confidence: 90, wasAuto: true)

        let undoneRecord = try await orchestrator.undoLastMove()
        #expect(undoneRecord != nil)
        #expect(fileExists(atPath: "\(srcDir)/file.pdf"))
        #expect(!fileExists(atPath: destPath))
    }

    @Test("approveSuggestion moves file and records confirmation")
    func approve() async throws {
        let dir = makeTemporaryDirectory(prefix: "tidy-approve")
        let downloads = "\(dir)/Downloads"
        let destDir = "\(dir)/Documents"
        try createDirectory(atPath: downloads)
        try createDirectory(atPath: destDir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb, settleSeconds: 0)

        let filePath = "\(downloads)/report.pdf"
        createFile(atPath: filePath, text: "content")
        let candidate = FileCandidate(path: filePath, fileSize: 1000)
        let moveRecord = try await orchestrator.approveSuggestion(candidate: candidate, destination: destDir)
        #expect(moveRecord.filename == "report.pdf")
        #expect(fileExists(atPath: moveRecord.destinationPath))
        let patterns = try kb.patterns(forExtension: "pdf")
        #expect(patterns.first?.signalType == .confirmation)
    }

    @Test("redirect records correction when different from suggestion")
    func redirectTest() async throws {
        let dir = makeTemporaryDirectory(prefix: "tidy-redirect")
        let downloads = "\(dir)/Downloads"
        let chosenDir = "\(dir)/Finance"
        try createDirectory(atPath: downloads)
        try createDirectory(atPath: chosenDir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb, settleSeconds: 0)

        let filePath = "\(downloads)/invoice.pdf"
        createFile(atPath: filePath, text: "data")
        let candidate = FileCandidate(path: filePath, fileSize: 1000)
        let moveRecord = try await orchestrator.redirect(
            candidate: candidate, suggestedDestination: "~/Documents/Work", chosenDestination: chosenDir
        )
        #expect(fileExists(atPath: moveRecord.destinationPath))
        let patterns = try kb.patterns(forExtension: "pdf")
        let correction = patterns.first { $0.signalType == .correction }
        #expect(correction != nil)
        #expect(correction!.destination == chosenDir)
    }
}
