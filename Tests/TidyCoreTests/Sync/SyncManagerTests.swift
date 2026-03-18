import Testing
@testable import TidyCore

@Suite("SyncManager")
struct SyncManagerTests {
    @Test("exports unsynced patterns to JSON file")
    func exportChanges() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-mgr-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["test"], sourceApp: nil,
            sizeBucket: .medium, timeBucket: .morning,
            destination: "/docs", signalType: .observation
        )

        let manager = SyncManager(backend: .local, deviceId: "test-device", knowledgeBase: kb)
        await manager.setSyncDirectory(dir)

        let url = try await manager.exportChanges()
        #expect(url != nil)

        // Pattern should now be marked as synced
        let unsynced = try kb.unsyncedPatterns()
        #expect(unsynced.isEmpty)
    }

    @Test("no export when nothing to sync")
    func noExportWhenEmpty() async throws {
        let kb = try KnowledgeBase.inMemory()
        let manager = SyncManager(backend: .local, deviceId: "test-device", knowledgeBase: kb)
        let url = try await manager.exportChanges()
        #expect(url == nil)
    }

    @Test("imports change logs from other devices")
    func importChanges() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-import-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()

        // Create a change log file from a different device
        let entry = ChangeLogEntry(
            fileExtension: "txt", filenameTokens: nil, sourceApp: nil,
            sizeBucket: nil, timeBucket: nil, documentType: nil,
            sourceDomain: nil, sceneType: nil, sourceFolder: nil,
            destination: "/notes", signalType: "observation", weight: 1.0,
            createdAt: makeDate(timeIntervalSince1970: 1000000)
        )
        let log = ChangeLog(
            deviceId: "other-device",
            timestamp: makeDate(timeIntervalSince1970: 1000000),
            patterns: [entry]
        )
        let data = try jsonEncodeISO8601(log)
        let filePath = joinPath(dir, "changes-other-device-1000000.json")
        createFile(atPath: filePath, contents: data)

        let manager = SyncManager(backend: .local, deviceId: "test-device", knowledgeBase: kb)
        await manager.setSyncDirectory(dir)

        let pinnedManager = PinnedRulesManager()
        let (_, result) = try await manager.importChanges(pinnedRulesManager: pinnedManager)
        #expect(result.patternsAdded == 1)

        // Verify the file was archived
        let archivePath = joinPath(joinPath(dir, "archived"), "changes-other-device-1000000.json")
        #expect(fileExists(atPath: archivePath))
    }

    @Test("skips own device change logs during import")
    func skipsOwnDevice() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-skip-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()

        // Create a change log from our own device
        let entry = ChangeLogEntry(
            fileExtension: "txt", filenameTokens: nil, sourceApp: nil,
            sizeBucket: nil, timeBucket: nil, documentType: nil,
            sourceDomain: nil, sceneType: nil, sourceFolder: nil,
            destination: "/notes", signalType: "observation", weight: 1.0,
            createdAt: makeDate(timeIntervalSince1970: 1000000)
        )
        let log = ChangeLog(
            deviceId: "my-device",
            timestamp: makeDate(timeIntervalSince1970: 1000000),
            patterns: [entry]
        )
        let data = try jsonEncodeISO8601(log)
        let filePath = joinPath(dir, "changes-my-device-1000000.json")
        createFile(atPath: filePath, contents: data)

        let manager = SyncManager(backend: .local, deviceId: "my-device", knowledgeBase: kb)
        await manager.setSyncDirectory(dir)

        let pinnedManager = PinnedRulesManager()
        let (_, result) = try await manager.importChanges(pinnedRulesManager: pinnedManager)
        #expect(result.patternsAdded == 0)
    }
}
