import Testing
@testable import TidyCore

@Suite("EnrichedFileContext")
struct EnrichedFileContextTests {
    @Test("wraps FileCandidate with nil enrichments by default")
    func defaultEnrichment() {
        let candidate = FileCandidate(path: "/tmp/test.pdf", fileSize: 1024)
        let context = EnrichedFileContext(candidate: candidate)
        #expect(context.candidate.path == "/tmp/test.pdf")
        #expect(context.extractedText == nil)
        #expect(context.imageAnalysis == nil)
        #expect(context.downloadContext == nil)
    }

    @Test("effectiveText returns extractedText when present")
    func effectiveTextFromExtraction() {
        let candidate = FileCandidate(path: "/tmp/test.pdf", fileSize: 1024)
        let context = EnrichedFileContext(candidate: candidate, extractedText: "Invoice from Acme Corp")
        #expect(context.effectiveText == "Invoice from Acme Corp")
    }

    @Test("effectiveText falls back to OCR text when extractedText is nil")
    func effectiveTextFallbackToOCR() {
        let candidate = FileCandidate(path: "/tmp/scan.pdf", fileSize: 2048)
        let imageAnalysis = ImageAnalysis(sceneType: .document, ocrText: "Scanned invoice text")
        let context = EnrichedFileContext(candidate: candidate, imageAnalysis: imageAnalysis)
        #expect(context.effectiveText == "Scanned invoice text")
    }

    @Test("effectiveText returns nil when both are nil")
    func effectiveTextNil() {
        let candidate = FileCandidate(path: "/tmp/test.bin", fileSize: 100)
        let context = EnrichedFileContext(candidate: candidate)
        #expect(context.effectiveText == nil)
    }

    @Test("SceneType raw values are stable strings")
    func sceneTypeRawValues() {
        #expect(SceneType.screenshot.rawValue == "screenshot")
        #expect(SceneType.photo.rawValue == "photo")
        #expect(SceneType.document.rawValue == "document")
        #expect(SceneType.diagram.rawValue == "diagram")
        #expect(SceneType.receipt.rawValue == "receipt")
        #expect(SceneType.unknown.rawValue == "unknown")
    }

    @Test("SourceCategory raw values are stable strings")
    func sourceCategoryRawValues() {
        #expect(SourceCategory.developer.rawValue == "developer")
        #expect(SourceCategory.googleDrive.rawValue == "googleDrive")
        #expect(SourceCategory.slack.rawValue == "slack")
        #expect(SourceCategory.email.rawValue == "email")
        #expect(SourceCategory.appStore.rawValue == "appStore")
        #expect(SourceCategory.browser.rawValue == "browser")
        #expect(SourceCategory.unknown.rawValue == "unknown")
    }
}
