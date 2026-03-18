import Testing
@testable import TidyCore

@Suite("RulePack")
struct RulePackTests {
    @Test("round-trips through JSON")
    func jsonRoundTrip() throws {
        let pack = RulePack(
            metadata: RulePack.Metadata(
                name: "Developer Essentials",
                description: "Routes dev files",
                author: "test",
                createdAt: makeDate(timeIntervalSince1970: 1000000)
            ),
            pinnedRules: [
                RulePack.PinnedRuleEntry(fileExtension: "dmg", destination: "~/Apps/Installers")
            ],
            patterns: [
                RulePack.PatternEntry(feature: "extension", value: "js", destination: "~/Developer", weight: 5.0)
            ],
            folderTemplate: ["~/Developer", "~/Apps/Installers"]
        )
        let data = try jsonEncodeISO8601(pack)
        let decoded = try jsonDecodeISO8601(RulePack.self, from: data)
        #expect(decoded.version == 1)
        #expect(decoded.metadata.name == "Developer Essentials")
        #expect(decoded.pinnedRules.count == 1)
        #expect(decoded.pinnedRules[0].fileExtension == "dmg")
        #expect(decoded.patterns.count == 1)
        #expect(decoded.patterns[0].weight == 5.0)
        #expect(decoded.folderTemplate.count == 2)
    }

    @Test("expandedFolderTemplate expands tilde")
    func expandTilde() {
        let pack = RulePack(
            metadata: RulePack.Metadata(name: "test", description: "", author: "", createdAt: makeDate(timeIntervalSince1970: 0)),
            folderTemplate: ["~/Documents/Test", "~/Developer"]
        )
        let expanded = pack.expandedFolderTemplate()
        #expect(expanded.count == 2)
        #expect(!expanded[0].contains("~"))
        #expect(expanded[0].contains("Documents/Test"))
    }

    @Test("empty pack encodes correctly")
    func emptyPack() throws {
        let pack = RulePack(
            metadata: RulePack.Metadata(name: "Empty", description: "Nothing", author: "nobody", createdAt: makeDate(timeIntervalSince1970: 0))
        )
        let data = try jsonEncodeISO8601(pack)
        let decoded = try jsonDecodeISO8601(RulePack.self, from: data)
        #expect(decoded.pinnedRules.isEmpty)
        #expect(decoded.patterns.isEmpty)
    }
}
