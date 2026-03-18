import Foundation

public struct SourceCategoryMapper: Sendable {
    private static let mappings: [(suffix: String, category: SourceCategory)] = [
        ("github.com", .developer),
        ("githubusercontent.com", .developer),
        ("gitlab.com", .developer),
        ("bitbucket.org", .developer),
        ("drive.google.com", .googleDrive),
        ("docs.google.com", .googleDrive),
        ("slack-files.com", .slack),
        ("files.slack.com", .slack),
        ("slack.com", .slack),
        ("mail.google.com", .email),
        ("outlook.live.com", .email),
        ("outlook.office.com", .email),
        ("figma.com", .developer),
        ("apps.apple.com", .appStore),
    ]

    public init() {}

    public func categorize(domain: String) -> SourceCategory {
        let lowered = domain.lowercased()
        for mapping in Self.mappings {
            if lowered == mapping.suffix || lowered.hasSuffix("." + mapping.suffix) {
                return mapping.category
            }
        }
        return .browser
    }

    public func categorize(url: URL) -> SourceCategory {
        guard let host = url.host() else { return .unknown }
        return categorize(domain: host)
    }
}
