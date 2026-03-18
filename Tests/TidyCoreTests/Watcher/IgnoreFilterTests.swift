import Testing
@testable import TidyCore

@Suite("IgnoreFilter")
struct IgnoreFilterTests {
    let filter = IgnoreFilter()

    @Test("ignores dotfiles")
    func dotfiles() {
        #expect(filter.shouldIgnore(filename: ".DS_Store") == true)
        #expect(filter.shouldIgnore(filename: ".hidden") == true)
    }
    @Test("ignores partial download extensions")
    func partialDownloads() {
        #expect(filter.shouldIgnore(filename: "file.part") == true)
        #expect(filter.shouldIgnore(filename: "file.crdownload") == true)
        #expect(filter.shouldIgnore(filename: "file.download") == true)
    }
    @Test("ignores files with tmp/temp in name")
    func tempFiles() {
        #expect(filter.shouldIgnore(filename: "tmpfile.txt") == true)
        #expect(filter.shouldIgnore(filename: "data.tmp") == true)
        #expect(filter.shouldIgnore(filename: "temp-export.csv") == true)
    }
    @Test("accepts normal files")
    func normalFiles() {
        #expect(filter.shouldIgnore(filename: "report.pdf") == false)
        #expect(filter.shouldIgnore(filename: "photo.jpg") == false)
    }
    @Test("accepts files with temp as part of longer word")
    func notTempSubstring() {
        #expect(filter.shouldIgnore(filename: "contemporary-art.pdf") == false)
    }

    @Test("matches extension pattern")
    func extensionPattern() {
        #expect(filter.matchesIgnorePattern(filename: "debug.log", patterns: ["*.log"]))
        #expect(!filter.matchesIgnorePattern(filename: "readme.md", patterns: ["*.log"]))
    }

    @Test("matches prefix pattern")
    func prefixPattern() {
        #expect(filter.matchesIgnorePattern(filename: "temp_file.txt", patterns: ["temp*"]))
        #expect(!filter.matchesIgnorePattern(filename: "important.txt", patterns: ["temp*"]))
    }

    @Test("matches exact pattern")
    func exactPattern() {
        #expect(filter.matchesIgnorePattern(filename: "Thumbs.db", patterns: ["thumbs.db"]))
        #expect(!filter.matchesIgnorePattern(filename: "other.db", patterns: ["thumbs.db"]))
    }

    @Test("combined check uses both standard and folder patterns")
    func combinedCheck() {
        // Standard ignore (dotfile)
        #expect(filter.shouldIgnore(filename: ".hidden", folderPatterns: []))
        // Folder pattern
        #expect(filter.shouldIgnore(filename: "debug.log", folderPatterns: ["*.log"]))
        // Neither
        #expect(!filter.shouldIgnore(filename: "report.pdf", folderPatterns: ["*.log"]))
    }

    @Test("empty patterns matches nothing")
    func emptyPatterns() {
        #expect(!filter.matchesIgnorePattern(filename: "anything.txt", patterns: []))
    }
}
