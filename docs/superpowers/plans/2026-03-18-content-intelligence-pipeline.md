# Content Intelligence Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich file candidates with deep content understanding (text extraction, image analysis, download context) before scoring, so Tidy routes files based on what they *are*, not just what they're named.

**Architecture:** A three-stage `ContentIntelligencePipeline` runs after `FileCandidate` creation and before scoring. It produces an `EnrichedFileContext` that wraps the candidate with extracted text, image analysis, and download provenance. The `ScoringLayer` protocol changes to accept `EnrichedFileContext`. All existing layers migrate to the new protocol. The `PatternMatcher` feature vector expands with new signals (scene type, source domain) at fixed weights.

**Tech Stack:** Swift 6, Vision framework (VNClassifyImageRequest, VNRecognizeTextRequest, VNDetectFaceRectanglesRequest), CGImageSource (EXIF), Foundation (xattr reading), GRDB (schema migration)

**Spec:** `docs/superpowers/specs/2026-03-17-tidy-v2-design.md` §1

---

## IMPORTANT: Corrections to Code Samples

> **Read this section first.** The code samples in this plan contain known issues identified during review. Apply these corrections when implementing each task. When a code sample conflicts with these corrections, the corrections take precedence.

### C1: FileCandidate Initializer

The plan uses `FileCandidate(path:fileSize:sourceApp:downloadURL:)` in many places. **This initializer does not exist.** The actual signature is:

```swift
FileCandidate(path: String, fileSize: UInt64, metadata: FileMetadata? = nil, date: Date = Date())
```

`sourceApp` and `downloadURL` are derived from `metadata`. To create a candidate with a download URL in tests:

```swift
let metadata = FileMetadata(downloadURL: "https://github.com/...")
let candidate = FileCandidate(path: "/tmp/test.pdf", fileSize: 1024, metadata: metadata)
```

Or without metadata (most tests): `FileCandidate(path: "/tmp/test.pdf", fileSize: 1024)`

### C2: ContentExtractor is Already Static

The existing `ContentExtractor` already uses static methods (`ContentExtractor.extractText(from:)`). The plan's rewrite is consistent with this. However, `AppleIntelligenceLayer` stores a `contentExtractor` instance — after this change, update it to use the static calls instead.

Also preserve the existing `textExtensions` set members (`"text"`, `"markdown"`) when adding new formats. Use `\.isWhitespace` in `truncateToWords` (not just space character) to match existing behavior.

### C3: KnowledgeBase.recordPattern Signature

The existing method signature uses:
- Label `extension ext:` (not `fileExtension:`)
- `SizeBucket?` and `TimeBucket?` types (not `String?`)
- Plain JSON encoding for tokens (not base64)

**Add the new parameters with defaults for backward compatibility:**

```swift
public func recordPattern(
    extension ext: String?,
    filenameTokens: [String],
    sourceApp: String?,
    sizeBucket: SizeBucket?,
    timeBucket: TimeBucket?,
    documentType: String? = nil,
    sourceDomain: String? = nil,
    sceneType: String? = nil,
    sourceFolder: String? = nil,
    destination: String,
    signalType: SignalType
) throws {
    // Keep existing JSON encoding: String(data:encoding:), NOT base64
    let tokensJSON = try? JSONEncoder().encode(filenameTokens)
    let tokensString = tokensJSON.flatMap { String(data: $0, encoding: .utf8) }
    // ... rest same, with new fields
}
```

**In PatternMatcher**, decode tokens with `tokensJSON.data(using: .utf8)` then `JSONDecoder().decode([String].self, from:)` — same as v1. Do NOT use `Data(base64Encoded:)`.

### C4: ScoringEngine Initializer

The plan uses `ScoringEngine(patternMatcher:heuristicsEngine:pinnedRulesManager:knowledgeBase:)` in test code. **This does not exist.** The actual initializers are:

```swift
// 2-layer (no AI):
try ScoringEngine(knowledgeBase: kb, heuristicsEngine: engine, pinnedRules: manager)
// 3-layer (with AI):
try ScoringEngine(knowledgeBase: kb, heuristicsEngine: engine, aiLayer: layer, pinnedRules: manager)
```

`ScoringEngine` creates its own `PatternMatcher` internally. Use these initializers in all test code.

### C5: SignalRecorder Methods Throw

The existing `SignalRecorder` methods are `throws`. Keep them throwing. The plan's v2 enriched methods should also throw (not swallow with `try?`):

```swift
public func recordObservation(context: EnrichedFileContext, destination: String) throws {
    try knowledgeBase.recordPattern(extension: ..., ...)
}
```

### C6: MoveOrchestrator approve/redirect/confirm Methods

The plan only updates `processFile` and `recordUserMove`. **Also update** `approveSuggestion`, `redirect`, and `confirmAutoMove` to accept and use `EnrichedFileContext` so enriched signals are recorded. `AppState.Suggestion` should carry `EnrichedFileContext` instead of just `FileCandidate` so context isn't lost when the user acts on a suggestion.

### C7: Test File Paths

Place `EnrichedFileContextTests.swift` at `Tests/TidyCoreTests/Models/EnrichedFileContextTests.swift` for consistency with other model tests. Test files that call `makeTemporaryDirectory` should also call `createDirectory(atPath: dir)` before writing files to it.

### C8: sourceDomain vs sourceCategory

`pattern.sourceDomain` stores `SourceCategory.rawValue` (e.g., "email"), not an actual domain name. In `PatternMatcher`, compare `sourceCategory.rawValue == patternDomain`. Do NOT compare `sourceURL.host()` against a category name — remove that second condition.

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/TidyCore/Models/EnrichedFileContext.swift` | Wrapper struct: FileCandidate + pipeline outputs |
| `Sources/TidyCore/Models/ImageAnalysis.swift` | SceneType enum, ImageAnalysis struct, EXIFMetadata |
| `Sources/TidyCore/Models/DownloadContext.swift` | SourceCategory enum, DownloadContext struct |
| `Sources/TidyCore/Intelligence/ImageAnalyzer.swift` | Vision framework image analysis |
| `Sources/TidyCore/Intelligence/DownloadContextExtractor.swift` | xattr-based download provenance |
| `Sources/TidyCore/Intelligence/ContentIntelligencePipeline.swift` | Composes stages 1-3 |
| `Sources/TidyCore/Intelligence/SourceCategoryMappings.swift` | Domain→category mapping logic |
| `Tests/TidyCoreTests/Intelligence/ImageAnalyzerTests.swift` | Image analysis tests |
| `Tests/TidyCoreTests/Intelligence/DownloadContextExtractorTests.swift` | Download context tests |
| `Tests/TidyCoreTests/Intelligence/ContentIntelligencePipelineTests.swift` | Pipeline integration tests |
| `Tests/TidyCoreTests/Intelligence/SourceCategoryMappingsTests.swift` | Domain mapping tests |

### Modified Files
| File | Change |
|------|--------|
| `Sources/TidyCore/Scoring/ScoringLayer.swift` | Protocol accepts `EnrichedFileContext` |
| `Sources/TidyCore/Scoring/ScoringEngine.swift` | `route()` accepts `EnrichedFileContext` |
| `Sources/TidyCore/Matching/PatternMatcher.swift` | New feature weights, accepts `EnrichedFileContext` |
| `Sources/TidyCore/Heuristics/HeuristicsEngine.swift` | Accepts `EnrichedFileContext` |
| `Sources/TidyCore/Intelligence/AppleIntelligenceLayer.swift` | Accepts `EnrichedFileContext`, uses enriched data in prompt |
| `Sources/TidyCore/Intelligence/ContentExtractor.swift` | Add Office, RTF, EML formats |
| `Sources/TidyCore/Intelligence/InvocationPolicy.swift` | Accept `EnrichedFileContext` for richer decisions |
| `Sources/TidyCore/Models/PatternRecord.swift` | Add new signal columns |
| `Sources/TidyCore/Database/KnowledgeBase.swift` | Migration v2: new columns |
| `Sources/TidyCore/Operations/SignalRecorder.swift` | Record new signal fields |
| `Sources/TidyCore/Orchestrator/MoveOrchestrator.swift` | Run pipeline before scoring |
| `Sources/Tidy/AppState.swift` | Create pipeline, pass `EnrichedFileContext` |
| `Tests/TidyCoreTests/ContentExtractorTests.swift` | Tests for new formats |
| `Tests/TidyCoreTests/PatternMatcherTests.swift` | Update for new weights |
| `Tests/TidyCoreTests/ScoringEngineTests.swift` | Update for `EnrichedFileContext` |
| `Tests/TidyCoreTests/MoveOrchestratorTests.swift` | Update for pipeline |

---

## Task 1: New Model Types

**Files:**
- Create: `Sources/TidyCore/Models/ImageAnalysis.swift`
- Create: `Sources/TidyCore/Models/DownloadContext.swift`
- Create: `Sources/TidyCore/Models/EnrichedFileContext.swift`
- Test: `Tests/TidyCoreTests/EnrichedFileContextTests.swift`

- [ ] **Step 1: Write the test for EnrichedFileContext**

```swift
// Tests/TidyCoreTests/EnrichedFileContextTests.swift
import Testing
@testable import TidyCore

