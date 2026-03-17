// Tests/TidyCoreTests/Rules/PinnedRulesManagerTests.swift
import Testing
@testable import TidyCore

@Suite("PinnedRulesManager")
struct PinnedRulesManagerTests {
    @Test("matches file by extension")
    func extensionMatch() {
        let rules = [PinnedRule(fileExtension: "pdf", destination: "~/Documents/PDFs")]
        let manager = PinnedRulesManager(rules: rules)
        let candidate = FileCandidate(path: "/Downloads/report.pdf", fileSize: 50_000)
        let match = manager.match(candidate)
        #expect(match != nil)
        #expect(match!.destination == "~/Documents/PDFs")
    }

    @Test("returns nil when no rule matches")
    func noMatch() {
        let manager = PinnedRulesManager(rules: [PinnedRule(fileExtension: "pdf", destination: "~/PDFs")])
        let candidate = FileCandidate(path: "/Downloads/photo.jpg", fileSize: 50_000)
        #expect(manager.match(candidate) == nil)
    }

    @Test("pinned rules produce 100% confidence")
    func fullConfidence() {
        let manager = PinnedRulesManager(rules: [PinnedRule(fileExtension: "dmg", destination: "~/Install")])
        let candidate = FileCandidate(path: "/Downloads/Chrome.dmg", fileSize: 100_000_000)
        #expect(manager.match(candidate)!.confidence == 1.0)
    }

    @Test("case insensitive extension matching")
    func caseInsensitive() {
        let manager = PinnedRulesManager(rules: [PinnedRule(fileExtension: "PDF", destination: "~/PDFs")])
        let candidate = FileCandidate(path: "/Downloads/report.pdf", fileSize: 50_000)
        #expect(manager.match(candidate) != nil)
    }

    @Test("saves and loads rules from JSON")
    func persistence() throws {
        let path = makeTempFilePath(prefix: "tidy-rules", extension: "json")
        defer { removeItem(atPath: path) }
        let manager = PinnedRulesManager(rules: [
            PinnedRule(fileExtension: "pdf", destination: "~/PDFs"),
            PinnedRule(fileExtension: "dmg", destination: "~/Install"),
        ])
        try manager.save(to: path)
        let loaded = try PinnedRulesManager.load(from: path)
        #expect(loaded.rules.count == 2)
        #expect(loaded.rules[0].fileExtension == "pdf")
    }

    @Test("load returns empty for nonexistent file")
    func loadMissing() throws {
        let loaded = try PinnedRulesManager.load(from: "/nonexistent/rules.json")
        #expect(loaded.rules.isEmpty)
    }
}
