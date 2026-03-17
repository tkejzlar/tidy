// Sources/TidyCore/Metadata/FileMetadataExtractor.swift
import Foundation

/// Metadata extracted from a file via Spotlight / MDItem APIs.
public struct FileMetadata: Sendable {
    public let contentType: String?        // UTI, e.g. "public.jpeg"
    public let downloadURL: String?        // kMDItemWhereFroms (first entry)
    public let sourceApp: String?          // kMDItemCreator or quarantine agent
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let numberOfPages: Int?
    public let isScreenCapture: Bool
    public let authors: [String]

    public init(
        contentType: String?, downloadURL: String?, sourceApp: String?,
        pixelWidth: Int?, pixelHeight: Int?, numberOfPages: Int?,
        isScreenCapture: Bool, authors: [String]
    ) {
        self.contentType = contentType
        self.downloadURL = downloadURL
        self.sourceApp = sourceApp
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.numberOfPages = numberOfPages
        self.isScreenCapture = isScreenCapture
        self.authors = authors
    }
}

public struct FileMetadataExtractor: Sendable {
    public init() {}

    public func extract(from path: String) -> FileMetadata {
        guard let mdItem = MDItemCreate(nil, path as CFString) else {
            return FileMetadata(
                contentType: nil, downloadURL: nil, sourceApp: nil,
                pixelWidth: nil, pixelHeight: nil, numberOfPages: nil,
                isScreenCapture: false, authors: []
            )
        }

        func attr<T>(_ name: CFString) -> T? {
            MDItemCopyAttribute(mdItem, name) as? T
        }

        let whereFroms: [String]? = attr(kMDItemWhereFroms)
        let isScreenCapture: Bool = MDItemCopyAttribute(
            mdItem, "kMDItemIsScreenCapture" as CFString
        ) as? Bool ?? false

        return FileMetadata(
            contentType: attr(kMDItemContentType),
            downloadURL: whereFroms?.first,
            sourceApp: attr(kMDItemCreator),
            pixelWidth: attr(kMDItemPixelWidth),
            pixelHeight: attr(kMDItemPixelHeight),
            numberOfPages: attr(kMDItemNumberOfPages),
            isScreenCapture: isScreenCapture,
            authors: attr(kMDItemAuthors) ?? []
        )
    }
}
