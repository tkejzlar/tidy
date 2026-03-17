import Foundation

/// Protocol for intelligence layers that score file destinations.
public protocol ScoringLayer: Sendable {
    func score(_ candidate: FileCandidate) async throws -> [ScoredDestination]
}
