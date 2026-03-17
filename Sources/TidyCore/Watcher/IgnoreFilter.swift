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
}
