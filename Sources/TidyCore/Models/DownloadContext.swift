import Foundation

public enum SourceCategory: String, Codable, Sendable {
    case developer, googleDrive, slack, email, appStore, browser, unknown
}

public struct DownloadContext: Sendable {
    public let sourceURL: URL?
    public let referringURL: URL?
    public let sourceCategory: SourceCategory
    public let quarantineAgent: String?
    public init(sourceURL: URL? = nil, referringURL: URL? = nil, sourceCategory: SourceCategory = .unknown, quarantineAgent: String? = nil) {
        self.sourceURL = sourceURL; self.referringURL = referringURL; self.sourceCategory = sourceCategory; self.quarantineAgent = quarantineAgent
    }
}
