import Foundation

public struct InvocationPolicy: Sendable {
    private static let deterministicExtensions: Set<String> = ["dmg", "pkg", "mpkg", "app"]
    private let highConfidenceThreshold: Int

    public init(highConfidenceThreshold: Int = 85) {
        self.highConfidenceThreshold = highConfidenceThreshold
    }

    public func shouldInvoke(
        extension ext: String?, patternConfidence: Int?, isScreenshot: Bool
    ) -> Bool {
        if let ext = ext, Self.deterministicExtensions.contains(ext.lowercased()) { return false }
        if isScreenshot { return false }
        if let c = patternConfidence, c > highConfidenceThreshold { return false }
        guard let confidence = patternConfidence else { return true }
        if confidence < 50 { return true }
        if let ext = ext { return ContentExtractor.isTextExtractable(extension: ext) }
        return false
    }
}
