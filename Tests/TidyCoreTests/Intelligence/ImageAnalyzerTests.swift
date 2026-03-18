import Testing
@testable import TidyCore

@Suite("ImageAnalyzer")
struct ImageAnalyzerTests {
    @Test("isImageFile identifies common image extensions")
    func imageExtensions() {
        #expect(ImageAnalyzer.isImageFile(extension: "jpg"))
        #expect(ImageAnalyzer.isImageFile(extension: "jpeg"))
        #expect(ImageAnalyzer.isImageFile(extension: "png"))
        #expect(ImageAnalyzer.isImageFile(extension: "heic"))
        #expect(ImageAnalyzer.isImageFile(extension: "tiff"))
        #expect(!ImageAnalyzer.isImageFile(extension: "pdf"))
        #expect(!ImageAnalyzer.isImageFile(extension: "txt"))
    }

    @Test("mapClassificationLabel maps known labels to scene types")
    func labelMapping() {
        #expect(ImageAnalyzer.mapClassificationLabel("document") == .document)
        #expect(ImageAnalyzer.mapClassificationLabel("text") == .document)
        #expect(ImageAnalyzer.mapClassificationLabel("screenshot") == .screenshot)
        #expect(ImageAnalyzer.mapClassificationLabel("people") == .photo)
        #expect(ImageAnalyzer.mapClassificationLabel("portrait") == .photo)
        #expect(ImageAnalyzer.mapClassificationLabel("landscape") == .photo)
        #expect(ImageAnalyzer.mapClassificationLabel("food") == .photo)
        #expect(ImageAnalyzer.mapClassificationLabel("diagram") == .diagram)
        #expect(ImageAnalyzer.mapClassificationLabel("chart") == .diagram)
        #expect(ImageAnalyzer.mapClassificationLabel("receipt") == .receipt)
        #expect(ImageAnalyzer.mapClassificationLabel("random_label") == .unknown)
    }

    @Test("case insensitive label mapping")
    func caseInsensitive() {
        #expect(ImageAnalyzer.mapClassificationLabel("DOCUMENT") == .document)
        #expect(ImageAnalyzer.mapClassificationLabel("Screenshot") == .screenshot)
    }

    @Test("extractEXIF returns nil for non-image file")
    func noEXIFForText() throws {
        let dir = makeTemporaryDirectory(prefix: "exif-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }
        let path = dir + "/test.txt"
        createFile(atPath: path, contents: "not an image".data(using: .utf8)!)
        let exif = ImageAnalyzer.extractEXIF(from: path)
        #expect(exif == nil)
    }

    @Test("analyze returns nil for non-image file")
    func nonImageReturnsNil() async throws {
        let dir = makeTemporaryDirectory(prefix: "analyze-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }
        let path = dir + "/test.txt"
        createFile(atPath: path, contents: "not an image".data(using: .utf8)!)
        let result = await ImageAnalyzer.analyze(path: path)
        #expect(result == nil)
    }
}
