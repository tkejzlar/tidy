// Sources/TidyCore/Models/PatternRecord.swift
import Foundation
import GRDB

public enum SignalType: String, Codable, Sendable, DatabaseValueConvertible {
    case observation
    case correction
    case confirmation

    public var defaultWeight: Double {
        switch self {
        case .observation:   return 1.0
        case .correction:    return 3.0
        case .confirmation:  return 1.0
        }
    }
}

public struct PatternRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var fileExtension: String?
    public var filenameTokens: String?    // JSON-encoded [String]
    public var sourceApp: String?
    public var sizeBucket: String?
    public var timeBucket: String?
    public var destination: String
    public var signalType: SignalType
    public var weight: Double
    public var createdAt: Date

    public static let databaseTableName = "pattern_records"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
