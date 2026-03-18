import Testing
@testable import TidyCore

@Suite("HeuristicsEngine")
struct HeuristicsEngineTests {
    @Test("screenshots route with 100% confidence via filename")
    func screenshotByFilename() async throws {
        let engine = HeuristicsEngine(
            affinities: [], clusters: [],
            screenshotDestination: "~/Screenshots"
        )
        let candidate = FileCandidate(
            path: "/Downloads/Screenshot 2026-03-17 at 10.42.31.png",
            fileSize: 500_000
        )
        let results = try await engine.score(EnrichedFileContext(candidate: candidate))
        #expect(results.count == 1)
        #expect(results[0].path == "~/Screenshots")
        #expect(results[0].confidence == 1.0)
    }

    @Test("screenshots route with 100% confidence via metadata flag")
    func screenshotByMetadata() async throws {
        let engine = HeuristicsEngine(
            affinities: [], clusters: [],
            screenshotDestination: "~/Screenshots"
        )
        let metadata = FileMetadata(
            contentType: "public.png", downloadURL: nil, sourceApp: nil,
            pixelWidth: 1920, pixelHeight: 1080, numberOfPages: nil,
            isScreenCapture: true, authors: []
        )
        let candidate = FileCandidate(
            path: "/Downloads/random-image.png",
            fileSize: 500_000,
            metadata: metadata
        )
        let results = try await engine.score(EnrichedFileContext(candidate: candidate))
        #expect(results.count == 1)
        #expect(results[0].confidence == 1.0)
    }

    @Test("installers route with 100% confidence")
    func installer() async throws {
        let engine = HeuristicsEngine(
            affinities: [], clusters: [],
            installerDestination: "~/Installers"
        )
        let candidate = FileCandidate(
            path: "/Downloads/Chrome.dmg", fileSize: 100_000_000
        )
        let results = try await engine.score(EnrichedFileContext(candidate: candidate))
        #expect(results.count == 1)
        #expect(results[0].path == "~/Installers")
        #expect(results[0].confidence == 1.0)
    }

    @Test("extension affinity scores reach suggest tier for 20+ files")
    func extensionAffinityReachesSuggestTier() async throws {
        let affinities = [
            ExtensionAffinity(folderPath: "~/Documents/PDFs", fileExtension: "pdf", fileCount: 25)
        ]
        let engine = HeuristicsEngine(affinities: affinities, clusters: [])
        let candidate = FileCandidate(
            path: "/Downloads/report.pdf", fileSize: 1_000_000
        )
        let results = try await engine.score(EnrichedFileContext(candidate: candidate))
        #expect(!results.isEmpty)
        let pdfResult = results.first { $0.path == "~/Documents/PDFs" }
        #expect(pdfResult != nil)
        #expect(pdfResult!.confidence >= 0.50)
    }

    @Test("screenshot takes priority over extension affinity")
    func screenshotPriority() async throws {
        let affinities = [
            ExtensionAffinity(folderPath: "~/Photos", fileExtension: "png", fileCount: 100)
        ]
        let engine = HeuristicsEngine(
            affinities: affinities, clusters: [],
            screenshotDestination: "~/Screenshots"
        )
        let candidate = FileCandidate(
            path: "/Downloads/Screenshot 2026-03-17 at 10.42.31.png",
            fileSize: 500_000
        )
        let results = try await engine.score(EnrichedFileContext(candidate: candidate))
        #expect(results[0].path == "~/Screenshots")
    }

    @Test("returns empty for unknown file types with no affinities")
    func noMatch() async throws {
        let engine = HeuristicsEngine(affinities: [], clusters: [])
        let candidate = FileCandidate(
            path: "/Downloads/mystery.xyz", fileSize: 100
        )
        let results = try await engine.score(EnrichedFileContext(candidate: candidate))
        #expect(results.isEmpty)
    }
}
