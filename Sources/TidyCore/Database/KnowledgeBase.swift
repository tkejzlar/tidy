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
        try migrator.migrate(dbQueue)
    }

    // MARK: - Patterns

    public func recordPattern(
        extension ext: String?,
        filenameTokens: [String],
        sourceApp: String?,
        sizeBucket: SizeBucket?,
        timeBucket: TimeBucket?,
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
            destination: destination,
            signalType: signalType,
            weight: signalType.defaultWeight,
            createdAt: Date()
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
        wasAuto: Bool
    ) throws {
        var record = MoveRecord(
            filename: filename,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            confidence: confidence,
            wasAuto: wasAuto,
            wasUndone: false,
            createdAt: Date()
        )
        try dbQueue.write { db in
            try record.insert(db)
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
