import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
public final class AppleIntelligenceLayer: Sendable, ScoringLayer {
    private let contentExtractor: ContentExtractor
    private let invocationPolicy: InvocationPolicy
    private let existingFolders: [String]

    public init(existingFolders: [String], invocationPolicy: InvocationPolicy = InvocationPolicy()) {
        self.contentExtractor = ContentExtractor()
        self.invocationPolicy = invocationPolicy
        self.existingFolders = existingFolders
    }

    public func score(_ candidate: FileCandidate) async throws -> [ScoredDestination] {
        let isScreenshot = candidate.metadata?.isScreenCapture ?? false
        guard invocationPolicy.shouldInvoke(
            extension: candidate.fileExtension, patternConfidence: nil, isScreenshot: isScreenshot
        ) else { return [] }

        var prompt = "Classify this file for organizing into folders.\n\n"
        prompt += "Filename: \(candidate.filename)\n"
        if let url = candidate.downloadURL { prompt += "Download URL: \(url)\n" }
        if let content = contentExtractor.extractText(from: candidate.path, maxWords: 500) {
            prompt += "File content:\n\(content)\n"
        }
        if !existingFolders.isEmpty {
            prompt += "\nExisting folders: \(existingFolders.joined(separator: ", "))\n"
        }

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt, generating: FileClassification.self)
            let classification = response.content
            let confidence = Double(min(max(classification.confidence, 0), 100)) / 100.0

            if let folder = findBestFolder(category: classification.category, subfolder: classification.subfolder) {
                return [ScoredDestination(path: folder, confidence: confidence,
                    reason: "AI: \(classification.summary)")]
            } else {
                return [ScoredDestination(
                    path: "~/Documents/\(classification.category.capitalized)/\(classification.subfolder)",
                    confidence: confidence * 0.8,
                    reason: "AI: \(classification.summary)")]
            }
        } catch {
            return []
        }
    }

    private func findBestFolder(category: String, subfolder: String) -> String? {
        let catLower = category.lowercased()
        let subLower = subfolder.lowercased()
        for folder in existingFolders {
            let name = (folder as NSString).lastPathComponent.lowercased()
            if name == subLower || name == catLower { return folder }
        }
        for folder in existingFolders {
            if folder.lowercased().contains(catLower) || folder.lowercased().contains(subLower) { return folder }
        }
        return nil
    }
}
#endif

public struct AppleIntelligenceAvailability: Sendable {
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }
}
