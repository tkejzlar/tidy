import Foundation

public enum FolderRole: String, Codable, Sendable {
    case inbox
    case archive
    case watchOnly
}

public struct WatchedFolder: Codable, Sendable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public var role: FolderRole
    public var isEnabled: Bool
    public var ignorePatterns: [String]

    public init(url: URL, role: FolderRole = .inbox, isEnabled: Bool = true, ignorePatterns: [String] = []) {
        self.url = url
        self.role = role
        self.isEnabled = isEnabled
        self.ignorePatterns = ignorePatterns
    }
}