@Suite("EnrichedFileContext")
struct EnrichedFileContextTests {
    @Test("wraps FileCandidate with nil enrichments by default")
    func defaultEnrichment() {
        let candidate = FileCandidate(
            path: "/tmp/test.pdf",
            fileSize: 1024,
            sourceApp: nil,
            downloadURL: nil
        )
        let context = EnrichedFileContext(candidate: candidate)
        #expect(context.candidate.path == "/tmp/test.pdf")
        #expect(context.extractedText == nil)
        #expect(context.imageAnalysis == nil)
        #expect(context.downloadContext == nil)
    }

    @Test("effectiveText returns extractedText when present")
    func effectiveTextFromExtraction() {
        let candidate = FileCandidate(
            path: "/tmp/test.pdf",
            fileSize: 1024,
            sourceApp: nil,
            downloadURL: nil
        )
        let context = EnrichedFileContext(
            candidate: candidate,
            extractedText: "Invoice from Acme Corp"
        )
        #expect(context.effectiveText == "Invoice from Acme Corp")
    }

    @Test("effectiveText falls back to OCR text when extractedText is nil")
    func effectiveTextFallbackToOCR() {
        let candidate = FileCandidate(
            path: "/tmp/scan.pdf",
            fileSize: 2048,
            sourceApp: nil,
            downloadURL: nil
        )
        let imageAnalysis = ImageAnalysis(
            sceneType: .document,
            ocrText: "Scanned invoice text",
            hasFaces: false,
            exifMetadata: nil
        )
        let context = EnrichedFileContext(
            candidate: candidate,
            extractedText: nil,
            imageAnalysis: imageAnalysis
        )
        #expect(context.effectiveText == "Scanned invoice text")
    }

    @Test("SceneType raw values are stable strings")
    func sceneTypeRawValues() {
        #expect(SceneType.screenshot.rawValue == "screenshot")
        #expect(SceneType.photo.rawValue == "photo")
        #expect(SceneType.document.rawValue == "document")
        #expect(SceneType.diagram.rawValue == "diagram")
        #expect(SceneType.receipt.rawValue == "receipt")
        #expect(SceneType.unknown.rawValue == "unknown")
    }

