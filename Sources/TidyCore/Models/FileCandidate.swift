// Sources/TidyCore/Models/FileCandidate.swift
import Foundation

public struct FileCandidate: Sendable {
    public let path: String
    public let filename: String
    public let fileExtension: String?
    public let filenameTokens: [String]
    public let fileSize: UInt64
    public let sizeBucket: SizeBucket
    public let timeBucket: TimeBucket
    public let sourceApp: String?
    public let downloadURL: String?
    public let metadata: FileMetadata?

    public init(
        path: String,
        fileSize: UInt64,
        metadata: FileMetadata? = nil,
        date: Date = Date()
    ) {
        self.path = path
        self.fileSize = fileSize
        self.metadata = metadata
        self.sourceApp = metadata?.sourceApp
        self.downloadURL = metadata?.downloadURL
        self.sizeBucket = SizeBucket(bytes: fileSize)
        self.timeBucket = TimeBucket(date: date)

        let url = URL(fileURLWithPath: path)
        self.filename = url.lastPathComponent

        let ext = url.pathExtension
        self.fileExtension = ext.isEmpty ? nil : ext.lowercased()

        // Tokenize: strip extension, split on delimiters, lowercase
        // Filter out pure-numeric tokens (dates, years) — consistent with TokenClusterer
        let stem = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        self.filenameTokens = stem
            .components(separatedBy: CharacterSet(charactersIn: "-_. "))
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && $0.count > 1 }
            .filter { !$0.allSatisfy(\.isNumber) }
    }
}
