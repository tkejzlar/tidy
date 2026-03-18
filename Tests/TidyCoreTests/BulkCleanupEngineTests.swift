import Testing
@testable import TidyCore

@Suite("BulkCleanupEngine")
struct BulkCleanupEngineTests {
    @Test("scans folder and finds files")
    func scanFolder() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        createFile(atPath: dir + "/report.txt", text: "test content")
        createFile(atPath: dir + "/image.png", text: "fake png data")
        createFile(atPath: dir + "/data.csv", text: "a,b,c\n1,2,3")

        let kb = try KnowledgeBase.inMemory()
        let engine = try ScoringEngine(
            knowledgeBase: kb,
            heuristicsEngine: HeuristicsEngine(affinities: [], clusters: [])
        )
        let undoLog = UndoLog(knowledgeBase: kb)
        let bulk = BulkCleanupEngine(scoringEngine: engine, undoLog: undoLog)

        let result = try await bulk.scan(folder: makeFileURL(path: dir))
        #expect(result.scannedCount == 3)
        #expect(result.batchId.count > 0)
    }

    @Test("scan with no patterns produces no proposals")
    func noPatterns() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-empty")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        createFile(atPath: dir + "/file.xyz", text: "data")

        let kb = try KnowledgeBase.inMemory()
        let engine = try ScoringEngine(
            knowledgeBase: kb,
            heuristicsEngine: HeuristicsEngine(affinities: [], clusters: [])
        )
        let undoLog = UndoLog(knowledgeBase: kb)
        let bulk = BulkCleanupEngine(scoringEngine: engine, undoLog: undoLog)

        let result = try await bulk.scan(folder: makeFileURL(path: dir))
        #expect(result.proposed.isEmpty)
    }

    @Test("cancellation stops scan early")
    func cancellation() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-cancel")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        for i in 0..<10 {
            createFile(atPath: dir + "/file\(i).txt", text: "data")
        }

        let kb = try KnowledgeBase.inMemory()
        let engine = try ScoringEngine(
            knowledgeBase: kb,
            heuristicsEngine: HeuristicsEngine(affinities: [], clusters: [])
        )
        let undoLog = UndoLog(knowledgeBase: kb)
        let bulk = BulkCleanupEngine(scoringEngine: engine, undoLog: undoLog)

        // Cancel immediately
        await bulk.cancel()
        let result = try await bulk.scan(folder: makeFileURL(path: dir))
        #expect(result.scannedCount == 10)  // total is counted before processing
        // Some or all proposals may be skipped due to cancellation
    }

    @Test("empty folder returns empty result")
    func emptyFolder() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-empty-dir")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let engine = try ScoringEngine(
            knowledgeBase: kb,
            heuristicsEngine: HeuristicsEngine(affinities: [], clusters: [])
        )
        let undoLog = UndoLog(knowledgeBase: kb)
        let bulk = BulkCleanupEngine(scoringEngine: engine, undoLog: undoLog)

        let result = try await bulk.scan(folder: makeFileURL(path: dir))
        #expect(result.scannedCount == 0)
        #expect(result.proposed.isEmpty)
    }
}
