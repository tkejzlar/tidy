// Sources/TidyCore/Rules/PinnedRule.swift
import Foundation

public struct PinnedRule: Codable, Sendable, Identifiable {
    public var id: String { fileExtension.lowercased() }
    public let fileExtension: String
    public let destination: String
    public var updatedAt: Date?

    public init(fileExtension: String, destination: String, updatedAt: Date? = nil) {
        self.fileExtension = fileExtension
        self.destination = destination
        self.updatedAt = updatedAt
    }
}
