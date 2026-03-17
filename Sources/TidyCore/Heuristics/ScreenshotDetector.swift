import Foundation

public struct ScreenshotDetector: Sendable {
    private static let patterns: [String] = [
        #"^Screenshot \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}"#,
        #"^CleanShot \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}"#,
        #"^Monosnap "#,
        #"^Screen Shot \d{4}-\d{2}-\d{2} at \d{1,2}\.\d{2}\.\d{2}"#,
    ]

    public init() {}

    public func isScreenshot(filename: String, isScreenCapture: Bool) -> Bool {
        if isScreenCapture { return true }
        return Self.patterns.contains { pattern in
            filename.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
