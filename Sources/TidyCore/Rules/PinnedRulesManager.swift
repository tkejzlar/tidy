// Sources/TidyCore/Rules/PinnedRulesManager.swift
import Foundation

public struct PinnedRuleMatch: Sendable {
    public let destination: String
    public let confidence: Double
    public let rule: PinnedRule
}

public struct PinnedRulesManager: Sendable {
    public private(set) var rules: [PinnedRule]

    public init(rules: [PinnedRule] = []) { self.rules = rules }

    public func match(_ candidate: FileCandidate) -> PinnedRuleMatch? {
        guard let ext = candidate.fileExtension else { return nil }
        let extLower = ext.lowercased()
        guard let rule = rules.first(where: { $0.fileExtension.lowercased() == extLower }) else { return nil }
        return PinnedRuleMatch(destination: rule.destination, confidence: 1.0, rule: rule)
    }

    public func save(to path: String) throws {
        let data = try JSONEncoder().encode(rules)
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    public static func load(from path: String) throws -> PinnedRulesManager {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return PinnedRulesManager()
        }
        let rules = try JSONDecoder().decode([PinnedRule].self, from: data)
        return PinnedRulesManager(rules: rules)
    }

    public mutating func addRule(_ rule: PinnedRule) {
        rules.removeAll { $0.fileExtension.lowercased() == rule.fileExtension.lowercased() }
        rules.append(rule)
    }

    public mutating func removeRule(forExtension ext: String) {
        rules.removeAll { $0.fileExtension.lowercased() == ext.lowercased() }
    }
}
