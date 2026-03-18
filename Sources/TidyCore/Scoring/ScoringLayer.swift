import Foundation

/// Protocol for intelligence layers that score file destinations.
public protocol ScoringLayer: Sendable {
    func score(_ context: EnrichedFileContext) async throws -> [ScoredDestination]
}
