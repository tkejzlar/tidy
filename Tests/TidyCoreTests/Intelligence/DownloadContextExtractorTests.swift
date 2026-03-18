import Testing
@testable import TidyCore

@Suite("DownloadContextExtractor")
struct DownloadContextExtractorTests {
    let extractor = DownloadContextExtractor()

    @Test("extracts context from URL string")
    func fromURL() {
        let context = extractor.contextFromURL("https://github.com/user/repo/releases/download/v1.0/app.zip")
        #expect(context.sourceCategory == .developer)
        #expect(context.sourceURL != nil)
    }

    @Test("extracts context from Google Drive URL")
    func fromGoogleDrive() {
        let context = extractor.contextFromURL("https://drive.google.com/uc?id=abc123")
        #expect(context.sourceCategory == .googleDrive)
    }

    @Test("returns browser category for unknown domain")
    func unknownDomain() {
        let context = extractor.contextFromURL("https://randomsite.com/file.zip")
        #expect(context.sourceCategory == .browser)
    }

    @Test("handles nil URL gracefully")
    func nilURL() {
        let context = extractor.contextFromURL(nil)
        #expect(context.sourceCategory == .unknown)
        #expect(context.sourceURL == nil)
    }

    @Test("handles malformed URL string")
    func malformedURL() {
        let context = extractor.contextFromURL("not a url at all")
        #expect(context.sourceCategory == .unknown)
    }

    @Test("extracts quarantine agent from string")
    func quarantineAgent() {
        let agent = DownloadContextExtractor.parseQuarantineAgent(from: "0083;5f3b3c00;Safari;12345")
        #expect(agent == "Safari")
    }

    @Test("handles missing quarantine agent")
    func missingQuarantineAgent() {
        let agent = DownloadContextExtractor.parseQuarantineAgent(from: nil)
        #expect(agent == nil)
    }

    @Test("handles empty quarantine agent field")
    func emptyQuarantineAgent() {
        let agent = DownloadContextExtractor.parseQuarantineAgent(from: "0083;5f3b3c00;;12345")
        #expect(agent == nil)
    }
}
