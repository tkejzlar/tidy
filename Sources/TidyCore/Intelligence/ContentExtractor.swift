import Foundation
import PDFKit

public struct ContentExtractor: Sendable {
    private static let textExtensions: Set<String> = ["txt", "md", "csv", "text", "markdown"]
    private static let pdfExtensions: Set<String> = ["pdf"]

    public init() {}

    public static func isTextExtractable(extension ext: String) -> Bool {
        let lower = ext.lowercased()
        return textExtensions.contains(lower) || pdfExtensions.contains(lower)
    }

    public func extractText(from path: String, maxWords: Int = 500) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        if Self.pdfExtensions.contains(ext) {
            return extractFromPDF(path: path, maxWords: maxWords)
        } else if Self.textExtensions.contains(ext) {
            return extractFromTextFile(path: path, maxWords: maxWords)
        }
        return nil
    }

    private func extractFromTextFile(path: String, maxWords: Int) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return truncateToWords(text, maxWords: maxWords)
    }

    private func extractFromPDF(path: String, maxWords: Int) -> String? {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { return nil }
        var text = ""
        let maxPages = min(document.pageCount, 5)
        for i in 0..<maxPages {
            guard let page = document.page(at: i),
                  let pageText = page.string else { continue }
            text += pageText + "\n"
            if text.split(whereSeparator: \.isWhitespace).count >= maxWords { break }
        }
        guard !text.isEmpty else { return nil }
        return truncateToWords(text, maxWords: maxWords)
    }

    private func truncateToWords(_ text: String, maxWords: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.prefix(maxWords).joined(separator: " ")
    }
}
