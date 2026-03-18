import Testing
@testable import TidyCore

@Suite("ContentIntelligencePipeline")
struct ContentIntelligencePipelineTests {
    @Test("enriches text file with extracted text")
    func enrichTextFile() async throws {
        let dir = makeTemporaryDirectory(prefix: "pipeline-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }
        let path = dir + "/readme.txt"
        createFile(atPath: path, contents: "Hello world from a text file".data(using: .utf8)!)

        let candidate = FileCandidate(path: path, fileSize: 28)
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.candidate.path == path)
        #expect(context.extractedText != nil)
        #expect(context.extractedText!.contains("Hello world"))
        #expect(context.imageAnalysis == nil) // not an image
    }

    @Test("passes through candidate when no enrichment applies")
    func noEnrichment() async {
        let candidate = FileCandidate(path: "/tmp/nonexistent.xyz", fileSize: 100)
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.candidate.path == "/tmp/nonexistent.xyz")
        #expect(context.extractedText == nil)
        #expect(context.imageAnalysis == nil)
        #expect(context.downloadContext == nil)
    }

    @Test("enriches with download context from downloadURL metadata")
    func enrichWithDownloadURL() async {
        let metadata = FileMetadata(
            contentType: nil,
            downloadURL: "https://github.com/user/repo/releases/download/v1.0/test.zip",
            sourceApp: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            numberOfPages: nil,
            isScreenCapture: false,
            authors: []
        )
        let candidate = FileCandidate(path: "/tmp/test.zip", fileSize: 1024, metadata: metadata)
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.downloadContext != nil)
        #expect(context.downloadContext?.sourceCategory == .developer)
    }
}
