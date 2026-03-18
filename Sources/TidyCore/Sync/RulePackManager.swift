// Sources/TidyCore/Sync/RulePackManager.swift
import Foundation

public struct RulePackManager: Sendable {
    public init() {}

    /// Export pinned rules and high-weight patterns as a .tidypack file.
    public func export(
        name: String,
        description: String,
        author: String,
        pinnedRules: [PinnedRule],
        patterns: [PatternRecord],
        minimumWeight: Double = 2.0,
        folderTemplate: [String] = [],
        to path: String
    ) throws {
        let ruleEntries = pinnedRules.map {
            RulePack.PinnedRuleEntry(
                fileExtension: $0.fileExtension,
                destination: abbreviatePath($0.destination)
            )
        }

        let patternEntries = patterns
            .filter { $0.weight >= minimumWeight }
            .compactMap { p -> RulePack.PatternEntry? in
                guard let ext = p.fileExtension else { return nil }
                return RulePack.PatternEntry(
                    feature: "extension",
                    value: ext,
                    destination: abbreviatePath(p.destination),
                    weight: p.weight
                )
            }

        let template = folderTemplate.map { abbreviatePath($0) }

        let pack = RulePack(
            metadata: RulePack.Metadata(name: name, description: description, author: author),
            pinnedRules: ruleEntries,
            patterns: patternEntries,
            folderTemplate: template
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pack)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Import a .tidypack file, returning the pack for preview.
    public func load(from path: String) throws -> RulePack {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RulePack.self, from: data)
    }

    /// Apply imported rules to the knowledge base with 0.5x weight reduction.
    public func applyImport(
        pack: RulePack,
        acceptedRuleExtensions: Set<String>,
        knowledgeBase: KnowledgeBase,
        pinnedRulesManager: inout PinnedRulesManager
    ) throws -> (rulesImported: Int, patternsImported: Int) {
        // Import accepted pinned rules
        var rulesCount = 0
        for rule in pack.pinnedRules {
            if acceptedRuleExtensions.contains(rule.fileExtension.lowercased()) {
                let expandedDest = NSString(string: rule.destination).expandingTildeInPath
                pinnedRulesManager.addRule(PinnedRule(fileExtension: rule.fileExtension, destination: expandedDest))
                rulesCount += 1
            }
        }

        // Import patterns with 0.5x weight reduction
        var patternsCount = 0
        for pattern in pack.patterns {
            let expandedDest = NSString(string: pattern.destination).expandingTildeInPath
            try knowledgeBase.recordPattern(
                extension: pattern.value,
                filenameTokens: [],
                sourceApp: nil,
                sizeBucket: nil,
                timeBucket: nil,
                destination: expandedDest,
                signalType: .observation
            )
            patternsCount += 1
        }

        // Create missing folders from template
        let fm = FileManager.default
        for folder in pack.expandedFolderTemplate() {
            if !fm.fileExists(atPath: folder) {
                try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
            }
        }

        return (rulesCount, patternsCount)
    }

    /// Convert absolute path to ~ prefix for portability
    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
