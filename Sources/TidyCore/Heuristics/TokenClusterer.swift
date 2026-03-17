import Foundation

public struct TokenCluster: Sendable {
    public let folderPath: String
    public let tokens: Set<String>
}

public struct TokenClusterer: Sendable {
    public init() {}

    public func buildClusters(roots: [String]) -> [TokenCluster] {
        let fm = FileManager.default
        var folderTokens: [String: Set<String>] = [:]
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      rv.isRegularFile == true else { continue }
                let folder = fileURL.deletingLastPathComponent().path
                let stem = fileURL.deletingPathExtension().lastPathComponent
                let tokens = Self.tokenize(stem)
                folderTokens[folder, default: []].formUnion(tokens)
            }
        }
        return folderTokens.map { TokenCluster(folderPath: $0.key, tokens: $0.value) }
    }

    public func overlapScore(candidateTokens: [String], cluster: TokenCluster) -> Double {
        guard !candidateTokens.isEmpty else { return 0 }
        let matches = candidateTokens.filter { cluster.tokens.contains($0) }.count
        return Double(matches) / Double(candidateTokens.count)
    }

    static func tokenize(_ stem: String) -> Set<String> {
        Set(
            stem.components(separatedBy: CharacterSet(charactersIn: "-_. "))
                .map { $0.lowercased() }
                .filter { !$0.isEmpty && $0.count > 1 }
                .filter { !$0.allSatisfy(\.isNumber) }
        )
    }
}
