import Foundation

public struct DownloadContextExtractor: Sendable {
    private let categoryMapper = SourceCategoryMapper()

    public init() {}

    /// Extract download context from a file's extended attributes.
    public func extract(fromPath path: String) -> DownloadContext {
        let whereFroms = readWhereFroms(path: path)
        let quarantineRaw = readXattr(path: path, name: "com.apple.quarantine")
        let quarantineAgent = Self.parseQuarantineAgent(from: quarantineRaw)

        let sourceURLString = whereFroms.first
        let referringURLString = whereFroms.count > 1 ? whereFroms[1] : nil

        return contextFromURLStrings(
            source: sourceURLString,
            referring: referringURLString,
            quarantineAgent: quarantineAgent
        )
    }

    /// Build context from a URL string (for testing or when URL is already known).
    public func contextFromURL(_ urlString: String?) -> DownloadContext {
        return contextFromURLStrings(source: urlString, referring: nil, quarantineAgent: nil)
    }

    private func contextFromURLStrings(source: String?, referring: String?, quarantineAgent: String?) -> DownloadContext {
        guard let source, let url = URL(string: source) else {
            return DownloadContext(sourceCategory: .unknown, quarantineAgent: quarantineAgent)
        }
        let category = categoryMapper.categorize(url: url)
        let referringURL = referring.flatMap { URL(string: $0) }
        return DownloadContext(
            sourceURL: url,
            referringURL: referringURL,
            sourceCategory: category,
            quarantineAgent: quarantineAgent
        )
    }

    /// Parse the agent name from a quarantine xattr value.
    /// Format: flags;timestamp;agentName;uuid
    public static func parseQuarantineAgent(from value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let agent = String(parts[2])
        return agent.isEmpty ? nil : agent
    }

    private func readWhereFroms(path: String) -> [String] {
        guard let data = readXattrData(path: path, name: "com.apple.metadata:kMDItemWhereFroms") else {
            return []
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let urls = plist as? [String] else {
            return []
        }
        return urls
    }

    private func readXattr(path: String, name: String) -> String? {
        guard let data = readXattrData(path: path, name: name) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readXattrData(path: String, name: String) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        let result = getxattr(path, name, &buffer, length, 0, 0)
        guard result > 0 else { return nil }
        return Data(buffer[0..<result])
    }
}
