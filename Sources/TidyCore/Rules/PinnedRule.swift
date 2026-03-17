// Sources/TidyCore/Rules/PinnedRule.swift
import Foundation

public struct PinnedRule: Codable, Sendable, Identifiable {
    public var id: String { fileExtension.lowercased() }
    public var fileExtension: String
    public var destination: String
    public init(fileExtension: String, destination: String) {
        self.fileExtension = fileExtension
        self.destination = destination
    }
}
