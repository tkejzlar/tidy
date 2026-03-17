import Testing
@testable import TidyCore

@Suite("FolderArchaeologist")
struct FolderArchaeologistTests {
    private func createTestTree() throws -> String {
        let root = makeTemporaryDirectory(prefix: "tidy-test")
        let pdfDir = "\(root)/Documents/PDFs"
        try createDirectory(atPath: pdfDir)
        for i in 1...25 { createFile(atPath: "\(pdfDir)/doc\(i).pdf") }
        let photoDir = "\(root)/Photos"
        try createDirectory(atPath: photoDir)
        for i in 1...10 { createFile(atPath: "\(photoDir)/img\(i).png") }
        return root
    }

    @Test("scans folders and builds extension affinity map")
    func scan() throws {
        let root = try createTestTree()
        defer { removeItem(atPath: root) }
        let archaeologist = FolderArchaeologist()
        let affinities = archaeologist.scan(roots: [root])
        let pdfMatches = affinities.filter { $0.fileExtension == "pdf" }
        #expect(!pdfMatches.isEmpty)
        #expect(pdfMatches[0].folderPath.hasSuffix("Documents/PDFs"))
        #expect(pdfMatches[0].fileCount == 25)
    }

    @Test("confidence boost: +30 for 20+ files, +15 for 5-19")
    func confidenceBoost() {
        let archaeologist = FolderArchaeologist()
        #expect(archaeologist.confidenceBoost(fileCount: 25) == 30)
        #expect(archaeologist.confidenceBoost(fileCount: 10) == 15)
        #expect(archaeologist.confidenceBoost(fileCount: 3) == 0)
    }
}
