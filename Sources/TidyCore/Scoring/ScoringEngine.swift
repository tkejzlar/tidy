// Sources/TidyCore/Scoring/ScoringEngine.swift
import Foundation

public final class ScoringEngine: Sendable {
    private let knowledgeBase: KnowledgeBase
    private let patternMatcher: PatternMatcher
    private let heuristicsEngine: HeuristicsEngine
    private let aiLayer: (any ScoringLayer)?

    public init(knowledgeBase: KnowledgeBase, heuristicsEngine: HeuristicsEngine) throws {
        self.knowledgeBase = knowledgeBase
        self.patternMatcher = PatternMatcher(knowledgeBase: knowledgeBase)
        self.heuristicsEngine = heuristicsEngine
        self.aiLayer = nil
    }

    public init(knowledgeBase: KnowledgeBase, heuristicsEngine: HeuristicsEngine, aiLayer: any ScoringLayer) throws {
        self.knowledgeBase = knowledgeBase
        self.patternMatcher = PatternMatcher(knowledgeBase: knowledgeBase)
        self.heuristicsEngine = heuristicsEngine
        self.aiLayer = aiLayer
    }

    public func route(_ candidate: FileCandidate) async throws -> RoutingDecision? {
        let moveCount = try knowledgeBase.totalMoveCount()

        let patternScores = try await patternMatcher.score(candidate)
        let heuristicScores = try await heuristicsEngine.score(candidate)
        let aiScores = try await aiLayer?.score(candidate) ?? []

        var allDestinations: Set<String> = []
        for s in patternScores { allDestinations.insert(s.path) }
        for s in heuristicScores { allDestinations.insert(s.path) }
        for s in aiScores { allDestinations.insert(s.path) }

        guard !allDestinations.isEmpty else { return nil }

        let useThreeLayer = !aiScores.isEmpty

        var bestDest: String = ""
        var bestScore: Double = -1
        var bestBreakdown: [String: Double] = [:]
        var bestReason: String = ""

        if useThreeLayer {
            let w = Self.threeLayerWeights(moveCount: moveCount)
            for dest in allDestinations {
                let pScore = patternScores.first(where: { $0.path == dest })?.confidence ?? 0
                let aScore = aiScores.first(where: { $0.path == dest })?.confidence ?? 0
                let hScore = heuristicScores.first(where: { $0.path == dest })?.confidence ?? 0
                let combined = w.pattern * pScore + w.ai * aScore + w.heuristic * hScore

                if combined > bestScore {
                    bestScore = combined
                    bestDest = dest
                    bestBreakdown = [
                        "pattern": w.pattern * pScore,
                        "ai": w.ai * aScore,
                        "heuristic": w.heuristic * hScore,
                    ]
                    let reasons = [
                        patternScores.first(where: { $0.path == dest })?.reason,
                        aiScores.first(where: { $0.path == dest })?.reason,
                        heuristicScores.first(where: { $0.path == dest })?.reason,
                    ].compactMap { $0 }
                    bestReason = reasons.joined(separator: "; ")
                }
            }
        } else {
            let w = Self.weights(moveCount: moveCount)
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

    public struct ThreeLayerWeights: Sendable {
        public let pattern: Double
        public let ai: Double
        public let heuristic: Double
    }

    /// Piecewise linear interpolation for 3-layer weights per DESIGN.md.
    /// Control points: (0: 0.0/0.5/0.5), (30: 0.3/0.4/0.3), (80: 0.5/0.3/0.2), (100+: 0.6/0.3/0.1)
    /// AI weight never drops below 0.3.
    public static func threeLayerWeights(moveCount: Int) -> ThreeLayerWeights {
        let m = Double(moveCount)
        let pattern: Double
        let ai: Double
        let heuristic: Double

        if m <= 0 {
            pattern = 0.0
            ai = 0.5
            heuristic = 0.5
        } else if m <= 30 {
            let t = m / 30.0
            pattern = 0.0 + t * 0.3
            ai = 0.5 + t * (0.4 - 0.5)
            heuristic = 0.5 + t * (0.3 - 0.5)
        } else if m <= 80 {
            let t = (m - 30.0) / 50.0
            pattern = 0.3 + t * (0.5 - 0.3)
            ai = 0.4 + t * (0.3 - 0.4)
            heuristic = 0.3 + t * (0.2 - 0.3)
        } else if m <= 100 {
            let t = (m - 80.0) / 20.0
            pattern = 0.5 + t * (0.6 - 0.5)
            ai = 0.3 + t * (0.3 - 0.3)
            heuristic = 0.2 + t * (0.1 - 0.2)
        } else {
            pattern = 0.6
            ai = 0.3
            heuristic = 0.1
        }

        // AI weight floor of 0.3
        let clampedAI = max(ai, 0.3)
        return ThreeLayerWeights(pattern: pattern, ai: clampedAI, heuristic: heuristic)
    }
}
