// Sources/TidyCore/Operations/FileMover.swift
import Foundation

public enum FileMoverError: Error, Sendable {
    case sourceNotFound(String)
    case moveFailed(String, underlying: Error)
}

public struct MoveResult: Sendable {
    public let sourcePath: String
    public let destinationPath: String
}

public struct FileMover: Sendable {
    public init() {}

    public func move(from sourcePath: String, toDirectory destDir: String) throws -> MoveResult {
        let fm = FileManager.default
        let destDir = NSString(string: destDir).expandingTildeInPath
        guard fm.fileExists(atPath: sourcePath) else {
            throw FileMoverError.sourceNotFound(sourcePath)
        }
        if !fm.fileExists(atPath: destDir) {
            try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let filename = sourceURL.lastPathComponent
        var destPath = (destDir as NSString).appendingPathComponent(filename)
        if fm.fileExists(atPath: destPath) {
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            var counter = 2
            while fm.fileExists(atPath: destPath) {
                let newName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
                destPath = (destDir as NSString).appendingPathComponent(newName)
                counter += 1
            }
        }
        do { try fm.moveItem(atPath: sourcePath, toPath: destPath) }
        catch { throw FileMoverError.moveFailed(sourcePath, underlying: error) }
        return MoveResult(sourcePath: sourcePath, destinationPath: destPath)
    }

    public func undoMove(from currentPath: String, to originalPath: String) throws -> MoveResult {
        let originalDir = (originalPath as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: originalDir) {
            try fm.createDirectory(atPath: originalDir, withIntermediateDirectories: true)
        }
        guard fm.fileExists(atPath: currentPath) else {
            throw FileMoverError.sourceNotFound(currentPath)
        }
        do { try fm.moveItem(atPath: currentPath, toPath: originalPath) }
        catch { throw FileMoverError.moveFailed(currentPath, underlying: error) }
        return MoveResult(sourcePath: currentPath, destinationPath: originalPath)
    }
}
