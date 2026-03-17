import Testing
@testable import TidyCore

@Suite("FileMover")
struct FileMoverTests {
    private func createTempDir() throws -> String {
        let path = makeTemporaryDirectory(prefix: "tidy-mover")
        try createDirectory(atPath: path)
        return path
    }

    @Test("moves file to destination")
    func basicMove() throws {
        let dir = try createTempDir()
        defer { removeItem(atPath: dir) }
        let src = "\(dir)/source.pdf"
        let destDir = "\(dir)/dest"
        try createDirectory(atPath: destDir)
        createFile(atPath: src, text: "hello")
        let mover = FileMover()
        let result = try mover.move(from: src, toDirectory: destDir)
        #expect(result.destinationPath == "\(destDir)/source.pdf")
        #expect(!fileExists(atPath: src))
        #expect(fileExists(atPath: result.destinationPath))
    }

    @Test("handles filename collision by appending number")
    func collision() throws {
        let dir = try createTempDir()
        defer { removeItem(atPath: dir) }
        let src1 = "\(dir)/report.pdf"
        let src2 = "\(dir)/incoming/report.pdf"
        let destDir = "\(dir)/docs"
        try createDirectory(atPath: "\(dir)/incoming")
        try createDirectory(atPath: destDir)
        createFile(atPath: src1, text: "v1")
        createFile(atPath: src2, text: "v2")
        let mover = FileMover()
        _ = try mover.move(from: src1, toDirectory: destDir)
        let result2 = try mover.move(from: src2, toDirectory: destDir)
        #expect(result2.destinationPath.contains("report-2.pdf"))
        #expect(fileExists(atPath: result2.destinationPath))
    }

    @Test("creates destination directory if it doesn't exist")
    func createsDir() throws {
        let dir = try createTempDir()
        defer { removeItem(atPath: dir) }
        let src = "\(dir)/file.txt"
        createFile(atPath: src, text: "data")
        let mover = FileMover()
        let result = try mover.move(from: src, toDirectory: "\(dir)/new/nested/dir")
        #expect(fileExists(atPath: result.destinationPath))
    }

    @Test("throws when source doesn't exist")
    func missingSource() throws {
        let mover = FileMover()
        #expect(throws: FileMoverError.self) {
            try mover.move(from: "/nonexistent/file.pdf", toDirectory: "/tmp")
        }
    }
}
