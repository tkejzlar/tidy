import Foundation
import PDFKit

public struct ContentExtractor: Sendable {
    private static let textExtensions: Set<String> = ["txt", "md", "csv", "text", "markdown"]
    private static let pdfExtensions: Set<String> = ["pdf"]
    private static let rtfExtensions: Set<String> = ["rtf"]
    private static let officeExtensions: Set<String> = ["docx", "xlsx", "pptx"]
    private static let emailExtensions: Set<String> = ["eml"]

    public init() {}

    public static func isTextExtractable(extension ext: String) -> Bool {
        let lower = ext.lowercased()
        return textExtensions.contains(lower)
            || pdfExtensions.contains(lower)
            || rtfExtensions.contains(lower)
            || officeExtensions.contains(lower)
            || emailExtensions.contains(lower)
    }

    public func extractText(from path: String, maxWords: Int = 500) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        if Self.pdfExtensions.contains(ext) {
            return extractFromPDF(path: path, maxWords: maxWords)
        } else if Self.textExtensions.contains(ext) {
            return extractFromTextFile(path: path, maxWords: maxWords)
        } else if Self.rtfExtensions.contains(ext) {
            return extractFromRTF(path: path, maxWords: maxWords)
        } else if Self.officeExtensions.contains(ext) {
            return extractFromOfficeXML(path: path, maxWords: maxWords)
        } else if Self.emailExtensions.contains(ext) {
            return extractFromEML(path: path, maxWords: maxWords)
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

    private func extractFromRTF(path: String, maxWords: Int) -> String? {
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else { return nil }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        let text = attributed.string
        guard !text.isEmpty else { return nil }
        return truncateToWords(text, maxWords: maxWords)
    }

    private func extractFromOfficeXML(path: String, maxWords: Int) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        let innerPath: String
        switch ext {
        case "docx": innerPath = "word/document.xml"
        case "xlsx": innerPath = "xl/sharedStrings.xml"
        case "pptx": innerPath = "ppt/slides/slide1.xml"
        default: return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", path, innerPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let xmlData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !xmlData.isEmpty,
              let xmlString = String(data: xmlData, encoding: .utf8) else { return nil }

        // Strip XML tags
        var result = ""
        var inTag = false
        for ch in xmlString {
            if ch == "<" {
                inTag = true
                result.append(" ")
            } else if ch == ">" {
                inTag = false
            } else if !inTag {
                result.append(ch)
            }
        }
        let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return truncateToWords(text, maxWords: maxWords)
    }

    private func extractFromEML(path: String, maxWords: Int) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8),
              !raw.isEmpty else { return nil }
        // Split headers from body at first blank line
        let body: String
        if let range = raw.range(of: "\n\n") {
            body = String(raw[range.upperBound...])
        } else {
            body = raw
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return truncateToWords(text, maxWords: maxWords)
    }

    private func truncateToWords(_ text: String, maxWords: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.prefix(maxWords).joined(separator: " ")
    }
}
