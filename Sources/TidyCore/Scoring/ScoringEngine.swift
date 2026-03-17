// Sources/TidyCore/Scoring/ScoringEngine.swift
import Foundation

public final class ScoringEngine: Sendable {
    private let knowledgeBase: KnowledgeBase
    private let patternMatcher: PatternMatcher
    private let heuristicsEngine: HeuristicsEngine

    public init(knowledgeBase: KnowledgeBase, heuristicsEngine: HeuristicsEngine) throws {
        self.knowledgeBase = knowledgeBase
        self.patternMatcher = PatternMatcher(knowledgeBase: knowledgeBase)
        self.heuristicsEngine = heuristicsEngine
    }

    public func route(_ candidate: FileCandidate) async throws -> RoutingDecision? {
        let moveCount = try knowledgeBase.totalMoveCount()
        let w = Self.weights(moveCount: moveCount)

        let patternScores = try await patternMatcher.score(candidate)
        let heuristicScores = try await heuristicsEngine.score(candidate)

        var allDestinations: Set<String> = []
        for s in patternScores { allDestinations.insert(s.path) }
        for s in heuristicScores { allDestinations.insert(s.path) }

        guard !allDestinations.isEmpty else { return nil }

        var bestDest: String = ""
        var bestScore: Double = -1
        var bestBreakdown: [String: Double] = [:]
        var bestReason: String = ""

        for dest in allDestinations {
            let pScore = patternScores.first(where: { $0.path == dest })?.confidence ?? 0
            let hScore = heuristicScores.first(where: { $0.path == dest })?.confidence ?? 0
            let combined = w.pattern * pScore + w.heuristic * hScore

            if combined > bestScore {
                bestScore = combined
                bestDest = dest
                bestBreakdown = [
                    "pattern": w.pattern * pScore,
                    "heuristic": w.heuristic * hScore,
                ]
                let reasons = [
                    patternScores.first(where: { $0.path == dest })?.reason,
                    heuristicScores.first(where: { $0.path == dest })?.reason,
                ].compactMap { $0 }
                bestReason = reasons.joined(separator: "; ")
            }
        }

        guard bestScore > 0 else { return nil }

        return RoutingDecision(
            destination: bestDest,
            confidence: Int(bestScore * 100),
            layerBreakdown: bestBreakdown,
            reason: bestReason
        )
    }

    // MARK: - Weight Calculation

    public struct LayerWeights: Sendable {
        public let pattern: Double
        public let heuristic: Double
    }

    /// Piecewise linear interpolation between DESIGN.md control points.
    public static func weights(moveCount: Int) -> LayerWeights {
        let m = Double(moveCount)
        let patternWeight: Double
        if m <= 0 {
            patternWeight = 0.0
        } else if m <= 30 {
            patternWeight = (m / 30.0) * 0.50
        } else if m <= 80 {
            patternWeight = 0.50 + ((m - 30.0) / 50.0) * 0.21
        } else if m <= 100 {
            patternWeight = 0.71 + ((m - 80.0) / 20.0) * 0.15
        } else {
            patternWeight = 0.86
        }
        return LayerWeights(pattern: patternWeight, heuristic: 1.0 - patternWeight)
    }
}
