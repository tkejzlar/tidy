import Foundation

public struct ExtensionAffinity: Sendable {
    public let folderPath: String
    public let fileExtension: String
    public let fileCount: Int
}

public struct FolderArchaeologist: Sendable {
    public init() {}

    public func scan(roots: [String]) -> [ExtensionAffinity] {
        let fm = FileManager.default
        var folderExtCounts: [String: [String: Int]] = [:]
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      resourceValues.isRegularFile == true else { continue }
                let ext = fileURL.pathExtension.lowercased()
                guard !ext.isEmpty else { continue }
                let folder = fileURL.deletingLastPathComponent().path
                folderExtCounts[folder, default: [:]][ext, default: 0] += 1
            }
        }
        var affinities: [ExtensionAffinity] = []
        for (folder, extCounts) in folderExtCounts {
            for (ext, count) in extCounts where count >= 5 {
                affinities.append(ExtensionAffinity(folderPath: folder, fileExtension: ext, fileCount: count))
            }
        }
        return affinities.sorted { $0.fileCount > $1.fileCount }
    }

    public func confidenceBoost(fileCount: Int) -> Int {
        switch fileCount {
        case 20...: return 30
        case 5..<20: return 15
        default: return 0
        }
    }
}
