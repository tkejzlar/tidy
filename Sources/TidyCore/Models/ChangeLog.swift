// Sources/TidyCore/Models/ChangeLog.swift
import Foundation

public struct ChangeLogEntry: Codable, Sendable {
    public let fileExtension: String?
    public let filenameTokens: String?
    public let sourceApp: String?
    public let sizeBucket: String?
    public let timeBucket: String?
    public let documentType: String?
    public let sourceDomain: String?
    public let sceneType: String?
    public let sourceFolder: String?
    public let destination: String
    public let signalType: String
    public let weight: Double
    public let createdAt: Date

    public init(
        fileExtension: String?, filenameTokens: String?, sourceApp: String?,
        sizeBucket: String?, timeBucket: String?, documentType: String?,
        sourceDomain: String?, sceneType: String?, sourceFolder: String?,
        destination: String, signalType: String, weight: Double, createdAt: Date
    ) {
        self.fileExtension = fileExtension
        self.filenameTokens = filenameTokens
        self.sourceApp = sourceApp
        self.sizeBucket = sizeBucket
        self.timeBucket = timeBucket
        self.documentType = documentType
        self.sourceDomain = sourceDomain
        self.sceneType = sceneType
        self.sourceFolder = sourceFolder
        self.destination = destination
        self.signalType = signalType
        self.weight = weight
        self.createdAt = createdAt
    }

    public init(from pattern: PatternRecord) {
        self.fileExtension = pattern.fileExtension
        self.filenameTokens = pattern.filenameTokens
        self.sourceApp = pattern.sourceApp
        self.sizeBucket = pattern.sizeBucket
        self.timeBucket = pattern.timeBucket
        self.documentType = pattern.documentType
        self.sourceDomain = pattern.sourceDomain
        self.sceneType = pattern.sceneType
        self.sourceFolder = pattern.sourceFolder
        self.destination = pattern.destination
        self.signalType = pattern.signalType.rawValue
        self.weight = pattern.weight
        self.createdAt = pattern.createdAt
    }
}

public struct PinnedRuleEntry: Codable, Sendable {
    public let fileExtension: String
    public let destination: String
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case fileExtension = "extension"
        case destination
        case updatedAt
    }

    public init(fileExtension: String, destination: String, updatedAt: Date?) {
        self.fileExtension = fileExtension
        self.destination = destination
        self.updatedAt = updatedAt
    }
}

public struct ChangeLog: Codable, Sendable {
    public let deviceId: String
    public let timestamp: Date
    public let patterns: [ChangeLogEntry]
    public let pinnedRules: [PinnedRuleEntry]

    public init(deviceId: String, timestamp: Date = Date(), patterns: [ChangeLogEntry], pinnedRules: [PinnedRuleEntry] = []) {
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.patterns = patterns
        self.pinnedRules = pinnedRules
    }
}
