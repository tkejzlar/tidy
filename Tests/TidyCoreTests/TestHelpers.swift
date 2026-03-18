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

func createFile(atPath path: String, contents: Data) {
    FileManager.default.createFile(atPath: path, contents: contents)
}

func createFile(atPath path: String, text: String) {
    FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
}

func fileExists(atPath path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

func makeTempFilePath(prefix: String, extension ext: String) -> String {
    NSTemporaryDirectory() + "\(prefix)-\(UUID().uuidString).\(ext)"
}

func writeText(_ text: String, toFile path: String) throws {
    try (text as NSString).write(toFile: path, atomically: true, encoding: String.Encoding.utf8.rawValue)
}

func makeURL(string: String) -> URL {
    URL(string: string)!
}
