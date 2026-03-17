// Tests/TidyCoreTests/Scoring/ScoringEngineTests.swift
import Testing
@testable import TidyCore

@Suite("ScoringEngine")
struct ScoringEngineTests {
    @Test("weights shift based on move count — matches DESIGN.md table")
    func weightShifting() {
        let w0 = ScoringEngine.weights(moveCount: 0)
        #expect(abs(w0.pattern - 0.0) < 0.01)
        #expect(abs(w0.heuristic - 1.0) < 0.01)

        let w30 = ScoringEngine.weights(moveCount: 30)
        #expect(abs(w30.pattern - 0.50) < 0.05)
        #expect(abs(w30.heuristic - 0.50) < 0.05)

        let w80 = ScoringEngine.weights(moveCount: 80)
        #expect(abs(w80.pattern - 0.71) < 0.05)
        #expect(abs(w80.heuristic - 0.29) < 0.05)

        let w100 = ScoringEngine.weights(moveCount: 100)
        #expect(abs(w100.pattern - 0.86) < 0.05)
        #expect(abs(w100.heuristic - 0.14) < 0.05)
    }

    @Test("combines pattern matcher and heuristics into a routing decision")
    func layerCombination() async throws {
        let kb = try KnowledgeBase.inMemory()
        for i in 1...50 {
            try kb.recordPattern(
                extension: "pdf", filenameTokens: ["report"],
                sourceApp: nil, sizeBucket: .medium, timeBucket: .afternoon,
                destination: "~/Documents/Reports", signalType: .observation
            )
            try kb.recordMove(
                filename: "report\(i).pdf", sourcePath: "/a", destinationPath: "/b",
                confidence: 90, wasAuto: true
            )
        }
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let candidate = FileCandidate(path: "/Downloads/report-q2.pdf", fileSize: 2_000_000)
        let decision = try await engine.route(candidate)
        #expect(decision != nil)
        #expect(decision!.destination == "~/Documents/Reports")
        #expect(decision!.confidence > 0)
    }

    @Test("returns nil when no layer has suggestions")
    func noSuggestions() async throws {
        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let candidate = FileCandidate(path: "/Downloads/mystery-file.xyz", fileSize: 100)
        let decision = try await engine.route(candidate)
        #expect(decision == nil)
    }

    @Test("confidence maps to correct tiers")
    func tiers() {
        #expect(ConfidenceTier(confidence: 95) == .autoMove)
        #expect(ConfidenceTier(confidence: 80) == .autoMove)
        #expect(ConfidenceTier(confidence: 65) == .suggest)
        #expect(ConfidenceTier(confidence: 50) == .suggest)
        #expect(ConfidenceTier(confidence: 49) == .ask)
        #expect(ConfidenceTier(confidence: 0) == .ask)
    }
}
