// Tests/TidyCoreTests/Models/FileCandidateTests.swift
import Testing
@testable import TidyCore

@Suite("FileCandidate")
struct FileCandidateTests {
    @Test("extracts extension and tokens from filename")
    func filenameTokenization() {
        let candidate = FileCandidate(
            path: "/Users/me/Downloads/invoice-march-2026.pdf",
            fileSize: 45_000
        )
        #expect(candidate.fileExtension == "pdf")
        // "2026" is filtered out — pure numeric tokens are noise for matching
        #expect(candidate.filenameTokens == ["invoice", "march"])
        #expect(candidate.sizeBucket == .small)
    }

    @Test("handles filenames with dots, underscores, spaces")
    func complexFilename() {
        let candidate = FileCandidate(
            path: "/Users/me/Downloads/Q1 Report_Final.v2.docx",
            fileSize: 1_500_000
        )
        #expect(candidate.fileExtension == "docx")
        #expect(Set(candidate.filenameTokens) == Set(["q1", "report", "final", "v2"]))
        #expect(candidate.sizeBucket == .medium)
    }

    @Test("handles no-extension files")
    func noExtension() {
        let candidate = FileCandidate(
            path: "/Users/me/Downloads/Makefile",
            fileSize: 200
        )
        #expect(candidate.fileExtension == nil)
        #expect(candidate.filenameTokens == ["makefile"])
    }

    @Test("carries optional metadata")
    func withMetadata() {
        let metadata = FileMetadata(
            contentType: "public.jpeg",
            downloadURL: nil,
            sourceApp: "Safari",
            pixelWidth: 1920, pixelHeight: 1080,
            numberOfPages: nil,
            isScreenCapture: true,
            authors: []
        )
        let candidate = FileCandidate(
            path: "/Downloads/screenshot.png",
            fileSize: 500_000,
            metadata: metadata
        )
        #expect(candidate.metadata?.isScreenCapture == true)
        #expect(candidate.sourceApp == "Safari")
    }
}
