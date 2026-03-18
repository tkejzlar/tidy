import Foundation
import Vision
import ImageIO

public struct ImageAnalyzer: Sendable {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]

    private static let labelToSceneType: [String: SceneType] = [
        "document": .document, "text": .document,
        "screenshot": .screenshot,
        "people": .photo, "portrait": .photo,
        "landscape": .photo, "nature": .photo, "food": .photo, "animal": .photo,
        "diagram": .diagram, "chart": .diagram,
        "receipt": .receipt,
    ]

    public static func isImageFile(extension ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }

    public static func mapClassificationLabel(_ label: String) -> SceneType {
        labelToSceneType[label.lowercased()] ?? .unknown
    }

    /// Full analysis: scene classification, OCR, face detection, EXIF.
    /// Returns nil for non-image files.
    public static func analyze(path: String) async -> ImageAnalysis? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard isImageFile(extension: ext) else { return nil }

        let url = URL(fileURLWithPath: path)
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        async let sceneType = classifyScene(cgImage: cgImage)
        async let ocrText = recognizeText(cgImage: cgImage)
        async let hasFaces = detectFaces(cgImage: cgImage)
        let exifMetadata = extractEXIF(from: path)

        return await ImageAnalysis(
            sceneType: sceneType,
            ocrText: ocrText,
            hasFaces: hasFaces,
            exifMetadata: exifMetadata
        )
    }

    private static func classifyScene(cgImage: CGImage) async -> SceneType {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNClassificationObservation],
                      let topResult = results.first,
                      topResult.confidence > 0.3 else {
                    continuation.resume(returning: .unknown)
                    return
                }
                continuation.resume(returning: mapClassificationLabel(topResult.identifier))
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: .unknown)
            }
        }
    }

    private static func recognizeText(cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                continuation.resume(returning: text.isEmpty ? nil : String(text.prefix(2000)))
            }
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private static func detectFaces(cgImage: CGImage) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                let count = (request.results as? [VNFaceObservation])?.count ?? 0
                continuation.resume(returning: count > 0)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    public static func extractEXIF(from path: String) -> EXIFMetadata? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let cameraModel = tiffDict?[kCGImagePropertyTIFFModel as String] as? String
        let hasGPS = gpsDict != nil && !gpsDict!.isEmpty
        var creationDate: Date? = nil
        if let dateStr = exifDict?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            creationDate = formatter.date(from: dateStr)
        }
        guard cameraModel != nil || hasGPS || creationDate != nil else { return nil }
        return EXIFMetadata(cameraModel: cameraModel, hasGPS: hasGPS, creationDate: creationDate)
    }
}
