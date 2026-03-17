import Foundation

/// Combines all day-one heuristics into a single scoring layer.
public final class HeuristicsEngine: @unchecked Sendable, ScoringLayer {
    private let screenshotDetector = ScreenshotDetector()
    private let installerDetector = InstallerDetector()
    private let recencyWeighter = RecencyWeighter()
    private let affinities: [ExtensionAffinity]
    private let clusters: [TokenCluster]
    private let screenshotDestination: String
    private let installerDestination: String

    public init(
        affinities: [ExtensionAffinity],
        clusters: [TokenCluster],
        screenshotDestination: String = "~/Pictures/Screenshots",
        installerDestination: String = "~/Downloads/_Installers"
    ) {
        self.affinities = affinities
        self.clusters = clusters
        self.screenshotDestination = screenshotDestination
        self.installerDestination = installerDestination
    }

    public func score(_ candidate: FileCandidate) async throws -> [ScoredDestination] {
        var results: [ScoredDestination] = []
        let isScreenCapture = candidate.metadata?.isScreenCapture ?? false

        // 1. Screenshot detection (deterministic, 100%)
        if let ext = candidate.fileExtension,
           ["png", "jpg", "jpeg", "tiff"].contains(ext),
           screenshotDetector.isScreenshot(filename: candidate.filename, isScreenCapture: isScreenCapture) {
            return [ScoredDestination(path: screenshotDestination, confidence: 1.0, reason: "Screenshot detected")]
        }

        // 2. Installer detection (deterministic, 100%)
        if let ext = candidate.fileExtension,
           installerDetector.isInstaller(extension: ext) {
            return [ScoredDestination(path: installerDestination, confidence: 1.0, reason: "Installer file detected by extension")]
        }

        // 3. Extension affinity from folder archaeology
        // Per DESIGN.md: +30 for 20+ files → enough to reach "suggest" tier
        if let ext = candidate.fileExtension {
            let archaeologist = FolderArchaeologist()
            let matching = affinities.filter { $0.fileExtension == ext }
            for affinity in matching.prefix(3) {
                let boost = archaeologist.confidenceBoost(fileCount: affinity.fileCount)
                let confidence: Double = switch boost {
                case 30: 0.60   // 20+ files → suggest tier
                case 15: 0.35   // 5–19 files → ask tier but close
                default: 0.10
                }
                results.append(ScoredDestination(
                    path: affinity.folderPath,
                    confidence: confidence,
                    reason: "Folder has \(affinity.fileCount) .\(ext) files"
                ))
            }
        }

        // 4. Token clustering overlap
        let clusterer = TokenClusterer()
        for cluster in clusters {
            let overlap = clusterer.overlapScore(candidateTokens: candidate.filenameTokens, cluster: cluster)
            if overlap > 0.2 {
                results.append(ScoredDestination(
                    path: cluster.folderPath,
                    confidence: overlap * 0.5,
                    reason: "Filename tokens match folder content"
                ))
            }
        }

        // Deduplicate by path, keeping highest confidence
        var bestByPath: [String: ScoredDestination] = [:]
        for result in results {
            if let existing = bestByPath[result.path] {
                if result.confidence > existing.confidence { bestByPath[result.path] = result }
            } else {
                bestByPath[result.path] = result
            }
        }
        return bestByPath.values.sorted { $0.confidence > $1.confidence }
    }
}
