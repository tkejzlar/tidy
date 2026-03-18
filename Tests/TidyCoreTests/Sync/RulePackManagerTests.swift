import Testing
@testable import TidyCore

@Suite("RulePackManager")
struct RulePackManagerTests {
    @Test("export and reimport round-trips")
    func exportImportRoundTrip() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let path = dir + "/test.tidypack"
        let manager = RulePackManager()

        let rules = [PinnedRule(fileExtension: "dmg", destination: "/Users/test/Apps")]
        try manager.export(
            name: "Test Pack",
            description: "A test",
            author: "tester",
            pinnedRules: rules,
            patterns: [],
            to: path
        )

        #expect(fileExists(atPath: path))

        let loaded = try manager.load(from: path)
        #expect(loaded.metadata.name == "Test Pack")
        #expect(loaded.pinnedRules.count == 1)
        #expect(loaded.pinnedRules[0].fileExtension == "dmg")
    }

    @Test("applyImport adds pinned rules")
    func importRules() throws {
        let pack = RulePack(
            metadata: RulePack.Metadata(name: "test", description: "", author: "", createdAt: makeDate(timeIntervalSince1970: 0)),
            pinnedRules: [
                RulePack.PinnedRuleEntry(fileExtension: "pdf", destination: "~/Documents"),
                RulePack.PinnedRuleEntry(fileExtension: "dmg", destination: "~/Apps")
            ]
        )
        let kb = try KnowledgeBase.inMemory()
        var rulesManager = PinnedRulesManager()
        let manager = RulePackManager()

        let result = try manager.applyImport(
            pack: pack,
            acceptedRuleExtensions: ["pdf"],  // only accept pdf
            knowledgeBase: kb,
            pinnedRulesManager: &rulesManager
        )

        #expect(result.rulesImported == 1)
        #expect(rulesManager.rules.count == 1)
        #expect(rulesManager.rules[0].fileExtension == "pdf")
    }

    @Test("abbreviatePath converts home directory to tilde")
    func pathAbbreviation() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-abbr")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let path = dir + "/test.tidypack"
        let manager = RulePackManager()

        // Export with a home-dir path
        let homePath = makeHomeDirectory() + "/Documents/Test"
        let rules = [PinnedRule(fileExtension: "txt", destination: homePath)]
        try manager.export(name: "test", description: "", author: "", pinnedRules: rules, patterns: [], to: path)

        let loaded = try manager.load(from: path)
        #expect(loaded.pinnedRules[0].destination.hasPrefix("~"))
    }
}
