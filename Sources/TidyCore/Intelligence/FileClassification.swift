import Foundation

#if canImport(FoundationModels) && FOUNDATION_MODELS_MACROS_AVAILABLE
import FoundationModels

@available(macOS 26, *)
@Generable
public struct FileClassification {
    @Guide(description: "Primary category: finance, legal, work, personal, reference, creative, code, media")
    public var category: String

    @Guide(description: "Suggested subfolder name, 1-2 words")
    public var subfolder: String

    @Guide(description: "Confidence 0-100")
    public var confidence: Int

    @Guide(description: "One-line description of the document")
    public var summary: String
}
#endif
