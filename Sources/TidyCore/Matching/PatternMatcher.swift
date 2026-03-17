// Sources/TidyCore/Matching/PatternMatcher.swift
import Foundation

public struct PatternMatcher: Sendable {
    private let knowledgeBase: KnowledgeBase

    private let extensionWeight: Double = 0.35
    private let tokenWeight: Double = 0.30
    private let sourceAppWeight: Double = 0.15
    private let sizeBucketWeight: Double = 0.10
    private let timeBucketWeight: Double = 0.10

    public init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    public func score(_ candidate: FileCandidate) async throws -> [ScoredDestination] {
        let allPatterns = try knowledgeBase.allPatterns()
        guard !allPatterns.isEmpty else { return [] }

        var destinationScores: [String: (score: Double, totalWeight: Double, reason: String)] = [:]

        for pattern in allPatterns {
            var featureScore: Double = 0

            if let ext = candidate.fileExtension, ext == pattern.fileExtension {
                featureScore += extensionWeight
            }

            if let tokensJSON = pattern.filenameTokens,
               let tokensData = tokensJSON.data(using: .utf8),
               let patternTokens = try? JSONDecoder().decode([String].self, from: tokensData) {
                let candidateSet = Set(candidate.filenameTokens)
                let patternSet = Set(patternTokens)
                if !patternSet.isEmpty {
                    let overlap = Double(candidateSet.intersection(patternSet).count) / Double(patternSet.count)
                    featureScore += tokenWeight * overlap
                }
            }

            if let candidateApp = candidate.sourceApp,
               let patternApp = pattern.sourceApp,
               candidateApp == patternApp {
                featureScore += sourceAppWeight
            }

            if let patternBucket = pattern.sizeBucket,
               candidate.sizeBucket.rawValue == patternBucket {
                featureScore += sizeBucketWeight
            }

            if let patternBucket = pattern.timeBucket,
               candidate.timeBucket.rawValue == patternBucket {
                featureScore += timeBucketWeight
            }

            let weightedScore = featureScore * pattern.weight
            let dest = pattern.destination
            let existing = destinationScores[dest]
            destinationScores[dest] = (
                score: (existing?.score ?? 0) + weightedScore,
                totalWeight: (existing?.totalWeight ?? 0) + pattern.weight,
                reason: "Matched \(Int(featureScore * 100))% features"
            )
        }

        let maxScore = destinationScores.values.map(\.score).max() ?? 1
        guard maxScore > 0 else { return [] }

        return destinationScores.map { dest, value in
            ScoredDestination(
                path: dest,
                confidence: min(value.score / maxScore, 1.0),
                reason: value.reason
            )
        }.sorted { $0.confidence > $1.confidence }
    }
}
