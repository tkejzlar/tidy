import Testing
@testable import TidyCore

@Suite("ContentExtractor")
struct ContentExtractorTests {
    let extractor = ContentExtractor()

    @Test("extracts text from .txt file")
    func txtFile() throws {
        let path = makeTempFilePath(prefix: "tidy-ce", extension: "txt")
        try writeText("This is a sample invoice from Acme Corp.", toFile: path)
        defer { removeItem(atPath: path) }
        let extracted = extractor.extractText(from: path, maxWords: 500)
        #expect(extracted != nil)
        #expect(extracted!.contains("invoice"))
    }

    @Test("extracts text from .md file")
    func mdFile() throws {
        let path = makeTempFilePath(prefix: "tidy-ce", extension: "md")
        try writeText("# Meeting Notes\n\nDiscussed Q1 revenue.", toFile: path)
        defer { removeItem(atPath: path) }
        let extracted = extractor.extractText(from: path, maxWords: 500)
        #expect(extracted != nil)
        #expect(extracted!.contains("Meeting"))
    }

    @Test("extracts text from .csv file")
    func csvFile() throws {
        let path = makeTempFilePath(prefix: "tidy-ce", extension: "csv")
        try writeText("Date,Amount\n2026-03-01,150.00", toFile: path)
        defer { removeItem(atPath: path) }
        let extracted = extractor.extractText(from: path, maxWords: 500)
        #expect(extracted != nil)
        #expect(extracted!.contains("Amount"))
    }

    @Test("respects maxWords limit")
    func maxWords() throws {
        let path = makeTempFilePath(prefix: "tidy-ce", extension: "txt")
        let words = (1...1000).map { "word\($0)" }.joined(separator: " ")
        try writeText(words, toFile: path)
        defer { removeItem(atPath: path) }
        let extracted = extractor.extractText(from: path, maxWords: 10)
        #expect(extracted != nil)
        #expect(extracted!.split(separator: " ").count <= 10)
    }

    @Test("returns nil for unsupported extensions")
    func unsupported() {
        #expect(extractor.extractText(from: "/fake/file.dmg", maxWords: 500) == nil)
    }

    @Test("returns nil for nonexistent file")
    func nonexistent() {
        #expect(extractor.extractText(from: "/nonexistent/file.txt", maxWords: 500) == nil)
    }

    @Test("reports supported extensions")
    func supportedExtensions() {
        #expect(ContentExtractor.isTextExtractable(extension: "pdf"))
        #expect(ContentExtractor.isTextExtractable(extension: "txt"))
        #expect(ContentExtractor.isTextExtractable(extension: "md"))
        #expect(ContentExtractor.isTextExtractable(extension: "csv"))
        #expect(!ContentExtractor.isTextExtractable(extension: "png"))
        #expect(!ContentExtractor.isTextExtractable(extension: "dmg"))
    }
}
