import Foundation

public enum SceneType: String, Codable, Sendable {
    case screenshot, photo, document, diagram, receipt, unknown
}

public struct EXIFMetadata: Sendable {
    public let cameraModel: String?
    public let hasGPS: Bool
    public let creationDate: Date?
    public init(cameraModel: String? = nil, hasGPS: Bool = false, creationDate: Date? = nil) {
        self.cameraModel = cameraModel; self.hasGPS = hasGPS; self.creationDate = creationDate
    }
}

public struct ImageAnalysis: Sendable {
    public let sceneType: SceneType
    public let ocrText: String?
    public let hasFaces: Bool
    public let exifMetadata: EXIFMetadata?
    public init(sceneType: SceneType, ocrText: String? = nil, hasFaces: Bool = false, exifMetadata: EXIFMetadata? = nil) {
        self.sceneType = sceneType; self.ocrText = ocrText; self.hasFaces = hasFaces; self.exifMetadata = exifMetadata
    }
}
