import Foundation

public struct ContentIntelligencePipeline: Sendable {
    private let downloadContextExtractor = DownloadContextExtractor()
    private let contentExtractor = ContentExtractor()

    public init() {}

    /// Run all enrichment stages and produce an EnrichedFileContext.
    public func enrich(_ candidate: FileCandidate) async -> EnrichedFileContext {
        // Stage 1: Text extraction (cheap, always run for supported types)
        let extractedText: String?
        if let ext = candidate.fileExtension, ContentExtractor.isTextExtractable(extension: ext) {
            extractedText = contentExtractor.extractText(from: candidate.path)
        } else {
            extractedText = nil
        }

        // Stage 2: Image analysis (moderate cost, run for images only)
        let imageAnalysis: ImageAnalysis?
        if let ext = candidate.fileExtension, ImageAnalyzer.isImageFile(extension: ext) {
            imageAnalysis = await ImageAnalyzer.analyze(path: candidate.path)
        } else {
            imageAnalysis = nil
        }

        // Stage 3: Download context (free, always run)
        // First try xattrs on the actual file, then fall back to metadata URL
        var downloadContext = downloadContextExtractor.extract(fromPath: candidate.path)
        if downloadContext.sourceCategory == .unknown, let urlString = candidate.downloadURL {
            downloadContext = downloadContextExtractor.contextFromURL(urlString)
        }

        // Only include download context if it has meaningful data
        let finalDownloadContext: DownloadContext?
        if downloadContext.sourceCategory == .unknown && downloadContext.sourceURL == nil {
            finalDownloadContext = nil
        } else {
            finalDownloadContext = downloadContext
        }

        return EnrichedFileContext(
            candidate: candidate,
            extractedText: extractedText,
            imageAnalysis: imageAnalysis,
            downloadContext: finalDownloadContext
        )
    }
}
