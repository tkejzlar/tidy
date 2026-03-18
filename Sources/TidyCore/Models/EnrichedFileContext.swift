import Foundation

public struct EnrichedFileContext: Sendable {
    public let candidate: FileCandidate
    public let extractedText: String?
    public let imageAnalysis: ImageAnalysis?
    public let downloadContext: DownloadContext?

    public var effectiveText: String? {
        extractedText ?? imageAnalysis?.ocrText
    }

    public init(candidate: FileCandidate, extractedText: String? = nil, imageAnalysis: ImageAnalysis? = nil, downloadContext: DownloadContext? = nil) {
        self.candidate = candidate; self.extractedText = extractedText; self.imageAnalysis = imageAnalysis; self.downloadContext = downloadContext
    }
}
