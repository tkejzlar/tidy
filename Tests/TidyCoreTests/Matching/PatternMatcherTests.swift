// Tests/TidyCoreTests/Matching/PatternMatcherTests.swift
import Testing
@testable import TidyCore

@Suite("PatternMatcher")
struct PatternMatcherTests {
    @Test("returns empty when no patterns exist")
    func empty() async throws {
        let kb = try KnowledgeBase.inMemory()
        let matcher = PatternMatcher(knowledgeBase: kb)
        let candidate = FileCandidate(path: "/Downloads/test.pdf", fileSize: 1000)
        let results = try await matcher.score(EnrichedFileContext(candidate: candidate))
        #expect(results.isEmpty)
    }

    @Test("matches by extension")
    func extensionMatch() async throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["invoice"],
            sourceApp: nil, sizeBucket: .small, timeBucket: .morning,
            destination: "~/Documents/Finance", signalType: .observation
        )
        let matcher = PatternMatcher(knowledgeBase: kb)
        let candidate = FileCandidate(path: "/Downloads/invoice-april.pdf", fileSize: 50_000)
        let results = try await matcher.score(EnrichedFileContext(candidate: candidate))
        #expect(!results.isEmpty)
        #expect(results[0].path == "~/Documents/Finance")
    }

    @Test("higher weight patterns score higher")
    func weightedScoring() async throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["report"],
            sourceApp: nil, sizeBucket: .medium, timeBucket: .afternoon,
            destination: "~/Documents/Finance", signalType: .observation
        )
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["report"],
            sourceApp: nil, sizeBucket: .medium, timeBucket: .afternoon,
            destination: "~/Documents/Work", signalType: .correction
        )
        let matcher = PatternMatcher(knowledgeBase: kb)
        let candidate = FileCandidate(path: "/Downloads/report-q1.pdf", fileSize: 2_000_000)
        let results = try await matcher.score(EnrichedFileContext(candidate: candidate))
        #expect(results.count == 2)
        #expect(results[0].path == "~/Documents/Work")
    }

    @Test("token overlap increases score")
    func tokenOverlap() async throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["invoice", "march"],
            sourceApp: nil, sizeBucket: .small, timeBucket: .morning,
            destination: "~/Documents/Finance", signalType: .observation
        )
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["report", "quarterly"],
            sourceApp: nil, sizeBucket: .medium, timeBucket: .afternoon,
            destination: "~/Documents/Work", signalType: .observation
        )
        let matcher = PatternMatcher(knowledgeBase: kb)
        let candidate = FileCandidate(path: "/Downloads/invoice-april.pdf", fileSize: 30_000)
        let results = try await matcher.score(EnrichedFileContext(candidate: candidate))
        #expect(results[0].path == "~/Documents/Finance")
    }
}
