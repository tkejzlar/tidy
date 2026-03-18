// Sources/TidyCore/Watcher/IgnoreFilter.swift
import Foundation

public struct IgnoreFilter: Sendable {
    private static let ignoredExtensions: Set<String> = ["part", "crdownload", "download"]
    private static let tempTokens: Set<String> = ["tmp", "temp"]

    public init() {}

    public func shouldIgnore(filename: String) -> Bool {
        if filename.hasPrefix(".") { return true }
        let lower = filename.lowercased()
        let ext = (lower as NSString).pathExtension
        if Self.ignoredExtensions.contains(ext) { return true }
        let stem = ext.isEmpty ? lower : (lower as NSString).deletingPathExtension
        let tokens = stem.components(separatedBy: CharacterSet(charactersIn: "-_. "))
        for token in tokens {
            if Self.tempTokens.contains(token) { return true }
            for t in Self.tempTokens { if token.hasPrefix(t) { return true } }
        }
        if Self.tempTokens.contains(ext) { return true }
        return false
    }

    /// Check if a filename matches any of the given glob-style ignore patterns.
    /// Supports: "*.ext" (extension match), "prefix*" (prefix match), "exact" (exact match)
    public func matchesIgnorePattern(filename: String, patterns: [String]) -> Bool {
        let lowered = filename.lowercased()
        for pattern in patterns {
            let p = pattern.lowercased()
            if p.hasPrefix("*.") {
                // Extension match: "*.log" matches "debug.log"
                let ext = String(p.dropFirst(2))
                if lowered.hasSuffix("." + ext) { return true }
            } else if p.hasSuffix("*") {
                // Prefix match: "temp*" matches "temporary.txt"
                let prefix = String(p.dropLast())
                if lowered.hasPrefix(prefix) { return true }
            } else {
                // Exact match
                if lowered == p { return true }
            }
        }
        return false
    }

    /// Combined check: standard ignore rules OR per-folder patterns
    public func shouldIgnore(filename: String, folderPatterns: [String]) -> Bool {
        shouldIgnore(filename: filename) || matchesIgnorePattern(filename: filename, patterns: folderPatterns)
    }
}
