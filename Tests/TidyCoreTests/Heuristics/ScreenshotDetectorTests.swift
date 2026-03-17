import Testing
@testable import TidyCore

@Suite("ScreenshotDetector")
struct ScreenshotDetectorTests {
    let detector = ScreenshotDetector()

    @Test("detects macOS screenshot filename pattern")
    func macOSScreenshot() {
        #expect(detector.isScreenshot(filename: "Screenshot 2026-03-17 at 10.42.31.png", isScreenCapture: false) == true)
    }

    @Test("detects via metadata flag")
    func metadataFlag() {
        #expect(detector.isScreenshot(filename: "random-image.png", isScreenCapture: true) == true)
    }

    @Test("detects CleanShot screenshots")
    func cleanShot() {
        #expect(detector.isScreenshot(filename: "CleanShot 2026-03-17 at 10.42.31.png", isScreenCapture: false) == true)
    }

    @Test("rejects non-screenshot images")
    func notScreenshot() {
        #expect(detector.isScreenshot(filename: "vacation-photo.png", isScreenCapture: false) == false)
    }
}
