// Sources/TidyCore/Orchestrator/BulkCleanupEngine.swift
import Foundation

public actor BulkCleanupEngine {
    public struct CleanupResult: Sendable {
        public let batchId: String
        public let proposed: [ProposedMove]
        public let scannedCount: Int
    }

    public struct ProposedMove: Sendable {
        public let candidate: FileCandidate
        public let context: EnrichedFileContext
        public let decision: RoutingDecision
    }

    public enum CleanupProgress: Sendable {
        case scanning(current: Int, total: Int)
        case scoring(current: Int, total: Int)
        case complete(result: CleanupResult)
    }

    private let scoringEngine: ScoringEngine
    private let pipeline: ContentIntelligencePipeline
    private let fileMover: FileMover
    private let undoLog: UndoLog
    private var isCancelled = false

    public init(
        scoringEngine: ScoringEngine,
        pipeline: ContentIntelligencePipeline = ContentIntelligencePipeline(),
        fileMover: FileMover = FileMover(),
        undoLog: UndoLog
    ) {
        self.scoringEngine = scoringEngine
        self.pipeline = pipeline
        self.fileMover = fileMover
        self.undoLog = undoLog
    }

    public func cancel() { isCancelled = true }

    /// Scan a folder and propose moves based on scoring.
    public func scan(
        folder: URL,
        recursive: Bool = false,
        progressCallback: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async throws -> CleanupResult {
        isCancelled = false
        let batchId = UUID().uuidString

        let filePaths = Self.enumerateFiles(in: folder, recursive: recursive)
        let total = filePaths.count
        var proposed: [ProposedMove] = []

        // Process in batches of ~50
        let batchSize = 50
        for (index, path) in filePaths.enumerated() {
            guard !isCancelled else { break }

            if index % batchSize == 0 {
                progressCallback?(.scanning(current: index, total: total))
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let fileSize = (attrs?[.size] as? UInt64) ?? 0
            let candidate = FileCandidate(path: path, fileSize: fileSize)

            let context = await pipeline.enrich(candidate)

            guard let decision = try await scoringEngine.route(context) else { continue }

            proposed.append(ProposedMove(
                candidate: candidate,
                context: context,
                decision: decision
            ))
        }

        let result = CleanupResult(batchId: batchId, proposed: proposed, scannedCount: total)
        progressCallback?(.complete(result: result))
        return result
    }

    // MARK: - Private

    private static nonisolated func enumerateFiles(in folder: URL, recursive: Bool) -> [String] {
        let fm = FileManager.default
        var filePaths: [String] = []

        if recursive {
            if let enumerator = fm.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator {
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                          values.isRegularFile == true else { continue }
                    filePaths.append(url.path)
                }
            }
        } else {
            if let contents = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in contents {
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                          values.isRegularFile == true else { continue }
                    filePaths.append(url.path)
                }
            }
        }

        return filePaths
    }

    /// Execute proposed moves, recording them with the batch ID.
    public func execute(moves: [ProposedMove], batchId: String) async throws -> [MoveResult] {
        var results: [MoveResult] = []
        for move in moves {
            guard !isCancelled else { break }
            let result = try fileMover.move(
                from: move.candidate.path,
                toDirectory: move.decision.destination
            )
            try undoLog.recordMove(
                filename: move.candidate.filename,
                sourcePath: move.candidate.path,
                destinationPath: result.destinationPath,
                confidence: move.decision.confidence,
                wasAuto: true,
                batchId: batchId
            )
            results.append(result)
        }
        return results
    }
}
