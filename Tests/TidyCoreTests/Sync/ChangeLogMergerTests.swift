import Testing
@testable import TidyCore

@Suite("ChangeLogMerger")
struct ChangeLogMergerTests {
    let merger = ChangeLogMerger()

    @Test("new patterns are inserted")
    func insertsNewPatterns() throws {
        let kb = try KnowledgeBase.inMemory()
        var rulesManager = PinnedRulesManager()

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: makeDate(timeIntervalSince1970: 1000),
            patterns: [
                ChangeLogEntry(
                    fileExtension: "pdf", filenameTokens: "[\"invoice\"]",
                    sourceApp: "Safari", sizeBucket: "medium", timeBucket: "morning",
                    documentType: nil, sourceDomain: nil, sceneType: nil,
                    sourceFolder: "~/Downloads", destination: "~/Documents/Invoices",
                    signalType: "observation", weight: 1.0,
                    createdAt: makeDate(timeIntervalSince1970: 900)
                ),
                ChangeLogEntry(
                    fileExtension: "png", filenameTokens: nil,
                    sourceApp: nil, sizeBucket: nil, timeBucket: nil,
                    documentType: nil, sourceDomain: nil, sceneType: nil,
                    sourceFolder: nil, destination: "~/Pictures",
                    signalType: "observation", weight: 1.0,
                    createdAt: makeDate(timeIntervalSince1970: 950)
                )
            ]
        )

        let result = try merger.merge(changeLog: log, into: kb, pinnedRulesManager: &rulesManager)

        #expect(result.patternsAdded == 2)
        #expect(result.patternsUpdated == 0)

        let patterns = try kb.allPatterns()
        #expect(patterns.count == 2)
        #expect(patterns.contains { $0.fileExtension == "pdf" && $0.destination == "~/Documents/Invoices" })
        #expect(patterns.contains { $0.fileExtension == "png" && $0.destination == "~/Pictures" })
    }

    @Test("matching patterns get weights summed and capped at 20")
    func sumsWeightsCapped() throws {
        let kb = try KnowledgeBase.inMemory()
        var rulesManager = PinnedRulesManager()

        // Insert an existing pattern
        try kb.recordPattern(
            extension: "pdf",
            filenameTokens: ["invoice"],
            sourceApp: "Safari",
            sizeBucket: nil,
            timeBucket: nil,
            sourceFolder: "~/Downloads",
            destination: "~/Documents",
            signalType: .observation
        )

        let existing = try kb.allPatterns()
        #expect(existing.count == 1)
        #expect(existing[0].weight == 1.0)

        // Merge a matching pattern (same composite key)
        let log = ChangeLog(
            deviceId: "remote",
            timestamp: makeDate(timeIntervalSince1970: 2000),
            patterns: [
                ChangeLogEntry(
                    fileExtension: "pdf", filenameTokens: "[\"invoice\"]",
                    sourceApp: "Safari", sizeBucket: nil, timeBucket: nil,
                    documentType: nil, sourceDomain: nil, sceneType: nil,
                    sourceFolder: "~/Downloads", destination: "~/Documents",
                    signalType: "observation", weight: 2.5,
                    createdAt: makeDate(timeIntervalSince1970: 1500)
                )
            ]
        )

        let result = try merger.merge(changeLog: log, into: kb, pinnedRulesManager: &rulesManager)

        #expect(result.patternsAdded == 0)
        #expect(result.patternsUpdated == 1)

        let patterns = try kb.allPatterns()
        #expect(patterns.count == 1)
        #expect(patterns[0].weight == 3.5)
    }

    @Test("weight sum is capped at 20.0")
    func weightCapAt20() throws {
        let kb = try KnowledgeBase.inMemory()
        var rulesManager = PinnedRulesManager()

        // Insert pattern with weight near max
        try kb.recordPattern(
            extension: "zip",
            filenameTokens: [],
            sourceApp: nil,
            sizeBucket: nil,
            timeBucket: nil,
            sourceFolder: nil,
            destination: "~/Archives",
            signalType: .correction  // weight = 3.0
        )

        // Update its weight to 18.0 directly
        let patterns = try kb.allPatterns()
        try kb.updatePatternWeight(id: patterns[0].id!, weight: 18.0)

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: makeDate(timeIntervalSince1970: 3000),
            patterns: [
                ChangeLogEntry(
                    fileExtension: "zip", filenameTokens: "[]",
                    sourceApp: nil, sizeBucket: nil, timeBucket: nil,
                    documentType: nil, sourceDomain: nil, sceneType: nil,
                    sourceFolder: nil, destination: "~/Archives",
                    signalType: "observation", weight: 5.0,
                    createdAt: makeDate(timeIntervalSince1970: 2500)
                )
            ]
        )

        let result = try merger.merge(changeLog: log, into: kb, pinnedRulesManager: &rulesManager)

        #expect(result.patternsUpdated == 1)
        let updated = try kb.allPatterns()
        #expect(updated[0].weight == 20.0)
    }

    @Test("pinned rules: newer timestamp wins")
    func pinnedRuleNewerWins() throws {
        let kb = try KnowledgeBase.inMemory()
        var rulesManager = PinnedRulesManager()

        // Add existing rule with older timestamp
        rulesManager.addRule(PinnedRule(
            fileExtension: "dmg",
            destination: "~/Old",
            updatedAt: makeDate(timeIntervalSince1970: 1000)
        ))

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: makeDate(timeIntervalSince1970: 3000),
            patterns: [],
            pinnedRules: [
                PinnedRuleEntry(
                    fileExtension: "dmg",
                    destination: "~/New",
                    updatedAt: makeDate(timeIntervalSince1970: 2000)
                )
            ]
        )

        let result = try merger.merge(changeLog: log, into: kb, pinnedRulesManager: &rulesManager)

        #expect(result.pinnedRulesUpdated == 1)
        let rule = rulesManager.rules.first { $0.fileExtension.lowercased() == "dmg" }
        #expect(rule?.destination == "~/New")
    }

    @Test("pinned rules: existing rule with newer timestamp is kept")
    func pinnedRuleExistingNewerKept() throws {
        let kb = try KnowledgeBase.inMemory()
        var rulesManager = PinnedRulesManager()

        // Add existing rule with newer timestamp
        rulesManager.addRule(PinnedRule(
            fileExtension: "dmg",
            destination: "~/Current",
            updatedAt: makeDate(timeIntervalSince1970: 5000)
        ))

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: makeDate(timeIntervalSince1970: 6000),
            patterns: [],
            pinnedRules: [
                PinnedRuleEntry(
                    fileExtension: "dmg",
                    destination: "~/Outdated",
                    updatedAt: makeDate(timeIntervalSince1970: 3000)
                )
            ]
        )

        let result = try merger.merge(changeLog: log, into: kb, pinnedRulesManager: &rulesManager)

        #expect(result.pinnedRulesUpdated == 0)
        let rule = rulesManager.rules.first { $0.fileExtension.lowercased() == "dmg" }
        #expect(rule?.destination == "~/Current")
    }
}
