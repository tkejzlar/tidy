// Sources/TidyCore/Database/KnowledgeBase.swift
import Foundation
import GRDB

public final class KnowledgeBase: Sendable {
    private let dbQueue: DatabaseQueue

    /// Create a KnowledgeBase backed by a file at the given path.
    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    /// Create an in-memory KnowledgeBase (for testing).
    public static func inMemory() throws -> KnowledgeBase {
        try KnowledgeBase()
    }

    private init() throws {
        dbQueue = try DatabaseQueue()
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "pattern_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("fileExtension", .text)
                t.column("filenameTokens", .text)
                t.column("sourceApp", .text)
                t.column("sizeBucket", .text)
                t.column("timeBucket", .text)
                t.column("destination", .text).notNull()
                t.column("signalType", .text).notNull()
                t.column("weight", .double).notNull().defaults(to: 1.0)
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(table: "move_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filename", .text).notNull()
                t.column("sourcePath", .text).notNull()
                t.column("destinationPath", .text).notNull()
                t.column("confidence", .integer)
                t.column("wasAuto", .boolean).notNull().defaults(to: false)
                t.column("wasUndone", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "pattern_records") { t in
                t.add(column: "documentType", .text)
                t.add(column: "sourceDomain", .text)
                t.add(column: "sceneType", .text)
                t.add(column: "sourceFolder", .text)
                t.add(column: "syncedAt", .double)
            }
            try db.alter(table: "move_records") { t in
                t.add(column: "batchId", .text)
            }
        }
        migrator.registerMigration("v3") { db in
            try db.create(table: "sync_metadata") { t in
                t.column("deviceId", .text).primaryKey()
                t.column("lastSyncTimestamp", .double)
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - Sync

    public func unsyncedPatterns() throws -> [PatternRecord] {
        try dbQueue.read { db in
            try PatternRecord
                .filter(Column("syncedAt") == nil)
                .fetchAll(db)
        }
    }

    public func markPatternsSynced(ids: [Int64], at date: Date = Date()) throws {
        try dbQueue.write { db in
            for id in ids {
                try db.execute(
                    sql: "UPDATE pattern_records SET syncedAt = ? WHERE id = ?",
                    arguments: [date.timeIntervalSince1970, id]
                )
            }
        }
    }

    public func updateSyncTimestamp(deviceId: String, timestamp: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_metadata (deviceId, lastSyncTimestamp) VALUES (?, ?)",
                arguments: [deviceId, timestamp.timeIntervalSince1970]
            )
        }
    }

    public func lastSyncTimestamp(deviceId: String) throws -> Date? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db,
                sql: "SELECT lastSyncTimestamp FROM sync_metadata WHERE deviceId = ?",
                arguments: [deviceId]
            )
            guard let timestamp = row?["lastSyncTimestamp"] as? Double else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
    }

    // MARK: - Patterns

    public func recordPattern(
        extension ext: String?,
        filenameTokens: [String],
        sourceApp: String?,
        sizeBucket: SizeBucket?,
        timeBucket: TimeBucket?,
        documentType: String? = nil,
        sourceDomain: String? = nil,
        sceneType: String? = nil,
        sourceFolder: String? = nil,
        destination: String,
        signalType: SignalType
    ) throws {
        let tokensJSON = try? JSONEncoder().encode(filenameTokens)
        let tokensString = tokensJSON.flatMap { String(data: $0, encoding: .utf8) }

        var record = PatternRecord(
            fileExtension: ext,
            filenameTokens: tokensString,
            sourceApp: sourceApp,
            sizeBucket: sizeBucket?.rawValue,
            timeBucket: timeBucket?.rawValue,
            documentType: documentType,
            sourceDomain: sourceDomain,
            sceneType: sceneType,
            sourceFolder: sourceFolder,
            destination: destination,
            signalType: signalType,
            weight: signalType.defaultWeight,
            createdAt: Date(),
            syncedAt: nil
        )
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    public func patterns(forExtension ext: String) throws -> [PatternRecord] {
        try dbQueue.read { db in
            try PatternRecord
                .filter(Column("fileExtension") == ext)
                .fetchAll(db)
        }
    }

    public func updatePatternWeight(id: Int64, weight: Double) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE pattern_records SET weight = ? WHERE id = ?", arguments: [weight, id])
        }
    }

    public func allPatterns() throws -> [PatternRecord] {
        try dbQueue.read { db in
            try PatternRecord.fetchAll(db)
        }
    }

    public func patternCount() throws -> Int {
        try dbQueue.read { db in
            try PatternRecord.fetchCount(db)
        }
    }

    // MARK: - Moves

    public func recordMove(
        filename: String,
        sourcePath: String,
        destinationPath: String,
        confidence: Int?,
        wasAuto: Bool,
        batchId: String? = nil
    ) throws {
        var record = MoveRecord(
            filename: filename,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            confidence: confidence,
            wasAuto: wasAuto,
            wasUndone: false,
            batchId: batchId,
            createdAt: Date()
        )
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    public func movesForBatch(_ batchId: String) throws -> [MoveRecord] {
        try dbQueue.read { db in
            try MoveRecord
                .filter(Column("batchId") == batchId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func undoableBatchMoves(_ batchId: String) throws -> [MoveRecord] {
        try dbQueue.read { db in
            try MoveRecord
                .filter(Column("batchId") == batchId)
                .filter(Column("wasUndone") == false)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func recentMoves(limit: Int) throws -> [MoveRecord] {
        try dbQueue.read { db in
            try MoveRecord
                .order(Column("createdAt").desc, Column("id").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func totalMoveCount() throws -> Int {
        try dbQueue.read { db in
            try MoveRecord.fetchCount(db)
        }
    }

    public func markMoveUndone(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE move_records SET wasUndone = 1 WHERE id = ?", arguments: [id])
        }
    }

    public func lastMove() throws -> MoveRecord? {
        try dbQueue.read { db in
            try MoveRecord.order(Column("createdAt").desc, Column("id").desc).fetchOne(db)
        }
    }

    public func lastUndoableMove() throws -> MoveRecord? {
        try dbQueue.read { db in
            try MoveRecord
                .filter(Column("wasUndone") == false)
                .order(Column("createdAt").desc, Column("id").desc)
                .fetchOne(db)
        }
    }

    public func pruneOldMoves(keepLast: Int) throws {
        try dbQueue.write { db in
            let count = try MoveRecord.fetchCount(db)
            if count > keepLast {
                try db.execute(
                    sql: """
                        DELETE FROM move_records WHERE id NOT IN (
                            SELECT id FROM move_records ORDER BY createdAt DESC, id DESC LIMIT ?
                        )
                        """,
                    arguments: [keepLast]
                )
            }
        }
    }
}
