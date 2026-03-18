// Sources/TidyCore/Sync/SyncManager.swift
import Foundation

public actor SyncManager {
    private let backend: SyncBackend
    private let deviceId: String
    private let knowledgeBase: KnowledgeBase
    private let merger: ChangeLogMerger
    private var syncDirectory: String

    public init(backend: SyncBackend, deviceId: String, knowledgeBase: KnowledgeBase, dropboxPath: String? = nil) {
        self.backend = backend
        self.deviceId = deviceId
        self.knowledgeBase = knowledgeBase
        self.merger = ChangeLogMerger()
        self.syncDirectory = backend.syncDirectory(dropboxPath: dropboxPath)
    }

    /// Override the sync directory (useful for testing).
    public func setSyncDirectory(_ path: String) {
        syncDirectory = path
    }

    /// Export any unsynced patterns as a change log file.
    public func exportChanges(pinnedRules: [PinnedRule] = []) throws -> URL? {
        let unsynced = try knowledgeBase.unsyncedPatterns()
        guard !unsynced.isEmpty || !pinnedRules.isEmpty else { return nil }

        // Ensure sync directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: syncDirectory) {
            try fm.createDirectory(atPath: syncDirectory, withIntermediateDirectories: true)
        }

        let entries = unsynced.map { ChangeLogEntry(from: $0) }
        let ruleEntries = pinnedRules.map {
            PinnedRuleEntry(fileExtension: $0.fileExtension, destination: $0.destination, updatedAt: $0.updatedAt)
        }

        let log = ChangeLog(deviceId: deviceId, patterns: entries, pinnedRules: ruleEntries)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let filename = "changes-\(deviceId)-\(Int(Date().timeIntervalSince1970)).json"
        let url = URL(fileURLWithPath: syncDirectory).appendingPathComponent(filename)
        let data = try encoder.encode(log)
        try data.write(to: url)

        // Mark patterns as synced
        let ids = unsynced.compactMap(\.id)
        try knowledgeBase.markPatternsSynced(ids: ids)
        try knowledgeBase.updateSyncTimestamp(deviceId: deviceId, timestamp: Date())

        return url
    }

    /// Import and merge all pending change logs from other devices.
    /// Returns the updated PinnedRulesManager along with the merge result.
    public func importChanges(pinnedRulesManager: PinnedRulesManager) throws -> (PinnedRulesManager, ChangeLogMerger.MergeResult) {
        let fm = FileManager.default
        let emptyResult = ChangeLogMerger.MergeResult(patternsAdded: 0, patternsUpdated: 0, pinnedRulesUpdated: 0)
        guard fm.fileExists(atPath: syncDirectory) else {
            return (pinnedRulesManager, emptyResult)
        }

        let contents = try fm.contentsOfDirectory(atPath: syncDirectory)
        let jsonFiles = contents.filter { $0.hasPrefix("changes-") && $0.hasSuffix(".json") && !$0.contains(deviceId) }

        var totalAdded = 0
        var totalUpdated = 0
        var totalRules = 0
        var updatedManager = pinnedRulesManager

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in jsonFiles {
            let path = (syncDirectory as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path) else { continue }
            guard let log = try? decoder.decode(ChangeLog.self, from: data) else { continue }

            let result = try merger.merge(changeLog: log, into: knowledgeBase, pinnedRulesManager: &updatedManager)
            totalAdded += result.patternsAdded
            totalUpdated += result.patternsUpdated
            totalRules += result.pinnedRulesUpdated

            // Archive processed file
            let archiveDir = (syncDirectory as NSString).appendingPathComponent("archived")
            if !fm.fileExists(atPath: archiveDir) {
                try fm.createDirectory(atPath: archiveDir, withIntermediateDirectories: true)
            }
            let archivePath = (archiveDir as NSString).appendingPathComponent(file)
            try? fm.moveItem(atPath: path, toPath: archivePath)
        }

        let mergeResult = ChangeLogMerger.MergeResult(patternsAdded: totalAdded, patternsUpdated: totalUpdated, pinnedRulesUpdated: totalRules)
        return (updatedManager, mergeResult)
    }
}
