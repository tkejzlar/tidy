// Sources/TidyCore/Models/RulePack.swift
import Foundation

public struct RulePack: Codable, Sendable {
    public struct Metadata: Codable, Sendable {
        public let name: String
        public let description: String
        public let author: String
        public let createdAt: Date

        public init(name: String, description: String, author: String, createdAt: Date = Date()) {
            self.name = name
            self.description = description
            self.author = author
            self.createdAt = createdAt
        }
    }

    public struct PatternEntry: Codable, Sendable {
        public let feature: String
        public let value: String
        public let destination: String
        public let weight: Double

        public init(feature: String, value: String, destination: String, weight: Double) {
            self.feature = feature
            self.value = value
            self.destination = destination
            self.weight = weight
        }
    }

    public struct PinnedRuleEntry: Codable, Sendable {
        public let fileExtension: String
        public let destination: String

        enum CodingKeys: String, CodingKey {
            case fileExtension = "extension"
            case destination
        }

        public init(fileExtension: String, destination: String) {
            self.fileExtension = fileExtension
            self.destination = destination
        }
    }

    public let version: Int
    public let metadata: Metadata
    public let pinnedRules: [PinnedRuleEntry]
    public let patterns: [PatternEntry]
    public let folderTemplate: [String]

    public init(version: Int = 1, metadata: Metadata, pinnedRules: [PinnedRuleEntry] = [], patterns: [PatternEntry] = [], folderTemplate: [String] = []) {
        self.version = version
        self.metadata = metadata
        self.pinnedRules = pinnedRules
        self.patterns = patterns
        self.folderTemplate = folderTemplate
    }

    public func expandedFolderTemplate() -> [String] {
        folderTemplate.map { NSString(string: $0).expandingTildeInPath }
    }
}