    @Test("SourceCategory raw values are stable strings")
    func sourceCategoryRawValues() {
        #expect(SourceCategory.developer.rawValue == "developer")
        #expect(SourceCategory.googleDrive.rawValue == "googleDrive")
        #expect(SourceCategory.slack.rawValue == "slack")
        #expect(SourceCategory.email.rawValue == "email")
        #expect(SourceCategory.appStore.rawValue == "appStore")
        #expect(SourceCategory.browser.rawValue == "browser")
        #expect(SourceCategory.unknown.rawValue == "unknown")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EnrichedFileContextTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — types don't exist yet

- [ ] **Step 3: Create ImageAnalysis.swift**

```swift
// Sources/TidyCore/Models/ImageAnalysis.swift
import Foundation

public enum SceneType: String, Codable, Sendable {
    case screenshot
    case photo
    case document
    case diagram
    case receipt
    case unknown
}

public struct EXIFMetadata: Sendable {
    public let cameraModel: String?
    public let hasGPS: Bool
    public let creationDate: Date?

    public init(cameraModel: String? = nil, hasGPS: Bool = false, creationDate: Date? = nil) {
        self.cameraModel = cameraModel
        self.hasGPS = hasGPS
        self.creationDate = creationDate
    }
}

public struct ImageAnalysis: Sendable {
    public let sceneType: SceneType
    public let ocrText: String?
    public let hasFaces: Bool
    public let exifMetadata: EXIFMetadata?

    public init(sceneType: SceneType, ocrText: String? = nil, hasFaces: Bool = false, exifMetadata: EXIFMetadata? = nil) {
        self.sceneType = sceneType
        self.ocrText = ocrText
        self.hasFaces = hasFaces
        self.exifMetadata = exifMetadata
    }
}
```

- [ ] **Step 4: Create DownloadContext.swift**

```swift
// Sources/TidyCore/Models/DownloadContext.swift
import Foundation

public enum SourceCategory: String, Codable, Sendable {
    case developer
    case googleDrive
    case slack
    case email
    case appStore
    case browser
    case unknown
}

public struct DownloadContext: Sendable {
    public let sourceURL: URL?
    public let referringURL: URL?
    public let sourceCategory: SourceCategory
    public let quarantineAgent: String?

    public init(sourceURL: URL? = nil, referringURL: URL? = nil, sourceCategory: SourceCategory = .unknown, quarantineAgent: String? = nil) {
        self.sourceURL = sourceURL
        self.referringURL = referringURL
        self.sourceCategory = sourceCategory
        self.quarantineAgent = quarantineAgent
    }
}
```

- [ ] **Step 5: Create EnrichedFileContext.swift**

```swift
// Sources/TidyCore/Models/EnrichedFileContext.swift
import Foundation

public struct EnrichedFileContext: Sendable {
    public let candidate: FileCandidate
    public let extractedText: String?
    public let imageAnalysis: ImageAnalysis?
    public let downloadContext: DownloadContext?

    /// Returns extractedText if available, otherwise falls back to OCR text from image analysis.
    public var effectiveText: String? {
        extractedText ?? imageAnalysis?.ocrText
    }

    public init(
        candidate: FileCandidate,
        extractedText: String? = nil,
        imageAnalysis: ImageAnalysis? = nil,
        downloadContext: DownloadContext? = nil
    ) {
        self.candidate = candidate
        self.extractedText = extractedText
        self.imageAnalysis = imageAnalysis
        self.downloadContext = downloadContext
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter EnrichedFileContextTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/TidyCore/Models/ImageAnalysis.swift Sources/TidyCore/Models/DownloadContext.swift Sources/TidyCore/Models/EnrichedFileContext.swift Tests/TidyCoreTests/EnrichedFileContextTests.swift
git commit -m "feat: add EnrichedFileContext, ImageAnalysis, DownloadContext model types"
```

---

## Task 2: Source Category Domain Mappings

**Files:**
- Create: `Sources/TidyCore/Intelligence/SourceCategoryMappings.swift`
- Test: `Tests/TidyCoreTests/Intelligence/SourceCategoryMappingsTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Intelligence/SourceCategoryMappingsTests.swift
import Testing
@testable import TidyCore

@Suite("SourceCategoryMappings")
struct SourceCategoryMappingsTests {
    let mapper = SourceCategoryMapper()

    @Test("github.com maps to developer")
    func github() {
        #expect(mapper.categorize(domain: "github.com") == .developer)
    }

    @Test("gitlab.com maps to developer")
    func gitlab() {
        #expect(mapper.categorize(domain: "gitlab.com") == .developer)
    }

    @Test("drive.google.com maps to googleDrive")
    func googleDrive() {
        #expect(mapper.categorize(domain: "drive.google.com") == .googleDrive)
    }

    @Test("docs.google.com maps to googleDrive")
    func googleDocs() {
        #expect(mapper.categorize(domain: "docs.google.com") == .googleDrive)
    }

    @Test("slack-files.com maps to slack")
    func slackFiles() {
        #expect(mapper.categorize(domain: "slack-files.com") == .slack)
    }

    @Test("files.slack.com maps to slack")
    func slackCDN() {
        #expect(mapper.categorize(domain: "files.slack.com") == .slack)
    }

    @Test("mail.google.com maps to email")
    func gmail() {
        #expect(mapper.categorize(domain: "mail.google.com") == .email)
    }

    @Test("unknown domain maps to browser")
    func unknownDomain() {
        #expect(mapper.categorize(domain: "example.com") == .browser)
    }

    @Test("categorize from URL extracts domain")
    func fromURL() {
        let url = URL(string: "https://github.com/user/repo/releases/download/v1.0/app.zip")!
        #expect(mapper.categorize(url: url) == .developer)
    }

    @Test("subdomains match parent patterns")
    func subdomain() {
        #expect(mapper.categorize(domain: "objects.githubusercontent.com") == .developer)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SourceCategoryMappingsTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `SourceCategoryMapper` doesn't exist

- [ ] **Step 3: Implement SourceCategoryMapper**

```swift
// Sources/TidyCore/Intelligence/SourceCategoryMappings.swift
import Foundation

public struct SourceCategoryMapper: Sendable {
    /// Domain suffix → category mappings. Order matters: first match wins.
    private static let mappings: [(suffix: String, category: SourceCategory)] = [
        ("github.com", .developer),
        ("githubusercontent.com", .developer),
        ("gitlab.com", .developer),
        ("bitbucket.org", .developer),
        ("drive.google.com", .googleDrive),
        ("docs.google.com", .googleDrive),
        ("slack-files.com", .slack),
        ("files.slack.com", .slack),
        ("slack.com", .slack),
        ("mail.google.com", .email),
        ("outlook.live.com", .email),
        ("outlook.office.com", .email),
        ("figma.com", .developer),
        ("apps.apple.com", .appStore),
    ]

    public init() {}

    public func categorize(domain: String) -> SourceCategory {
        let lowered = domain.lowercased()
        for mapping in Self.mappings {
            if lowered == mapping.suffix || lowered.hasSuffix("." + mapping.suffix) {
                return mapping.category
            }
        }
        return .browser
    }

    public func categorize(url: URL) -> SourceCategory {
        guard let host = url.host() else { return .unknown }
        return categorize(domain: host)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SourceCategoryMappingsTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Intelligence/SourceCategoryMappings.swift Tests/TidyCoreTests/Intelligence/SourceCategoryMappingsTests.swift
git commit -m "feat: add SourceCategoryMapper with domain-to-category mappings"
```

---

## Task 3: Expand ContentExtractor with Office, RTF, EML

**Files:**
- Modify: `Sources/TidyCore/Intelligence/ContentExtractor.swift`
- Test: `Tests/TidyCoreTests/ContentExtractorTests.swift` (modify existing)

- [ ] **Step 1: Write tests for new formats**

Add to the existing `ContentExtractorTests.swift`:

```swift
@Test("extracts text from RTF file")
func extractFromRTF() throws {
    let dir = makeTemporaryDirectory(prefix: "rtf-test")
    defer { removeItem(atPath: dir) }
    // Create a minimal RTF file
    let rtfContent = #"{\rtf1\ansi Hello from RTF document}"#
    let path = dir + "/test.rtf"
    createFile(atPath: path, contents: rtfContent.data(using: .utf8)!)
    let text = ContentExtractor.extractText(from: path)
    #expect(text != nil)
    #expect(text!.contains("Hello from RTF document"))
}

@Test("extracts text from DOCX file")
func extractFromDOCX() throws {
    let dir = makeTemporaryDirectory(prefix: "docx-test")
    defer { removeItem(atPath: dir) }
    let path = dir + "/test.docx"
    // Create a minimal DOCX (zip with word/document.xml)
    createMinimalDOCX(at: path, text: "Hello from DOCX")
    let text = ContentExtractor.extractText(from: path)
    #expect(text != nil)
    #expect(text!.contains("Hello from DOCX"))
}

@Test("extracts text from EML file")
func extractFromEML() throws {
    let dir = makeTemporaryDirectory(prefix: "eml-test")
    defer { removeItem(atPath: dir) }
    let emlContent = """
    From: sender@example.com
    To: recipient@example.com
    Subject: Test Email
    Content-Type: text/plain

    Hello from email body
    """
    let path = dir + "/test.eml"
    createFile(atPath: path, contents: emlContent.data(using: .utf8)!)
    let text = ContentExtractor.extractText(from: path)
    #expect(text != nil)
    #expect(text!.contains("Hello from email body"))
}

@Test("isTextExtractable includes new formats")
func newFormatsAreExtractable() {
    #expect(ContentExtractor.isTextExtractable(extension: "rtf"))
    #expect(ContentExtractor.isTextExtractable(extension: "docx"))
    #expect(ContentExtractor.isTextExtractable(extension: "eml"))
}
```

- [ ] **Step 2: Add DOCX helper to TestHelpers.swift**

Add to `Tests/TidyCoreTests/TestHelpers.swift`:

```swift
import Foundation

/// Creates a minimal .docx file (Office Open XML) with the given text content.
func createMinimalDOCX(at path: String, text: String) {
    // DOCX is a zip containing word/document.xml
    let documentXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:body>
    </w:document>
    """
    let tempDir = makeTemporaryDirectory(prefix: "docx-build")
    defer { removeItem(atPath: tempDir) }

    let wordDir = tempDir + "/word"
    createDirectory(atPath: wordDir)
    createFile(atPath: wordDir + "/document.xml", contents: documentXML.data(using: .utf8)!)

    // Create [Content_Types].xml (required by zip format)
    let contentTypes = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="xml" ContentType="application/xml"/>
    </Types>
    """
    createFile(atPath: tempDir + "/[Content_Types].xml", contents: contentTypes.data(using: .utf8)!)

    // Zip into .docx
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc", tempDir, path]
    try? process.run()
    process.waitUntilExit()
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ContentExtractorTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — new formats not handled

- [ ] **Step 4: Implement new format extraction in ContentExtractor.swift**

Modify `Sources/TidyCore/Intelligence/ContentExtractor.swift`:

```swift
// Sources/TidyCore/Intelligence/ContentExtractor.swift
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public struct ContentExtractor: Sendable {
    private static let textExtensions: Set<String> = ["txt", "md", "csv", "json", "xml", "log", "yaml", "yml"]
    private static let pdfExtensions: Set<String> = ["pdf"]
    private static let rtfExtensions: Set<String> = ["rtf"]
    private static let officeExtensions: Set<String> = ["docx", "xlsx", "pptx"]
    private static let emailExtensions: Set<String> = ["eml"]

    public static func isTextExtractable(extension ext: String) -> Bool {
        let lowered = ext.lowercased()
        return textExtensions.contains(lowered)
            || pdfExtensions.contains(lowered)
            || rtfExtensions.contains(lowered)
            || officeExtensions.contains(lowered)
            || emailExtensions.contains(lowered)
    }

    public static func extractText(from path: String, maxWords: Int = 500) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        if textExtensions.contains(ext) {
            return extractFromTextFile(path: path, maxWords: maxWords)
        } else if pdfExtensions.contains(ext) {
            return extractFromPDF(path: path, maxWords: maxWords)
        } else if rtfExtensions.contains(ext) {
            return extractFromRTF(path: path, maxWords: maxWords)
        } else if officeExtensions.contains(ext) {
            return extractFromOfficeXML(path: path, extension: ext, maxWords: maxWords)
        } else if emailExtensions.contains(ext) {
            return extractFromEML(path: path, maxWords: maxWords)
        }
        return nil
    }

    private static func extractFromTextFile(path: String, maxWords: Int) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return truncateToWords(content, maxWords: maxWords)
    }

    private static func extractFromPDF(path: String, maxWords: Int) -> String? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { return nil }
        var text = ""
        let pageLimit = min(doc.pageCount, 5)
        for i in 0..<pageLimit {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + " "
            }
        }
        return text.isEmpty ? nil : truncateToWords(text, maxWords: maxWords)
        #else
        return nil
        #endif
    }

    private static func extractFromRTF(path: String, maxWords: Int) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        let text = attributed.string
        return text.isEmpty ? nil : truncateToWords(text, maxWords: maxWords)
    }

    private static func extractFromOfficeXML(path: String, extension ext: String, maxWords: Int) -> String? {
        // Office Open XML files are ZIP archives containing XML
        let url = URL(fileURLWithPath: path)
        guard let archive = try? Data(contentsOf: url) else { return nil }

        // Determine the XML path inside the archive
        let xmlPath: String
        switch ext {
        case "docx": xmlPath = "word/document.xml"
        case "xlsx": xmlPath = "xl/sharedStrings.xml"
        case "pptx": xmlPath = "ppt/slides/slide1.xml"
        default: return nil
        }

        // Use Process to extract via unzip
        let tempDir = NSTemporaryDirectory() + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-d", tempDir, path, xmlPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }

        guard process.terminationStatus == 0 else { return nil }
        let extractedPath = tempDir + "/" + xmlPath
        guard let xmlData = FileManager.default.contents(atPath: extractedPath),
              let xmlString = String(data: xmlData, encoding: .utf8) else { return nil }

        // Strip XML tags to get plain text
        let stripped = xmlString.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        ).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        return stripped.isEmpty ? nil : truncateToWords(stripped, maxWords: maxWords)
    }

    private static func extractFromEML(path: String, maxWords: Int) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        // Split headers from body at first blank line
        let parts = content.components(separatedBy: "\n\n")
        guard parts.count >= 2 else { return nil }
        let body = parts.dropFirst().joined(separator: "\n\n")
        return body.isEmpty ? nil : truncateToWords(body, maxWords: maxWords)
    }

    private static func truncateToWords(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ", maxSplits: maxWords, omittingEmptySubsequences: true)
        return words.prefix(maxWords).joined(separator: " ")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ContentExtractorTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TidyCore/Intelligence/ContentExtractor.swift Tests/TidyCoreTests/ContentExtractorTests.swift Tests/TidyCoreTests/TestHelpers.swift
git commit -m "feat: expand ContentExtractor with RTF, DOCX, EML support"
```

---

## Task 4: Download Context Extractor

**Files:**
- Create: `Sources/TidyCore/Intelligence/DownloadContextExtractor.swift`
- Test: `Tests/TidyCoreTests/Intelligence/DownloadContextExtractorTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Intelligence/DownloadContextExtractorTests.swift
import Testing
@testable import TidyCore

@Suite("DownloadContextExtractor")
struct DownloadContextExtractorTests {
    let extractor = DownloadContextExtractor()

    @Test("extracts context from URL string in metadata")
    func fromMetadataURL() {
        let context = extractor.contextFromURL("https://github.com/user/repo/releases/download/v1.0/app.zip")
        #expect(context.sourceCategory == .developer)
        #expect(context.sourceURL?.host() == "github.com")
    }

    @Test("extracts context from Google Drive URL")
    func fromGoogleDrive() {
        let context = extractor.contextFromURL("https://drive.google.com/uc?id=abc123")
        #expect(context.sourceCategory == .googleDrive)
    }

    @Test("returns browser category for unknown domain")
    func unknownDomain() {
        let context = extractor.contextFromURL("https://randomsite.com/file.zip")
        #expect(context.sourceCategory == .browser)
    }

    @Test("handles nil URL gracefully")
    func nilURL() {
        let context = extractor.contextFromURL(nil)
        #expect(context.sourceCategory == .unknown)
        #expect(context.sourceURL == nil)
    }

    @Test("handles malformed URL string")
    func malformedURL() {
        let context = extractor.contextFromURL("not a url at all")
        #expect(context.sourceCategory == .unknown)
    }

    @Test("extracts quarantine agent from string")
    func quarantineAgent() {
        // Quarantine xattr format: flags;timestamp;agent;uuid
        let agent = DownloadContextExtractor.parseQuarantineAgent(from: "0083;5f3b3c00;Safari;12345")
        #expect(agent == "Safari")
    }

    @Test("handles missing quarantine agent")
    func missingQuarantineAgent() {
        let agent = DownloadContextExtractor.parseQuarantineAgent(from: nil)
        #expect(agent == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DownloadContextExtractorTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL

- [ ] **Step 3: Implement DownloadContextExtractor**

```swift
// Sources/TidyCore/Intelligence/DownloadContextExtractor.swift
import Foundation

public struct DownloadContextExtractor: Sendable {
    private let categoryMapper = SourceCategoryMapper()

    public init() {}

    /// Extract download context from a file's extended attributes.
    public func extract(fromPath path: String) -> DownloadContext {
        let whereFroms = readWhereFroms(path: path)
        let quarantineRaw = readXattr(path: path, name: "com.apple.quarantine")
        let quarantineAgent = Self.parseQuarantineAgent(from: quarantineRaw)

        let sourceURLString = whereFroms.first
        let referringURLString = whereFroms.count > 1 ? whereFroms[1] : nil

        return contextFromURLStrings(
            source: sourceURLString,
            referring: referringURLString,
            quarantineAgent: quarantineAgent
        )
    }

    /// Build context from a URL string (for testing or when URL is already known).
    public func contextFromURL(_ urlString: String?) -> DownloadContext {
        return contextFromURLStrings(source: urlString, referring: nil, quarantineAgent: nil)
    }

    private func contextFromURLStrings(source: String?, referring: String?, quarantineAgent: String?) -> DownloadContext {
        guard let source, let url = URL(string: source) else {
            return DownloadContext(sourceCategory: .unknown, quarantineAgent: quarantineAgent)
        }
        let category = categoryMapper.categorize(url: url)
        let referringURL = referring.flatMap { URL(string: $0) }
        return DownloadContext(
            sourceURL: url,
            referringURL: referringURL,
            sourceCategory: category,
            quarantineAgent: quarantineAgent
        )
    }

    /// Parse the agent name from a quarantine xattr value.
    /// Format: flags;timestamp;agentName;uuid
    public static func parseQuarantineAgent(from value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let agent = String(parts[2])
        return agent.isEmpty ? nil : agent
    }

    private func readWhereFroms(path: String) -> [String] {
        guard let data = readXattrData(path: path, name: "com.apple.metadata:kMDItemWhereFroms") else {
            return []
        }
        // kMDItemWhereFroms is stored as a binary plist array of strings
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let urls = plist as? [String] else {
            return []
        }
        return urls
    }

    private func readXattr(path: String, name: String) -> String? {
        guard let data = readXattrData(path: path, name: name) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readXattrData(path: String, name: String) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        let result = getxattr(path, name, &buffer, length, 0, 0)
        guard result > 0 else { return nil }
        return Data(buffer[0..<result])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DownloadContextExtractorTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Intelligence/DownloadContextExtractor.swift Tests/TidyCoreTests/Intelligence/DownloadContextExtractorTests.swift
git commit -m "feat: add DownloadContextExtractor for xattr-based download provenance"
```

---

## Task 5: Image Analyzer

**Files:**
- Create: `Sources/TidyCore/Intelligence/ImageAnalyzer.swift`
- Test: `Tests/TidyCoreTests/Intelligence/ImageAnalyzerTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Intelligence/ImageAnalyzerTests.swift
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

    @Test("extractEXIF returns nil for non-image file")
    func noEXIFForText() {
        let dir = makeTemporaryDirectory(prefix: "exif-test")
        defer { removeItem(atPath: dir) }
        let path = dir + "/test.txt"
        createFile(atPath: path, contents: "not an image".data(using: .utf8)!)
        let exif = ImageAnalyzer.extractEXIF(from: path)
        #expect(exif == nil)
    }

    @Test("analyze returns nil for non-image file")
    func nonImageReturnsNil() async {
        let dir = makeTemporaryDirectory(prefix: "analyze-test")
        defer { removeItem(atPath: dir) }
        let path = dir + "/test.txt"
        createFile(atPath: path, contents: "not an image".data(using: .utf8)!)
        let result = await ImageAnalyzer.analyze(path: path)
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImageAnalyzerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL

- [ ] **Step 3: Implement ImageAnalyzer**

```swift
// Sources/TidyCore/Intelligence/ImageAnalyzer.swift
import Foundation
import Vision
import ImageIO

public struct ImageAnalyzer: Sendable {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]

    private static let labelToSceneType: [String: SceneType] = [
        "document": .document,
        "text": .document,
        "screenshot": .screenshot,
        "people": .photo,
        "portrait": .photo,
        "landscape": .photo,
        "nature": .photo,
        "food": .photo,
        "animal": .photo,
        "diagram": .diagram,
        "chart": .diagram,
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

        // Only return if we found any useful metadata
        guard cameraModel != nil || hasGPS || creationDate != nil else { return nil }

        return EXIFMetadata(cameraModel: cameraModel, hasGPS: hasGPS, creationDate: creationDate)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ImageAnalyzerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Intelligence/ImageAnalyzer.swift Tests/TidyCoreTests/Intelligence/ImageAnalyzerTests.swift
git commit -m "feat: add ImageAnalyzer with Vision framework scene/OCR/face/EXIF analysis"
```

---

## Task 6: Content Intelligence Pipeline

**Files:**
- Create: `Sources/TidyCore/Intelligence/ContentIntelligencePipeline.swift`
- Test: `Tests/TidyCoreTests/Intelligence/ContentIntelligencePipelineTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Intelligence/ContentIntelligencePipelineTests.swift
import Testing
@testable import TidyCore

@Suite("ContentIntelligencePipeline")
struct ContentIntelligencePipelineTests {
    @Test("enriches text file with extracted text")
    func enrichTextFile() async {
        let dir = makeTemporaryDirectory(prefix: "pipeline-test")
        defer { removeItem(atPath: dir) }
        let path = dir + "/readme.txt"
        createFile(atPath: path, contents: "Hello world from a text file".data(using: .utf8)!)

        let candidate = FileCandidate(path: path, fileSize: 28, sourceApp: nil, downloadURL: nil)
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.candidate.path == path)
        #expect(context.extractedText != nil)
        #expect(context.extractedText!.contains("Hello world"))
        #expect(context.imageAnalysis == nil) // not an image
    }

    @Test("passes through candidate when no enrichment applies")
    func noEnrichment() async {
        let candidate = FileCandidate(
            path: "/tmp/nonexistent.xyz",
            fileSize: 100,
            sourceApp: nil,
            downloadURL: nil
        )
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.candidate.path == "/tmp/nonexistent.xyz")
        #expect(context.extractedText == nil)
        #expect(context.imageAnalysis == nil)
        #expect(context.downloadContext == nil)
    }

    @Test("enriches with download context from downloadURL")
    func enrichWithDownloadURL() async {
        let candidate = FileCandidate(
            path: "/tmp/test.zip",
            fileSize: 1024,
            sourceApp: nil,
            downloadURL: "https://github.com/user/repo/releases/download/v1.0/test.zip"
        )
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.downloadContext != nil)
        #expect(context.downloadContext?.sourceCategory == .developer)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContentIntelligencePipelineTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL

- [ ] **Step 3: Implement ContentIntelligencePipeline**

```swift
// Sources/TidyCore/Intelligence/ContentIntelligencePipeline.swift
import Foundation

public struct ContentIntelligencePipeline: Sendable {
    private let downloadContextExtractor = DownloadContextExtractor()

    public init() {}

    /// Run all enrichment stages (text, image, download context) and produce an EnrichedFileContext.
    public func enrich(_ candidate: FileCandidate) async -> EnrichedFileContext {
        // Stage 1: Text extraction (cheap, always run)
        let extractedText: String? = if let ext = candidate.fileExtension,
            ContentExtractor.isTextExtractable(extension: ext) {
            ContentExtractor.extractText(from: candidate.path)
        } else {
            nil
        }

        // Stage 2: Image analysis (moderate cost, run for images only)
        let imageAnalysis: ImageAnalysis? = if let ext = candidate.fileExtension,
            ImageAnalyzer.isImageFile(extension: ext) {
            await ImageAnalyzer.analyze(path: candidate.path)
        } else {
            nil
        }

        // Stage 3: Download context (free, always run)
        // First try xattrs on the actual file, then fall back to metadata URL
        var downloadContext = downloadContextExtractor.extract(fromPath: candidate.path)
        if downloadContext.sourceCategory == .unknown, let urlString = candidate.downloadURL {
            downloadContext = downloadContextExtractor.contextFromURL(urlString)
        }

        return EnrichedFileContext(
            candidate: candidate,
            extractedText: extractedText,
            imageAnalysis: imageAnalysis,
            downloadContext: downloadContext.sourceCategory == .unknown && downloadContext.sourceURL == nil ? nil : downloadContext
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContentIntelligencePipelineTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Intelligence/ContentIntelligencePipeline.swift Tests/TidyCoreTests/Intelligence/ContentIntelligencePipelineTests.swift
git commit -m "feat: add ContentIntelligencePipeline composing text, image, download stages"
```

---

## Task 7: Database Migration — New Pattern Record Columns

**Files:**
- Modify: `Sources/TidyCore/Models/PatternRecord.swift`
- Modify: `Sources/TidyCore/Database/KnowledgeBase.swift`
- Test: `Tests/TidyCoreTests/KnowledgeBaseTests.swift` (modify existing)

- [ ] **Step 1: Write migration test**

Add to `KnowledgeBaseTests.swift`:

```swift
@Test("migration v2 adds new columns to pattern_records")
func migrationV2() throws {
    let kb = try KnowledgeBase.inMemory()
    // Record a pattern with new fields
    try kb.recordPattern(
        fileExtension: "pdf",
        filenameTokens: ["invoice"],
        sourceApp: "Safari",
        sizeBucket: "medium",
        timeBucket: "morning",
        documentType: "invoice",
        sourceDomain: "mail.google.com",
        sceneType: "document",
        sourceFolder: "/Users/test/Downloads",
        destination: "/Users/test/Documents/Invoices",
        signalType: .observation,
        weight: 1.0
    )
    let patterns = try kb.allPatterns()
    #expect(patterns.count == 1)
    #expect(patterns[0].documentType == "invoice")
    #expect(patterns[0].sourceDomain == "mail.google.com")
    #expect(patterns[0].sceneType == "document")
    #expect(patterns[0].sourceFolder == "/Users/test/Downloads")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KnowledgeBaseTests/migrationV2 -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL

- [ ] **Step 3: Add new fields to PatternRecord**

Modify `Sources/TidyCore/Models/PatternRecord.swift`:

```swift
public struct PatternRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var fileExtension: String?
    public var filenameTokens: String?    // JSON-encoded [String]
    public var sourceApp: String?
    public var sizeBucket: String?
    public var timeBucket: String?
    public var documentType: String?
    public var sourceDomain: String?
    public var sceneType: String?
    public var sourceFolder: String?
    public var destination: String
    public var signalType: SignalType
    public var weight: Double
    public var createdAt: Date
    public var syncedAt: Date?

    public static let databaseTableName = "pattern_records"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 4: Add migration v2 to KnowledgeBase**

Add after the existing migration in `KnowledgeBase.swift`, inside the `migrator.registerMigration` block structure:

```swift
migrator.registerMigration("v2") { db in
    try db.alter(table: "pattern_records") { t in
        t.add(column: "documentType", .text)
        t.add(column: "sourceDomain", .text)
        t.add(column: "sceneType", .text)
        t.add(column: "sourceFolder", .text)
        t.add(column: "syncedAt", .double)
    }
    try db.alter(table: "move_records") { t in
        t.add(column: "batchId", .text)
    }
}
```

- [ ] **Step 5: Update `recordPattern` method to accept new fields**

Modify the `recordPattern` method in `KnowledgeBase.swift` to include the new parameters (with defaults of `nil` for backward compatibility):

```swift
public func recordPattern(
    fileExtension: String?,
    filenameTokens: [String],
    sourceApp: String?,
    sizeBucket: String?,
    timeBucket: String?,
    documentType: String? = nil,
    sourceDomain: String? = nil,
    sceneType: String? = nil,
    sourceFolder: String? = nil,
    destination: String,
    signalType: SignalType,
    weight: Double
) throws {
    var record = PatternRecord(
        fileExtension: fileExtension,
        filenameTokens: try? JSONEncoder().encode(filenameTokens).base64EncodedString(),
        sourceApp: sourceApp,
        sizeBucket: sizeBucket,
        timeBucket: timeBucket,
        documentType: documentType,
        sourceDomain: sourceDomain,
        sceneType: sceneType,
        sourceFolder: sourceFolder,
        destination: destination,
        signalType: signalType,
        weight: weight,
        createdAt: Date(),
        syncedAt: nil
    )
    try dbQueue.write { db in
        try record.insert(db)
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter KnowledgeBaseTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS (all existing tests should still pass with the new optional fields)

- [ ] **Step 7: Commit**

```bash
git add Sources/TidyCore/Models/PatternRecord.swift Sources/TidyCore/Database/KnowledgeBase.swift Tests/TidyCoreTests/KnowledgeBaseTests.swift
git commit -m "feat: add v2 migration with document_type, source_domain, scene_type, source_folder columns"
```

---

## Task 8: Update ScoringLayer Protocol

**Files:**
- Modify: `Sources/TidyCore/Scoring/ScoringLayer.swift`
- Modify: `Sources/TidyCore/Heuristics/HeuristicsEngine.swift`
- Modify: `Sources/TidyCore/Matching/PatternMatcher.swift`
- Modify: `Sources/TidyCore/Intelligence/AppleIntelligenceLayer.swift`
- Modify: `Sources/TidyCore/Scoring/ScoringEngine.swift`
- Test: existing tests must still compile and pass

- [ ] **Step 1: Change the protocol**

Modify `Sources/TidyCore/Scoring/ScoringLayer.swift`:

```swift
import Foundation

public protocol ScoringLayer: Sendable {
    func score(_ context: EnrichedFileContext) async throws -> [ScoredDestination]
}
```

- [ ] **Step 2: Update HeuristicsEngine to accept EnrichedFileContext**

In `Sources/TidyCore/Heuristics/HeuristicsEngine.swift`, change the method signature:

```swift
public func score(_ context: EnrichedFileContext) async throws -> [ScoredDestination] {
```

Replace all references to `candidate` with `context.candidate` inside the method body. The heuristics engine doesn't use enrichment data — it just passes through to the candidate.

- [ ] **Step 3: Update PatternMatcher to accept EnrichedFileContext and use new weights**

Modify `Sources/TidyCore/Matching/PatternMatcher.swift`:

```swift
public struct PatternMatcher: Sendable {
    private let knowledgeBase: KnowledgeBase
    // V2 feature weights (fixed constants)
    private let extensionWeight: Double = 0.25
    private let tokenWeight: Double = 0.20
    private let sceneTypeWeight: Double = 0.15
    private let sourceDomainWeight: Double = 0.15
    private let sourceAppWeight: Double = 0.10
    private let sizeBucketWeight: Double = 0.10
    private let timeBucketWeight: Double = 0.05

    public init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    public func score(_ context: EnrichedFileContext) async throws -> [ScoredDestination] {
        let candidate = context.candidate
        let patterns = try knowledgeBase.allPatterns()
        guard !patterns.isEmpty else { return [] }

        var scores: [String: Double] = [:]
        var reasons: [String: String] = [:]

        for pattern in patterns {
            var score = 0.0
            var maxScore = 0.0
            var matchReasons: [String] = []

            // Extension match
            if let ext = candidate.fileExtension, let patExt = pattern.fileExtension {
                maxScore += extensionWeight
                if ext.lowercased() == patExt.lowercased() {
                    score += extensionWeight
                    matchReasons.append("ext:\(ext)")
                }
            }

            // Token overlap
            if let tokensJSON = pattern.filenameTokens,
               let data = Data(base64Encoded: tokensJSON),
               let patternTokens = try? JSONDecoder().decode([String].self, from: data) {
                maxScore += tokenWeight
                let overlap = Set(candidate.filenameTokens).intersection(Set(patternTokens))
                if !overlap.isEmpty {
                    let ratio = Double(overlap.count) / Double(max(patternTokens.count, 1))
                    score += tokenWeight * ratio
                    matchReasons.append("tokens:\(overlap.count)")
                }
            }

            // Scene type match (new in v2)
            if let sceneType = context.imageAnalysis?.sceneType,
               let patternScene = pattern.sceneType {
                maxScore += sceneTypeWeight
                if sceneType.rawValue == patternScene {
                    score += sceneTypeWeight
                    matchReasons.append("scene:\(sceneType.rawValue)")
                }
            }

            // Source domain match (new in v2)
            if let sourceCategory = context.downloadContext?.sourceCategory,
               let patternDomain = pattern.sourceDomain {
                maxScore += sourceDomainWeight
                if sourceCategory.rawValue == patternDomain || context.downloadContext?.sourceURL?.host() == patternDomain {
                    score += sourceDomainWeight
                    matchReasons.append("source:\(patternDomain)")
                }
            }

            // Source app match
            if let app = candidate.sourceApp, let patApp = pattern.sourceApp {
                maxScore += sourceAppWeight
                if app.lowercased() == patApp.lowercased() {
                    score += sourceAppWeight
                    matchReasons.append("app:\(app)")
                }
            }

            // Size bucket match
            if let patSize = pattern.sizeBucket {
                maxScore += sizeBucketWeight
                if candidate.sizeBucket.rawValue == patSize {
                    score += sizeBucketWeight
                    matchReasons.append("size:\(patSize)")
                }
            }

            // Time bucket match
            if let patTime = pattern.timeBucket {
                maxScore += timeBucketWeight
                if candidate.timeBucket.rawValue == patTime {
                    score += timeBucketWeight
                    matchReasons.append("time:\(patTime)")
                }
            }

            guard maxScore > 0 else { continue }
            let normalizedScore = (score / maxScore) * pattern.weight
            let dest = pattern.destination
            scores[dest, default: 0] += normalizedScore
            if reasons[dest] == nil || normalizedScore > 0 {
                reasons[dest] = matchReasons.joined(separator: ", ")
            }
        }

        guard let maxVal = scores.values.max(), maxVal > 0 else { return [] }

        return scores.map { dest, score in
            ScoredDestination(
                path: dest,
                confidence: score / maxVal,
                reason: reasons[dest] ?? ""
            )
        }.sorted { $0.confidence > $1.confidence }
    }
}
```

- [ ] **Step 4: Update AppleIntelligenceLayer**

In `Sources/TidyCore/Intelligence/AppleIntelligenceLayer.swift`, change the method signature and use enriched data:

```swift
public func score(_ context: EnrichedFileContext) async throws -> [ScoredDestination] {
    let candidate = context.candidate

    // Check invocation policy
    guard invocationPolicy.shouldInvoke(
        extension: candidate.fileExtension,
        patternConfidence: nil,
        isScreenshot: candidate.metadata?.isScreenCapture ?? false
    ) else { return [] }

    // Build enriched prompt
    var prompt = "Classify this file:\n"
    prompt += "Filename: \(candidate.filename)\n"
    if let url = candidate.downloadURL {
        prompt += "Downloaded from: \(url)\n"
    }
    if let text = context.effectiveText {
        prompt += "Content preview: \(String(text.prefix(300)))\n"
    }
    if let scene = context.imageAnalysis?.sceneType, scene != .unknown {
        prompt += "Image type: \(scene.rawValue)\n"
    }
    if let source = context.downloadContext?.sourceCategory, source != .unknown {
        prompt += "Source: \(source.rawValue)\n"
    }
    prompt += "\nExisting folders: \(existingFolders.joined(separator: ", "))\n"
    prompt += "Pick the best folder or suggest a new subfolder."

    // ... rest of Foundation Models call stays the same
```

- [ ] **Step 5: Update ScoringEngine.route() to accept EnrichedFileContext**

In `Sources/TidyCore/Scoring/ScoringEngine.swift`, change:

```swift
public func route(_ context: EnrichedFileContext) async throws -> RoutingDecision? {
    let candidate = context.candidate
    // Pinned rules check (uses candidate)
    if let match = pinnedRulesManager.match(candidate) {
        // ... same pinned rule logic
    }

    // Score through all layers with EnrichedFileContext
    let patternScores = try await patternMatcher.score(context)
    // ... rest uses context instead of candidate
```

- [ ] **Step 6: Run all tests to verify compilation and existing tests pass**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: All existing tests pass (may need minor updates to test files where `FileCandidate` was passed directly — wrap in `EnrichedFileContext(candidate:)`)

- [ ] **Step 7: Update test files to use EnrichedFileContext**

Update `ScoringEngineTests.swift`, `PatternMatcherTests.swift`, `HeuristicsEngineTests.swift`, and `MoveOrchestratorTests.swift` to wrap `FileCandidate` in `EnrichedFileContext(candidate:)` where `score()` or `route()` is called.

- [ ] **Step 8: Run all tests again**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: ALL PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/TidyCore/Scoring/ Sources/TidyCore/Matching/ Sources/TidyCore/Heuristics/HeuristicsEngine.swift Sources/TidyCore/Intelligence/AppleIntelligenceLayer.swift Tests/TidyCoreTests/
git commit -m "feat: update ScoringLayer protocol to accept EnrichedFileContext

All scoring layers (PatternMatcher, HeuristicsEngine, AppleIntelligenceLayer)
now accept EnrichedFileContext. PatternMatcher uses expanded feature weights
including scene type and source domain signals."
```

---

## Task 9: Update SignalRecorder with New Fields

**Files:**
- Modify: `Sources/TidyCore/Operations/SignalRecorder.swift`
- Test: `Tests/TidyCoreTests/SignalRecorderTests.swift` (modify existing)

- [ ] **Step 1: Write the test**

Add to `SignalRecorderTests.swift`:

```swift
@Test("records observation with enriched context fields")
func recordEnrichedObservation() throws {
    let kb = try KnowledgeBase.inMemory()
    let recorder = SignalRecorder(knowledgeBase: kb)
    let candidate = FileCandidate(
        path: "/tmp/invoice.pdf",
        fileSize: 2048,
        sourceApp: "Safari",
        downloadURL: "https://mail.google.com/attachment"
    )
    let context = EnrichedFileContext(
        candidate: candidate,
        extractedText: "Invoice from Acme",
        downloadContext: DownloadContext(
            sourceURL: URL(string: "https://mail.google.com/attachment"),
            sourceCategory: .email
        )
    )
    recorder.recordObservation(context: context, destination: "/Users/test/Documents/Invoices")

    let patterns = try kb.allPatterns()
    #expect(patterns.count == 1)
    #expect(patterns[0].sourceDomain == "email")
    #expect(patterns[0].sourceFolder == "/tmp")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SignalRecorderTests/recordEnrichedObservation -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL

- [ ] **Step 3: Update SignalRecorder**

Modify `Sources/TidyCore/Operations/SignalRecorder.swift` to add new methods that accept `EnrichedFileContext`:

```swift
public struct SignalRecorder: Sendable {
    private let knowledgeBase: KnowledgeBase

    public init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    // MARK: - EnrichedFileContext methods (v2)

    public func recordObservation(context: EnrichedFileContext, destination: String) {
        let candidate = context.candidate
        let sourceFolder = (candidate.path as NSString).deletingLastPathComponent
        try? knowledgeBase.recordPattern(
            fileExtension: candidate.fileExtension,
            filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp,
            sizeBucket: candidate.sizeBucket.rawValue,
            timeBucket: candidate.timeBucket.rawValue,
            documentType: context.imageAnalysis?.sceneType.rawValue,
            sourceDomain: context.downloadContext?.sourceCategory.rawValue,
            sceneType: context.imageAnalysis?.sceneType.rawValue,
            sourceFolder: sourceFolder,
            destination: destination,
            signalType: .observation,
            weight: SignalType.observation.defaultWeight
        )
    }

    public func recordCorrection(context: EnrichedFileContext, wrongDestination: String, correctDestination: String) {
        let candidate = context.candidate
        let sourceFolder = (candidate.path as NSString).deletingLastPathComponent
        try? knowledgeBase.recordPattern(
            fileExtension: candidate.fileExtension,
            filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp,
            sizeBucket: candidate.sizeBucket.rawValue,
            timeBucket: candidate.timeBucket.rawValue,
            documentType: context.imageAnalysis?.sceneType.rawValue,
            sourceDomain: context.downloadContext?.sourceCategory.rawValue,
            sceneType: context.imageAnalysis?.sceneType.rawValue,
            sourceFolder: sourceFolder,
            destination: correctDestination,
            signalType: .correction,
            weight: SignalType.correction.defaultWeight
        )
    }

    public func recordConfirmation(context: EnrichedFileContext, destination: String) {
        let candidate = context.candidate
        let sourceFolder = (candidate.path as NSString).deletingLastPathComponent
        try? knowledgeBase.recordPattern(
            fileExtension: candidate.fileExtension,
            filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp,
            sizeBucket: candidate.sizeBucket.rawValue,
            timeBucket: candidate.timeBucket.rawValue,
            documentType: context.imageAnalysis?.sceneType.rawValue,
            sourceDomain: context.downloadContext?.sourceCategory.rawValue,
            sceneType: context.imageAnalysis?.sceneType.rawValue,
            sourceFolder: sourceFolder,
            destination: destination,
            signalType: .confirmation,
            weight: SignalType.confirmation.defaultWeight
        )
    }

    // MARK: - Legacy FileCandidate methods (kept for backward compatibility)

    public func recordObservation(candidate: FileCandidate, destination: String) {
        recordObservation(context: EnrichedFileContext(candidate: candidate), destination: destination)
    }

    public func recordCorrection(candidate: FileCandidate, wrongDestination: String, correctDestination: String) {
        recordCorrection(context: EnrichedFileContext(candidate: candidate), wrongDestination: wrongDestination, correctDestination: correctDestination)
    }

    public func recordConfirmation(candidate: FileCandidate, destination: String) {
        recordConfirmation(context: EnrichedFileContext(candidate: candidate), destination: destination)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SignalRecorderTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Operations/SignalRecorder.swift Tests/TidyCoreTests/SignalRecorderTests.swift
git commit -m "feat: update SignalRecorder to record enriched context fields"
```

---

## Task 10: Update MoveOrchestrator to Run Pipeline

**Files:**
- Modify: `Sources/TidyCore/Orchestrator/MoveOrchestrator.swift`
- Test: `Tests/TidyCoreTests/MoveOrchestratorTests.swift` (update existing)

- [ ] **Step 1: Write integration test**

Add to `MoveOrchestratorTests.swift`:

```swift
@Test("processFile enriches candidate through pipeline before scoring")
func processFileWithPipeline() async throws {
    let dir = makeTemporaryDirectory(prefix: "orch-pipeline")
    defer { removeItem(atPath: dir) }

    // Create a text file
    let filePath = dir + "/readme.txt"
    createFile(atPath: filePath, contents: "Important document content".data(using: .utf8)!)

    let kb = try KnowledgeBase.inMemory()
    let engine = ScoringEngine(
        patternMatcher: PatternMatcher(knowledgeBase: kb),
        heuristicsEngine: HeuristicsEngine(affinities: [], clusters: []),
        pinnedRulesManager: PinnedRulesManager(),
        knowledgeBase: kb
    )
    let pipeline = ContentIntelligencePipeline()
    let orchestrator = MoveOrchestrator(
        scoringEngine: engine,
        knowledgeBase: kb,
        pipeline: pipeline
    )

    let candidate = FileCandidate(path: filePath, fileSize: 25, sourceApp: nil, downloadURL: nil)
    let event = try await orchestrator.processFile(candidate)

    // File should be processed (newFile since no patterns exist yet)
    #expect(event != nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MoveOrchestratorTests/processFileWithPipeline -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `MoveOrchestrator` doesn't accept `pipeline` parameter

- [ ] **Step 3: Update MoveOrchestrator**

Modify `Sources/TidyCore/Orchestrator/MoveOrchestrator.swift`:

```swift
public actor MoveOrchestrator {
    private let scoringEngine: ScoringEngine
    private let knowledgeBase: KnowledgeBase
    private let pipeline: ContentIntelligencePipeline
    // ... existing properties

    public init(
        scoringEngine: ScoringEngine,
        knowledgeBase: KnowledgeBase,
        pipeline: ContentIntelligencePipeline = ContentIntelligencePipeline(),
        settleSeconds: TimeInterval = 5.0
    ) {
        self.scoringEngine = scoringEngine
        self.knowledgeBase = knowledgeBase
        self.pipeline = pipeline
        // ... rest of init
    }

    public func processFile(_ candidate: FileCandidate) async throws -> OrchestratorEvent? {
        guard !ignoreFilter.shouldIgnore(filename: candidate.filename) else { return nil }
        guard !isPaused else { return nil }

        // Enrich through pipeline before scoring
        let context = await pipeline.enrich(candidate)

        guard let decision = try await scoringEngine.route(context) else {
            return .newFile(candidate: candidate)
        }
        // ... rest uses decision as before
    }

    // Update signal recording methods to pass EnrichedFileContext where available
    // For recordUserMove (external observation), create minimal context
    public func recordUserMove(filename: String, fileSize: UInt64, destination: String) async throws -> OrchestratorEvent? {
        let candidate = FileCandidate(path: destination + "/" + filename, fileSize: fileSize, sourceApp: nil, downloadURL: nil)
        let context = EnrichedFileContext(candidate: candidate)
        signalRecorder.recordObservation(context: context, destination: destination)
        return .observed(filename: filename, destination: destination)
    }
```

- [ ] **Step 4: Run all orchestrator tests**

Run: `swift test --filter MoveOrchestratorTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Orchestrator/MoveOrchestrator.swift Tests/TidyCoreTests/MoveOrchestratorTests.swift
git commit -m "feat: integrate ContentIntelligencePipeline into MoveOrchestrator"
```

---

## Task 11: Update AppState

**Files:**
- Modify: `Sources/Tidy/AppState.swift`

- [ ] **Step 1: Update AppState.start() to create pipeline**

In `Sources/Tidy/AppState.swift`, add the pipeline property and pass it to MoveOrchestrator:

```swift
// Add property
private var pipeline: ContentIntelligencePipeline?

// In start(), after creating scoringEngine:
let pipeline = ContentIntelligencePipeline()
self.pipeline = pipeline

// Pass to orchestrator
orchestrator = MoveOrchestrator(
    scoringEngine: scoringEngine,
    knowledgeBase: kb,
    pipeline: pipeline
)
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/Tidy/AppState.swift
git commit -m "feat: wire ContentIntelligencePipeline into AppState"
```

---

## Task 12: Update InvocationPolicy for Enriched Context

**Files:**
- Modify: `Sources/TidyCore/Intelligence/InvocationPolicy.swift`
- Test: `Tests/TidyCoreTests/InvocationPolicyTests.swift` (update existing)

- [ ] **Step 1: Write test for enriched policy**

Add to `InvocationPolicyTests.swift`:

```swift
@Test("skips invocation when download context provides high-confidence signal")
func skipWhenDownloadContextStrong() {
    let policy = InvocationPolicy()
    // If pattern confidence is already high, don't invoke even with enrichment
    #expect(!policy.shouldInvoke(extension: "pdf", patternConfidence: 90, isScreenshot: false))
}

@Test("invokes for text-extractable files with low confidence")
func invokeForTextFiles() {
    let policy = InvocationPolicy()
    #expect(policy.shouldInvoke(extension: "pdf", patternConfidence: 30, isScreenshot: false))
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter InvocationPolicyTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS (existing logic already handles these cases)

- [ ] **Step 3: Commit (if any changes needed)**

```bash
git add Sources/TidyCore/Intelligence/InvocationPolicy.swift Tests/TidyCoreTests/InvocationPolicyTests.swift
git commit -m "test: verify InvocationPolicy works correctly with enriched context"
```

---

## Task 13: Final Integration Test

**Files:**
- Test: `Tests/TidyCoreTests/ContentIntelligenceIntegrationTests.swift`

- [ ] **Step 1: Write end-to-end integration test**

```swift
// Tests/TidyCoreTests/ContentIntelligenceIntegrationTests.swift
import Testing
@testable import TidyCore

@Suite("Content Intelligence Integration")
struct ContentIntelligenceIntegrationTests {
    @Test("full pipeline: text file → enriched context → scoring")
    func endToEndTextFile() async throws {
        let dir = makeTemporaryDirectory(prefix: "integration")
        defer { removeItem(atPath: dir) }

        // Create a text file
        let filePath = dir + "/report.txt"
        createFile(atPath: filePath, contents: "Quarterly financial report Q1 2026".data(using: .utf8)!)

        // Set up KB with a learned pattern
        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            fileExtension: "txt",
            filenameTokens: ["report"],
            sourceApp: nil,
            sizeBucket: "tiny",
            timeBucket: "morning",
            destination: "/Users/test/Documents/Reports",
            signalType: .observation,
            weight: 2.0
        )

        let engine = ScoringEngine(
            patternMatcher: PatternMatcher(knowledgeBase: kb),
            heuristicsEngine: HeuristicsEngine(affinities: [], clusters: []),
            pinnedRulesManager: PinnedRulesManager(),
            knowledgeBase: kb
        )
        let pipeline = ContentIntelligencePipeline()

        // Run pipeline
        let candidate = FileCandidate(path: filePath, fileSize: 35, sourceApp: nil, downloadURL: nil)
        let context = await pipeline.enrich(candidate)

        // Verify enrichment
        #expect(context.extractedText != nil)
        #expect(context.extractedText!.contains("financial report"))

        // Score with enriched context
        let decision = try await engine.route(context)
        #expect(decision != nil)
        #expect(decision!.destination == "/Users/test/Documents/Reports")
    }

    @Test("enrichment adds download context from URL")
    func enrichmentWithDownloadURL() async {
        let candidate = FileCandidate(
            path: "/tmp/test.zip",
            fileSize: 1024,
            sourceApp: "Safari",
            downloadURL: "https://github.com/user/repo/releases/v1.0/test.zip"
        )
        let pipeline = ContentIntelligencePipeline()
        let context = await pipeline.enrich(candidate)

        #expect(context.downloadContext != nil)
        #expect(context.downloadContext!.sourceCategory == .developer)
    }
}
```

- [ ] **Step 2: Run integration tests**

Run: `swift test --filter ContentIntelligenceIntegrationTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 3: Run full test suite**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add Tests/TidyCoreTests/ContentIntelligenceIntegrationTests.swift
git commit -m "test: add end-to-end content intelligence integration tests"
```

---

## Task 14: Build and Verify App

- [ ] **Step 1: Build release**

Run: `swift build -c release`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run app**

Run: `swift run Tidy`
Expected: App launches in menu bar, no crashes

- [ ] **Step 3: Final commit with all remaining changes**

```bash
git status
# Stage any remaining files
git add -A
git commit -m "feat: complete content intelligence pipeline v2

Adds three-stage enrichment pipeline:
- Stage 1: Text extraction (PDF, TXT, MD, CSV, RTF, DOCX, EML)
- Stage 2: Image analysis (Vision: scene classification, OCR, face detection, EXIF)
- Stage 3: Download context (xattr-based provenance, domain categorization)

ScoringLayer protocol updated to accept EnrichedFileContext.
PatternMatcher expanded with scene type and source domain signals.
Database migrated with new pattern record columns."
```
