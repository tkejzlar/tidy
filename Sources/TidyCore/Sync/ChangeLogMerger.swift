// Sources/TidyCore/Sync/ChangeLogMerger.swift
import Foundation

public struct ChangeLogMerger: Sendable {
    public init() {}

    public struct MergeResult: Sendable {
        public let patternsAdded: Int
        public let patternsUpdated: Int
        public let pinnedRulesUpdated: Int
    }

    public func merge(
        changeLog: ChangeLog,
        into knowledgeBase: KnowledgeBase,
        pinnedRulesManager: inout PinnedRulesManager
    ) throws -> MergeResult {
        var added = 0
        var updated = 0

        let existingPatterns = try knowledgeBase.allPatterns()

        for entry in changeLog.patterns {
            // Find matching pattern by composite key
            let match = existingPatterns.first { p in
                p.fileExtension == entry.fileExtension &&
                p.filenameTokens == entry.filenameTokens &&
                p.sourceApp == entry.sourceApp &&
                p.sourceFolder == entry.sourceFolder &&
                p.destination == entry.destination
            }

            if let match = match, let matchId = match.id {
                // Sum weights, cap at 20.0
                let newWeight = min(match.weight + entry.weight, 20.0)
                try knowledgeBase.updatePatternWeight(id: matchId, weight: newWeight)
                updated += 1
            } else {
                // Insert new pattern
                let signalType = SignalType(rawValue: entry.signalType) ?? .observation
                // Parse filenameTokens from JSON string back to [String]
                var tokens: [String] = []
                if let tokensString = entry.filenameTokens,
                   let data = tokensString.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String].self, from: data) {
                    tokens = decoded
                }
                try knowledgeBase.recordPattern(
                    extension: entry.fileExtension,
                    filenameTokens: tokens,
                    sourceApp: entry.sourceApp,
                    sizeBucket: entry.sizeBucket.flatMap { SizeBucket(rawValue: $0) },
                    timeBucket: entry.timeBucket.flatMap { TimeBucket(rawValue: $0) },
                    documentType: entry.documentType,
                    sourceDomain: entry.sourceDomain,
                    sceneType: entry.sceneType,
                    sourceFolder: entry.sourceFolder,
                    destination: entry.destination,
                    signalType: signalType
                )
                added += 1
            }
        }

        // Merge pinned rules (last-write-wins by updatedAt)
        var rulesUpdated = 0
        for ruleEntry in changeLog.pinnedRules {
            let existingRule = pinnedRulesManager.rules.first {
                $0.id == ruleEntry.fileExtension.lowercased()
            }
            let shouldUpdate: Bool
            if let existing = existingRule,
               let existingDate = existing.updatedAt,
               let incomingDate = ruleEntry.updatedAt {
                shouldUpdate = incomingDate > existingDate
            } else {
                // Only add if doesn't exist yet
                shouldUpdate = existingRule == nil
            }
            if shouldUpdate {
                pinnedRulesManager.addRule(PinnedRule(
                    fileExtension: ruleEntry.fileExtension,
                    destination: ruleEntry.destination,
                    updatedAt: ruleEntry.updatedAt
                ))
                rulesUpdated += 1
            }
        }

        return MergeResult(
            patternsAdded: added,
            patternsUpdated: updated,
            pinnedRulesUpdated: rulesUpdated
        )
    }
}
