// Sources/TidyCore/Models/MoveRecord.swift
import Foundation
import GRDB

public struct MoveRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var filename: String
    public var sourcePath: String
    public var destinationPath: String
    public var confidence: Int?
    public var wasAuto: Bool
    public var wasUndone: Bool
    public var createdAt: Date
    public var batchId: String?

    public static let databaseTableName = "move_records"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
