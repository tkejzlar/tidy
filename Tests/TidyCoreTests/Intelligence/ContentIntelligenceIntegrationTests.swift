import Testing
@testable import TidyCore

@Suite("Content Intelligence Integration")
struct ContentIntelligenceIntegrationTests {
    @Test("full pipeline: text file enriched and scored")
    func endToEndTextFile() async throws {
        let dir = makeTemporaryDirectory(prefix: "integration")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let filePath = dir + "/report.txt"
        createFile(atPath: filePath, contents: "Quarterly financial report Q1 2026".data(using: .utf8)!)

        let kb = try KnowledgeBase.inMemory()
        // Record a pattern so scoring has something to match
        try kb.recordPattern(
            extension: "txt",
            filenameTokens: ["report"],
            sourceApp: nil,
            sizeBucket: .tiny,
            timeBucket: .morning,
            destination: "/Users/test/Documents/Reports",
            signalType: .observation
        )
        // Record enough moves so pattern weight > 0 (requires moveCount > 0)
        for i in 0..<35 {
            try kb.recordMove(
                filename: "file\(i).txt",
                sourcePath: "/tmp/file\(i).txt",
                destinationPath: "/Users/test/Documents/Reports/file\(i).txt",
                confidence: 80,
                wasAuto: true
            )
        }

        let engine = try ScoringEngine(
            knowledgeBase: kb,
            heuristicsEngine: HeuristicsEngine(affinities: [], clusters: [])
        )
        let pipeline = ContentIntelligencePipeline()

        let candidate = FileCandidate(path: filePath, fileSize: 35)
        let context = await pipeline.enrich(candidate)

        // Verify enrichment happened
        #expect(context.extractedText != nil)
        #expect(context.extractedText!.contains("financial report"))

        // Score with enriched context
        let decision = try await engine.route(context)
        #expect(decision != nil)
        #expect(decision!.destination == "/Users/test/Documents/Reports")
    }

    @Test("pipeline enriches with download context from metadata URL")
    func enrichmentWithDownloadURL() async throws {
        let metadata = FileMetadata(
            contentType: nil,
            downloadURL: "https://github.com/user/repo/releases/download/v1.0/tool.zip",
            sourceApp: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            numberOfPages: nil,
            isScreenCapture: false,
            authors: []
        )
        let candidate = FileCandidate(path: "/tmp/tool.zip", fileSize: 2048, metadata: metadata)
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        // Pipeline should fall back to candidate.downloadURL and classify as developer
        #expect(context.downloadContext != nil)
        #expect(context.downloadContext?.sourceCategory == .developer)
        #expect(context.downloadContext?.sourceURL != nil)
    }

    @Test("EnrichedFileContext effectiveText prefers extracted over OCR")
    func effectiveTextPrecedence() {
        let candidate = FileCandidate(path: "/tmp/test.pdf", fileSize: 100)
        let context = EnrichedFileContext(
            candidate: candidate,
            extractedText: "Direct text",
            imageAnalysis: ImageAnalysis(sceneType: .document, ocrText: "OCR text")
        )
        #expect(context.effectiveText == "Direct text")
    }

    @Test("effectiveText falls back to OCR when no extracted text")
    func effectiveTextFallsBackToOCR() {
        let candidate = FileCandidate(path: "/tmp/photo.jpg", fileSize: 500)
        let context = EnrichedFileContext(
            candidate: candidate,
            extractedText: nil,
            imageAnalysis: ImageAnalysis(sceneType: .document, ocrText: "Scanned text via OCR")
        )
        #expect(context.effectiveText == "Scanned text via OCR")
    }

    @Test("non-existent file produces minimal enrichment")
    func nonExistentFile() async {
        let candidate = FileCandidate(path: "/tmp/does-not-exist-12345.xyz", fileSize: 0)
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.extractedText == nil)
        #expect(context.imageAnalysis == nil)
    }

    @Test("non-existent text file produces no extracted text")
    func nonExistentTextFile() async {
        let candidate = FileCandidate(path: "/tmp/does-not-exist-99999.txt", fileSize: 0)
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        // txt is text-extractable, but file doesn't exist — should return nil gracefully
        #expect(context.extractedText == nil)
        #expect(context.imageAnalysis == nil)
        #expect(context.downloadContext == nil)
    }

    @Test("empty knowledge base produces no routing decision")
    func emptyKnowledgeBaseNoDecision() async throws {
        let dir = makeTemporaryDirectory(prefix: "integration-empty")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let filePath = dir + "/notes.txt"
        createFile(atPath: filePath, contents: "some text content".data(using: .utf8)!)

        let kb = try KnowledgeBase.inMemory()
        // No patterns recorded — engine should return nil
        let engine = try ScoringEngine(
            knowledgeBase: kb,
            heuristicsEngine: HeuristicsEngine(affinities: [], clusters: [])
        )
        let pipeline = ContentIntelligencePipeline()

        let candidate = FileCandidate(path: filePath, fileSize: 17)
        let context = await pipeline.enrich(candidate)
        let decision = try await engine.route(context)

        #expect(decision == nil)
    }
}
