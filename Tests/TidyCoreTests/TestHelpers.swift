// TestHelpers.swift — Foundation utilities for tests (no Testing import here)
import Foundation

func makeTemporaryDirectory(prefix: String) -> String {
    NSTemporaryDirectory() + "\(prefix)-\(UUID().uuidString)"
}

func removeItem(atPath path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

func createDirectory(atPath path: String) throws {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
}

func createFile(atPath path: String) {
    FileManager.default.createFile(atPath: path, contents: nil)
}
