# Multi-Folder Watching & Bulk Cleanup — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand Tidy from a single-folder watcher into a multi-folder system with folder roles (inbox, archive, watch-only), watch-only move detection via FSEvents rename pairs, and a bulk cleanup engine that scans existing folders and presents batched move suggestions with full batch undo support.

**Architecture:** `FileWatcher` accepts `[URL]` (one FSEvents stream with multiple paths). Events are tagged with their source folder and `FolderRole`. `MoveOrchestrator` respects folder roles: inbox = real-time auto-move/suggest, archive = on-demand only, watch-only = learn from user moves, never auto-move. `BulkCleanupEngine` is a new actor that scans a folder, enriches files through `ContentIntelligencePipeline`, scores them via `ScoringEngine`, groups by confidence tier, and presents results as batched suggestions. `UndoLog` gains `batchId` support for undoing entire cleanup runs. `IgnoreFilter` gains per-folder ignore patterns. Migration converts the v1 `watchPath` UserDefaults key to a `watchedFolders` JSON array.

**Tech Stack:** Swift 6, CoreServices (FSEvents with `kFSEventStreamEventFlagItemRenamed` pairs), GRDB (batch_id column — already added in Plan 1's v2 migration), SwiftUI (folder list editor, bulk cleanup UI)

**Spec:** `docs/superpowers/specs/2026-03-17-tidy-v2-design.md` section 2

**Prerequisites:** Plan 1 (Content Intelligence Pipeline) is fully implemented. `EnrichedFileContext`, `ContentIntelligencePipeline`, and the updated `ScoringLayer` protocol (accepting `EnrichedFileContext`) are available. The v2 database migration (adding `batchId` to `move_records`) is already in place.

---

## IMPORTANT: Corrections to Code Samples

> **Read this section first.** The code samples in this plan contain known patterns from the codebase. Apply these corrections when implementing each task. When a code sample conflicts with these corrections, the corrections take precedence.

### C1: FileCandidate Initializer

The actual signature is:

```swift
FileCandidate(path: String, fileSize: UInt64, metadata: FileMetadata? = nil, date: Date = Date())
```

`sourceApp` and `downloadURL` are derived from `metadata`. Most tests use: `FileCandidate(path: "/tmp/test.pdf", fileSize: 1024)`

### C2: ScoringEngine Initializer

The actual initializers are:

```swift
// 2-layer (no AI):
try ScoringEngine(knowledgeBase: kb, heuristicsEngine: engine, pinnedRules: manager)
// 3-layer (with AI):
try ScoringEngine(knowledgeBase: kb, heuristicsEngine: engine, aiLayer: layer, pinnedRules: manager)
```

`ScoringEngine` creates its own `PatternMatcher` internally.

### C3: KnowledgeBase.recordPattern Signature

The existing method uses label `extension ext:` (not `fileExtension:`), `SizeBucket?` and `TimeBucket?` types (not `String?`), and plain JSON encoding for tokens (not base64). After Plan 1, the method gains optional parameters `documentType`, `sourceDomain`, `sceneType`, `sourceFolder` with `nil` defaults.

### C4: SignalRecorder Methods Throw

The existing `SignalRecorder` methods are `throws`. Keep them throwing. After Plan 1, enriched-context variants also throw.

### C5: MoveOrchestrator is an Actor

`MoveOrchestrator` is declared as `public actor`. All public methods must be called with `await`. The `init` does not need `await`.

### C6: MoveRecord.batchId Column

The `batchId` column was already added to `move_records` in Plan 1's v2 migration. This plan adds the `batchId` property to the Swift `MoveRecord` struct and updates `KnowledgeBase.recordMove` and `UndoLog.recordMove` to accept it. No new database migration is needed.

### C7: WatchedFolder Storage

`WatchedFolder` is stored in UserDefaults as a JSON-encoded array, NOT in the database. This is consistent with how `watchPath` is stored today.

### C8: Post-Plan-1 Interfaces

After Plan 1, `ScoringEngine.route()` accepts `EnrichedFileContext` (not `FileCandidate`). `MoveOrchestrator.processFile()` runs the `ContentIntelligencePipeline` internally before scoring. `OrchestratorEvent.suggested` carries `EnrichedFileContext` context (via the Suggestion wrapper in AppState). The plan's code accounts for this.

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/TidyCore/Models/WatchedFolder.swift` | `FolderRole` enum, `WatchedFolder` struct (Codable) |
| `Sources/TidyCore/Orchestrator/BulkCleanupEngine.swift` | Actor: scan, enrich, score, tier, present, execute |
| `Tests/TidyCoreTests/WatchedFolderTests.swift` | WatchedFolder model tests |
| `Tests/TidyCoreTests/MultiWatcherTests.swift` | FileWatcher multi-path + rename detection tests |
| `Tests/TidyCoreTests/IgnoreFilterTests.swift` | Per-folder ignore pattern tests (extend existing) |
| `Tests/TidyCoreTests/BulkCleanupEngineTests.swift` | Bulk cleanup engine tests |
| `Tests/TidyCoreTests/BatchUndoTests.swift` | Batch undo tests |

### Modified Files
| File | Change |
|------|--------|
| `Sources/TidyCore/Watcher/FileWatcher.swift` | Accept `[URL]`, events tagged with source folder, rename pair tracking |
| `Sources/TidyCore/Watcher/IgnoreFilter.swift` | Per-folder ignore patterns |
| `Sources/TidyCore/Models/MoveRecord.swift` | Add `batchId: String?` property |
| `Sources/TidyCore/Database/KnowledgeBase.swift` | `recordMove` accepts `batchId`, `movesForBatch`, `undoableBatchMoves` queries |
| `Sources/TidyCore/Operations/UndoLog.swift` | `recordMove` accepts `batchId`, `undoBatch(batchId:)` method |
| `Sources/TidyCore/Orchestrator/MoveOrchestrator.swift` | Respect `FolderRole`, per-folder context, bulk cleanup integration |
| `Sources/TidyCore/Orchestrator/OrchestratorEvent.swift` | Add `learnedMove` case for watch-only observation |
| `Sources/Tidy/AppState.swift` | Migration from `watchPath` to `watchedFolders`, multi-folder watcher setup, bulk cleanup state |
| `Sources/Tidy/Views/SettingsView.swift` | Folder list editor with role selector |
| `Sources/Tidy/Views/PanelView.swift` | "Clean Up" button, progress indicator, batch undo |

---

## Task 1: WatchedFolder and FolderRole Model Types

**Files:**
- Create: `Sources/TidyCore/Models/WatchedFolder.swift`
- Create: `Tests/TidyCoreTests/WatchedFolderTests.swift`

- [ ] **Step 1: Write the test for WatchedFolder**

```swift
// Tests/TidyCoreTests/WatchedFolderTests.swift
import Testing
@testable import TidyCore

@Suite("WatchedFolder")
struct WatchedFolderTests {
    @Test("FolderRole raw values are stable strings")
    func folderRoleRawValues() {
        #expect(FolderRole.inbox.rawValue == "inbox")
        #expect(FolderRole.archive.rawValue == "archive")
        #expect(FolderRole.watchOnly.rawValue == "watchOnly")
    }

    @Test("WatchedFolder round-trips through JSON encoding")
    func jsonRoundTrip() throws {
        let folder = WatchedFolder(
            url: URL(fileURLWithPath: "/Users/test/Downloads"),
            role: .inbox,
            isEnabled: true,
            ignorePatterns: ["*.log", "node_modules"]
        )
        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(WatchedFolder.self, from: data)
        #expect(decoded.url.path == "/Users/test/Downloads")
        #expect(decoded.role == .inbox)
        #expect(decoded.isEnabled == true)
        #expect(decoded.ignorePatterns == ["*.log", "node_modules"])
    }

    @Test("WatchedFolder defaults to enabled with no ignore patterns")
    func defaults() {
        let folder = WatchedFolder(
            url: URL(fileURLWithPath: "/Users/test/Desktop"),
            role: .archive
        )
        #expect(folder.isEnabled == true)
        #expect(folder.ignorePatterns.isEmpty)
    }

    @Test("WatchedFolder array round-trips through JSON")
    func arrayRoundTrip() throws {
        let folders = [
            WatchedFolder(url: URL(fileURLWithPath: "/Users/test/Downloads"), role: .inbox),
            WatchedFolder(url: URL(fileURLWithPath: "/Users/test/Documents"), role: .archive),
            WatchedFolder(url: URL(fileURLWithPath: "/Users/test/Dropbox"), role: .watchOnly, isEnabled: false),
        ]
        let data = try JSONEncoder().encode(folders)
        let decoded = try JSONDecoder().decode([WatchedFolder].self, from: data)
        #expect(decoded.count == 3)
        #expect(decoded[0].role == .inbox)
        #expect(decoded[1].role == .archive)
        #expect(decoded[2].isEnabled == false)
    }

    @Test("WatchedFolder tildeCompactedPath returns tilde path for home directory")
    func tildeCompactedPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = WatchedFolder(
            url: home.appendingPathComponent("Downloads"),
            role: .inbox
        )
        #expect(folder.tildeCompactedPath.hasPrefix("~/"))
        #expect(folder.tildeCompactedPath.hasSuffix("Downloads"))
    }

    @Test("FolderRole display names are human-readable")
    func displayNames() {
        #expect(FolderRole.inbox.displayName == "Inbox")
        #expect(FolderRole.archive.displayName == "Archive")
        #expect(FolderRole.watchOnly.displayName == "Watch Only")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WatchedFolderTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL -- types don't exist yet

- [ ] **Step 3: Create WatchedFolder.swift**

```swift
// Sources/TidyCore/Models/WatchedFolder.swift
import Foundation

public enum FolderRole: String, Codable, Sendable, CaseIterable {
    case inbox
    case archive
    case watchOnly

    public var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .archive: "Archive"
        case .watchOnly: "Watch Only"
        }
    }
}

public struct WatchedFolder: Codable, Sendable, Identifiable, Equatable {
    public var id: URL { url }
    public let url: URL
    public var role: FolderRole
    public var isEnabled: Bool
    public var ignorePatterns: [String]

    public init(
        url: URL,
        role: FolderRole,
        isEnabled: Bool = true,
        ignorePatterns: [String] = []
    ) {
        self.url = url
        self.role = role
        self.isEnabled = isEnabled
        self.ignorePatterns = ignorePatterns
    }

    /// Returns the path with ~ for the home directory prefix.
    public var tildeCompactedPath: String {
        let path = url.path
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Returns the expanded absolute path.
    public var expandedPath: String {
        url.path
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WatchedFolderTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Models/WatchedFolder.swift Tests/TidyCoreTests/WatchedFolderTests.swift
git commit -m "feat: add WatchedFolder model with FolderRole enum"
```

---

## Task 2: FileWatcher Multi-Path Support

**Files:**
- Modify: `Sources/TidyCore/Watcher/FileWatcher.swift`
- Create: `Tests/TidyCoreTests/MultiWatcherTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/MultiWatcherTests.swift
import Testing
@testable import TidyCore

@Suite("FileWatcher Multi-Path")
struct MultiWatcherTests {
    @Test("FileEvent.sourceFolder returns tagged folder path")
    func eventSourceFolder() {
        let event = FileEvent.created(path: "/Users/test/Downloads/file.pdf", sourceFolder: "/Users/test/Downloads")
        switch event {
        case .created(let path, let source):
            #expect(path == "/Users/test/Downloads/file.pdf")
            #expect(source == "/Users/test/Downloads")
        default:
            #expect(Bool(false), "Expected .created event")
        }
    }

    @Test("FileEvent.movedIn captures destination path and source folder")
    func movedInEvent() {
        let event = FileEvent.movedIn(path: "/Users/test/Documents/report.pdf", sourceFolder: "/Users/test/Documents")
        switch event {
        case .movedIn(let path, let source):
            #expect(path == "/Users/test/Documents/report.pdf")
            #expect(source == "/Users/test/Documents")
        default:
            #expect(Bool(false), "Expected .movedIn event")
        }
    }

    @Test("FileEvent.renamedPair captures source and destination")
    func renamedPairEvent() {
        let event = FileEvent.renamedPair(
            oldPath: "/Users/test/Downloads/file.pdf",
            newPath: "/Users/test/Documents/file.pdf",
            sourceFolder: "/Users/test/Downloads"
        )
        switch event {
        case .renamedPair(let oldPath, let newPath, let source):
            #expect(oldPath == "/Users/test/Downloads/file.pdf")
            #expect(newPath == "/Users/test/Documents/file.pdf")
            #expect(source == "/Users/test/Downloads")
        default:
            #expect(Bool(false), "Expected .renamedPair event")
        }
    }

    @Test("FileWatcher initializes with multiple paths")
    func multiPathInit() {
        let paths = ["/tmp/test-dir-1", "/tmp/test-dir-2"]
        let watcher = FileWatcher(watchPaths: paths)
        // Should not crash; watcher holds multiple paths
        #expect(watcher.watchedPaths.count == 2)
    }

    @Test("FileWatcher single-path convenience init still works")
    func singlePathInit() {
        let watcher = FileWatcher(watchPath: "/tmp/test-dir")
        #expect(watcher.watchedPaths.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MultiWatcherTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL -- `FileEvent` doesn't have `sourceFolder`, `movedIn`, `renamedPair` cases; `FileWatcher` doesn't accept `[String]`

- [ ] **Step 3: Update FileEvent enum**

Modify `Sources/TidyCore/Watcher/FileWatcher.swift`, replacing the `FileEvent` enum:

```swift
import Foundation
import CoreServices

public enum FileEvent: Sendable {
    case created(path: String, sourceFolder: String)
    case modified(path: String, sourceFolder: String)
    case removed(path: String, sourceFolder: String)
    case movedOut(path: String, sourceFolder: String)
    case movedIn(path: String, sourceFolder: String)
    case renamedPair(oldPath: String, newPath: String, sourceFolder: String)
}
```

- [ ] **Step 4: Update FileWatcher to accept multiple paths and track rename pairs**

Replace the entire `FileWatcher` class in `Sources/TidyCore/Watcher/FileWatcher.swift`:

```swift
public final class FileWatcher: @unchecked Sendable {
    public let watchedPaths: [String]
    private var stream: FSEventStreamRef?
    private let eventContinuation: AsyncStream<FileEvent>.Continuation
    public let events: AsyncStream<FileEvent>

    /// Multi-path initializer. One FSEvents stream watching all paths.
    public init(watchPaths: [String]) {
        self.watchedPaths = watchPaths
        var continuation: AsyncStream<FileEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    /// Single-path convenience initializer (backward compatible).
    public convenience init(watchPath: String) {
        self.init(watchPaths: [watchPath])
    }

    /// Determine which watched folder a file path belongs to.
    private func sourceFolder(for path: String) -> String {
        // Find the longest matching watched path prefix
        var best = watchedPaths.first ?? ""
        for wp in watchedPaths {
            let normalized = wp.hasSuffix("/") ? wp : wp + "/"
            if path.hasPrefix(normalized) && wp.count > best.count {
                best = wp
            }
        }
        return best
    }

    public func start() {
        let pathsToWatch = watchedPaths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, eventFlags, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

                // Collect rename events for pair detection
                var pendingRenames: [(path: String, sourceFolder: String)] = []

                for i in 0..<numEvents {
                    let path = paths[i]
                    let flag = flags[i]
                    if flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 { continue }

                    let source = watcher.sourceFolder(for: path)

                    if flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                        // Renamed events come in pairs: old path (gone) + new path (exists)
                        if FileManager.default.fileExists(atPath: path) {
                            // This is the destination of a rename
                            if let pending = pendingRenames.popLast() {
                                // Paired: old path disappeared, new path appeared
                                watcher.eventContinuation.yield(.renamedPair(
                                    oldPath: pending.path,
                                    newPath: path,
                                    sourceFolder: pending.sourceFolder
                                ))
                            } else {
                                // No pending rename -- file appeared via rename from outside
                                watcher.eventContinuation.yield(.movedIn(path: path, sourceFolder: source))
                            }
                        } else {
                            // File no longer exists -- it was renamed away
                            pendingRenames.append((path: path, sourceFolder: source))
                        }
                    } else if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                        watcher.eventContinuation.yield(.created(path: path, sourceFolder: source))
                    } else if flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                        watcher.eventContinuation.yield(.modified(path: path, sourceFolder: source))
                    } else if flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                        watcher.eventContinuation.yield(.removed(path: path, sourceFolder: source))
                    }
                }

                // Any unmatched renames are movedOut events
                for pending in pendingRenames {
                    watcher.eventContinuation.yield(.movedOut(path: pending.path, sourceFolder: pending.sourceFolder))
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        eventContinuation.finish()
    }

    deinit { stop() }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter MultiWatcherTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TidyCore/Watcher/FileWatcher.swift Tests/TidyCoreTests/MultiWatcherTests.swift
git commit -m "feat: FileWatcher accepts multiple paths with source folder tagging and rename pair detection"
```

---

## Task 3: IgnoreFilter Per-Folder Patterns

**Files:**
- Modify: `Sources/TidyCore/Watcher/IgnoreFilter.swift`
- Create: `Tests/TidyCoreTests/IgnoreFilterPerFolderTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/IgnoreFilterPerFolderTests.swift
import Testing
@testable import TidyCore

@Suite("IgnoreFilter Per-Folder")
struct IgnoreFilterPerFolderTests {
    @Test("global ignore still works without per-folder patterns")
    func globalIgnore() {
        let filter = IgnoreFilter()
        #expect(filter.shouldIgnore(filename: ".hidden") == true)
        #expect(filter.shouldIgnore(filename: "file.part") == true)
        #expect(filter.shouldIgnore(filename: "report.pdf") == false)
    }

    @Test("per-folder extension pattern ignores matching files")
    func perFolderExtensionPattern() {
        let filter = IgnoreFilter()
        // Pattern "*.log" should ignore .log files in that folder
        #expect(filter.shouldIgnore(filename: "debug.log", folderPatterns: ["*.log"]) == true)
        #expect(filter.shouldIgnore(filename: "report.pdf", folderPatterns: ["*.log"]) == false)
    }

    @Test("per-folder exact name pattern ignores matching files")
    func perFolderExactPattern() {
        let filter = IgnoreFilter()
        #expect(filter.shouldIgnore(filename: "node_modules", folderPatterns: ["node_modules"]) == true)
        #expect(filter.shouldIgnore(filename: "package.json", folderPatterns: ["node_modules"]) == false)
    }

    @Test("per-folder prefix pattern with wildcard")
    func perFolderPrefixPattern() {
        let filter = IgnoreFilter()
        #expect(filter.shouldIgnore(filename: "temp_build_123.zip", folderPatterns: ["temp_*"]) == true)
        #expect(filter.shouldIgnore(filename: "report_final.zip", folderPatterns: ["temp_*"]) == false)
    }

    @Test("empty per-folder patterns array falls through to global only")
    func emptyPerFolderPatterns() {
        let filter = IgnoreFilter()
        #expect(filter.shouldIgnore(filename: "report.pdf", folderPatterns: []) == false)
        #expect(filter.shouldIgnore(filename: ".hidden", folderPatterns: []) == true)
    }

    @Test("multiple per-folder patterns checked in order")
    func multiplePatterns() {
        let filter = IgnoreFilter()
        let patterns = ["*.log", "*.tmp", "backup_*"]
        #expect(filter.shouldIgnore(filename: "app.log", folderPatterns: patterns) == true)
        #expect(filter.shouldIgnore(filename: "cache.tmp", folderPatterns: patterns) == true)
        #expect(filter.shouldIgnore(filename: "backup_2026.zip", folderPatterns: patterns) == true)
        #expect(filter.shouldIgnore(filename: "report.pdf", folderPatterns: patterns) == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IgnoreFilterPerFolderTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL -- `shouldIgnore` doesn't accept `folderPatterns`

- [ ] **Step 3: Update IgnoreFilter with per-folder patterns**

Modify `Sources/TidyCore/Watcher/IgnoreFilter.swift`:

```swift
// Sources/TidyCore/Watcher/IgnoreFilter.swift
import Foundation

public struct IgnoreFilter: Sendable {
    private static let ignoredExtensions: Set<String> = ["part", "crdownload", "download"]
    private static let tempTokens: Set<String> = ["tmp", "temp"]

    public init() {}

    /// Check if a filename should be ignored using global rules only.
    public func shouldIgnore(filename: String) -> Bool {
        shouldIgnoreGlobal(filename: filename)
    }

    /// Check if a filename should be ignored using global rules plus per-folder patterns.
    public func shouldIgnore(filename: String, folderPatterns: [String]) -> Bool {
        if shouldIgnoreGlobal(filename: filename) { return true }
        return matchesFolderPatterns(filename: filename, patterns: folderPatterns)
    }

    private func shouldIgnoreGlobal(filename: String) -> Bool {
        if filename.hasPrefix(".") { return true }
        let lower = filename.lowercased()
        let ext = (lower as NSString).pathExtension
        if Self.ignoredExtensions.contains(ext) { return true }
        let stem = ext.isEmpty ? lower : (lower as NSString).deletingPathExtension
        let tokens = stem.components(separatedBy: CharacterSet(charactersIn: "-_. "))
        for token in tokens {
            if Self.tempTokens.contains(token) { return true }
            for t in Self.tempTokens { if token.hasPrefix(t) { return true } }
        }
        if Self.tempTokens.contains(ext) { return true }
        return false
    }

    /// Match filename against per-folder glob-style patterns.
    /// Supports: "*.ext" (extension match), "prefix*" (prefix match), "exact" (exact match).
    private func matchesFolderPatterns(filename: String, patterns: [String]) -> Bool {
        let lower = filename.lowercased()
        for pattern in patterns {
            let p = pattern.lowercased()
            if p.hasPrefix("*.") {
                // Extension match: "*.log" matches "debug.log"
                let ext = String(p.dropFirst(2))
                if (lower as NSString).pathExtension == ext {
                    return true
                }
            } else if p.hasSuffix("*") {
                // Prefix match: "temp_*" matches "temp_build.zip"
                let prefix = String(p.dropLast(1))
                if lower.hasPrefix(prefix) {
                    return true
                }
            } else {
                // Exact match
                if lower == p {
                    return true
                }
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IgnoreFilterPerFolderTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Run existing IgnoreFilter tests to verify no regression**

Run: `swift test --filter IgnoreFilterTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TidyCore/Watcher/IgnoreFilter.swift Tests/TidyCoreTests/IgnoreFilterPerFolderTests.swift
git commit -m "feat: add per-folder ignore patterns to IgnoreFilter"
```

---

## Task 4: MoveRecord.batchId Property

**Files:**
- Modify: `Sources/TidyCore/Models/MoveRecord.swift`
- Modify: `Sources/TidyCore/Database/KnowledgeBase.swift`
- Modify: `Sources/TidyCore/Operations/UndoLog.swift`
- Create: `Tests/TidyCoreTests/BatchUndoTests.swift`

Note: The `batchId` column already exists in the database from Plan 1's v2 migration. This task adds the Swift property and query methods.

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/BatchUndoTests.swift
import Testing
@testable import TidyCore

@Suite("Batch Undo")
struct BatchUndoTests {
    @Test("MoveRecord stores batchId")
    func moveRecordBatchId() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(
            filename: "file1.pdf",
            sourcePath: "/tmp/Downloads/file1.pdf",
            destinationPath: "/tmp/Documents/file1.pdf",
            confidence: 85,
            wasAuto: true,
            batchId: "batch-123"
        )
        let last = try kb.lastMove()
        #expect(last != nil)
        #expect(last?.batchId == "batch-123")
    }

    @Test("recordMove without batchId defaults to nil")
    func moveRecordNoBatchId() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(
            filename: "file2.pdf",
            sourcePath: "/tmp/Downloads/file2.pdf",
            destinationPath: "/tmp/Documents/file2.pdf",
            confidence: 70,
            wasAuto: false
        )
        let last = try kb.lastMove()
        #expect(last?.batchId == nil)
    }

    @Test("movesForBatch returns only moves with matching batchId")
    func movesForBatch() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(
            filename: "a.pdf", sourcePath: "/src/a.pdf", destinationPath: "/dst/a.pdf",
            confidence: 90, wasAuto: true, batchId: "batch-abc"
        )
        try kb.recordMove(
            filename: "b.pdf", sourcePath: "/src/b.pdf", destinationPath: "/dst/b.pdf",
            confidence: 85, wasAuto: true, batchId: "batch-abc"
        )
        try kb.recordMove(
            filename: "c.pdf", sourcePath: "/src/c.pdf", destinationPath: "/dst/c.pdf",
            confidence: 60, wasAuto: false, batchId: "batch-other"
        )
        let batchMoves = try kb.movesForBatch(batchId: "batch-abc")
        #expect(batchMoves.count == 2)
        #expect(batchMoves.allSatisfy { $0.batchId == "batch-abc" })
    }

    @Test("undoableBatchMoves excludes already-undone moves")
    func undoableBatchMoves() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordMove(
            filename: "a.pdf", sourcePath: "/src/a.pdf", destinationPath: "/dst/a.pdf",
            confidence: 90, wasAuto: true, batchId: "batch-undo"
        )
        try kb.recordMove(
            filename: "b.pdf", sourcePath: "/src/b.pdf", destinationPath: "/dst/b.pdf",
            confidence: 85, wasAuto: true, batchId: "batch-undo"
        )
        // Mark first as undone
        let moves = try kb.movesForBatch(batchId: "batch-undo")
        try kb.markMoveUndone(id: moves[0].id!)

        let undoable = try kb.undoableBatchMoves(batchId: "batch-undo")
        #expect(undoable.count == 1)
        #expect(undoable[0].filename == "b.pdf")
    }

    @Test("UndoLog recordMove with batchId")
    func undoLogBatchId() throws {
        let kb = try KnowledgeBase.inMemory()
        let log = UndoLog(knowledgeBase: kb)
        try log.recordMove(
            filename: "test.pdf",
            sourcePath: "/src/test.pdf",
            destinationPath: "/dst/test.pdf",
            confidence: 90,
            wasAuto: true,
            batchId: "batch-log"
        )
        let last = try log.lastMove()
        #expect(last?.batchId == "batch-log")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BatchUndoTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL -- `MoveRecord` doesn't have `batchId`, `KnowledgeBase` methods don't exist

- [ ] **Step 3: Add batchId to MoveRecord**

Modify `Sources/TidyCore/Models/MoveRecord.swift`:

```swift
// Sources/TidyCore/Models/MoveRecord.swift
import Foundation
import GRDB

public struct MoveRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var filename: String
    public var sourcePath: String
    public var destinationPath: String
    public var confidence: Int?
    public var wasAuto: Bool
    public var wasUndone: Bool
    public var createdAt: Date
    public var batchId: String?

    public static let databaseTableName = "move_records"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 4: Update KnowledgeBase.recordMove and add batch query methods**

Add `batchId` parameter to `recordMove` and add new query methods in `Sources/TidyCore/Database/KnowledgeBase.swift`:

In the `recordMove` method, add `batchId: String? = nil` parameter:

```swift
public func recordMove(
    filename: String,
    sourcePath: String,
    destinationPath: String,
    confidence: Int?,
    wasAuto: Bool,
    batchId: String? = nil
) throws {
    var record = MoveRecord(
        filename: filename,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        confidence: confidence,
        wasAuto: wasAuto,
        wasUndone: false,
        createdAt: Date(),
        batchId: batchId
    )
    try dbQueue.write { db in
        try record.insert(db)
    }
}
```

Add the following new methods after the existing move methods:

```swift
public func movesForBatch(batchId: String) throws -> [MoveRecord] {
    try dbQueue.read { db in
        try MoveRecord
            .filter(Column("batchId") == batchId)
            .order(Column("createdAt").asc, Column("id").asc)
            .fetchAll(db)
    }
}

public func undoableBatchMoves(batchId: String) throws -> [MoveRecord] {
    try dbQueue.read { db in
        try MoveRecord
            .filter(Column("batchId") == batchId)
            .filter(Column("wasUndone") == false)
            .order(Column("createdAt").desc, Column("id").desc)
            .fetchAll(db)
    }
}
```

- [ ] **Step 5: Update UndoLog.recordMove to accept batchId**

Modify the `recordMove` method in `Sources/TidyCore/Operations/UndoLog.swift`:

```swift
public func recordMove(
    filename: String, sourcePath: String, destinationPath: String,
    confidence: Int?, wasAuto: Bool, batchId: String? = nil
) throws {
    try knowledgeBase.recordMove(
        filename: filename, sourcePath: sourcePath, destinationPath: destinationPath,
        confidence: confidence, wasAuto: wasAuto, batchId: batchId
    )
    try knowledgeBase.pruneOldMoves(keepLast: Self.maxEntries)
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter BatchUndoTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 7: Run existing UndoLog and KnowledgeBase tests to verify no regression**

Run: `swift test --filter "UndoLogTests|KnowledgeBaseTests" -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/TidyCore/Models/MoveRecord.swift Sources/TidyCore/Database/KnowledgeBase.swift Sources/TidyCore/Operations/UndoLog.swift Tests/TidyCoreTests/BatchUndoTests.swift
git commit -m "feat: add batchId to MoveRecord with batch query and undo support"
```

---

## Task 5: OrchestratorEvent Update for Watch-Only Learning

**Files:**
- Modify: `Sources/TidyCore/Orchestrator/OrchestratorEvent.swift`

- [ ] **Step 1: Add learnedMove event case**

Modify `Sources/TidyCore/Orchestrator/OrchestratorEvent.swift`:

```swift
// Sources/TidyCore/Orchestrator/OrchestratorEvent.swift
import Foundation

public enum OrchestratorEvent: Sendable {
    case autoMoved(move: MoveRecord, decision: RoutingDecision)
    case suggested(candidate: FileCandidate, decision: RoutingDecision)
    case newFile(candidate: FileCandidate)
    case undone(originalMove: MoveRecord)
    case observed(filename: String, destination: String)
    case learnedMove(filename: String, source: String, destination: String)
}
```

- [ ] **Step 2: Verify compilation**

Run: `swift build`
Expected: Build succeeds (no tests reference the new case yet, existing matches are non-exhaustive only if warnings are errors)

- [ ] **Step 3: Commit**

```bash
git add Sources/TidyCore/Orchestrator/OrchestratorEvent.swift
git commit -m "feat: add learnedMove case to OrchestratorEvent for watch-only folder learning"
```

---

## Task 6: MoveOrchestrator Multi-Folder Role Support

**Files:**
- Modify: `Sources/TidyCore/Orchestrator/MoveOrchestrator.swift`
- Modify existing tests in `Tests/TidyCoreTests/MoveOrchestratorTests.swift`

- [ ] **Step 1: Write the test**

Add to `Tests/TidyCoreTests/MoveOrchestratorTests.swift`:

```swift
@Test("processFile skips archive-role folders")
func archiveFolderSkipped() async throws {
    let kb = try KnowledgeBase.inMemory()
    let heuristics = HeuristicsEngine(affinities: [], clusters: [])
    let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
    let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb)

    let candidate = FileCandidate(path: "/tmp/test.pdf", fileSize: 1024)
    let event = try await orchestrator.processFile(
        candidate,
        folderRole: .archive
    )
    // Archive folders should not auto-process in real-time
    #expect(event == nil)
}

@Test("processFile processes inbox-role folders normally")
func inboxFolderProcessed() async throws {
    let kb = try KnowledgeBase.inMemory()
    let heuristics = HeuristicsEngine(affinities: [], clusters: [])
    let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
    let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb)

    let candidate = FileCandidate(path: "/tmp/test.pdf", fileSize: 1024)
    let event = try await orchestrator.processFile(
        candidate,
        folderRole: .inbox
    )
    // Inbox folders should process (returns newFile since no patterns exist)
    #expect(event != nil)
}

@Test("processFile with watchOnly role returns nil")
func watchOnlyFolderSkipped() async throws {
    let kb = try KnowledgeBase.inMemory()
    let heuristics = HeuristicsEngine(affinities: [], clusters: [])
    let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
    let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb)

    let candidate = FileCandidate(path: "/tmp/test.pdf", fileSize: 1024)
    let event = try await orchestrator.processFile(
        candidate,
        folderRole: .watchOnly
    )
    // Watch-only folders never auto-process
    #expect(event == nil)
}

@Test("recordWatchOnlyMove records learning signal")
func watchOnlyLearning() async throws {
    let kb = try KnowledgeBase.inMemory()
    let heuristics = HeuristicsEngine(affinities: [], clusters: [])
    let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
    let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb)

    let event = try await orchestrator.recordWatchOnlyMove(
        filename: "invoice.pdf",
        fileSize: 2048,
        sourcePath: "/Users/test/Desktop/invoice.pdf",
        destinationPath: "/Users/test/Documents/Invoices/invoice.pdf"
    )
    #expect(event != nil)
    if case .learnedMove(let filename, _, let dest) = event {
        #expect(filename == "invoice.pdf")
        #expect(dest == "/Users/test/Documents/Invoices/invoice.pdf")
    } else {
        #expect(Bool(false), "Expected learnedMove event")
    }

    // Verify the pattern was recorded
    let patterns = try kb.allPatterns()
    #expect(patterns.count == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MoveOrchestratorTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL -- `processFile` doesn't accept `folderRole`, `recordWatchOnlyMove` doesn't exist

- [ ] **Step 3: Update MoveOrchestrator**

Modify `Sources/TidyCore/Orchestrator/MoveOrchestrator.swift`. Add the `folderRole` parameter to `processFile` and add `recordWatchOnlyMove`:

```swift
public actor MoveOrchestrator {
    private let scoringEngine: ScoringEngine
    private let knowledgeBase: KnowledgeBase
    private let ignoreFilter: IgnoreFilter
    private let fileMover: FileMover
    private let undoLog: UndoLog
    private let signalRecorder: SignalRecorder
    private let settleTimer: SettleTimer
    private var autoMoveThreshold: Int = 80
    private var suggestThreshold: Int = 50
    private var isPaused: Bool = false

    public init(
        scoringEngine: ScoringEngine,
        knowledgeBase: KnowledgeBase,
        settleSeconds: TimeInterval = 5.0
    ) {
        self.scoringEngine = scoringEngine
        self.knowledgeBase = knowledgeBase
        self.ignoreFilter = IgnoreFilter()
        self.fileMover = FileMover()
        self.undoLog = UndoLog(knowledgeBase: knowledgeBase)
        self.signalRecorder = SignalRecorder(knowledgeBase: knowledgeBase)
        self.settleTimer = SettleTimer(settleSeconds: settleSeconds)
    }

    public func setPaused(_ paused: Bool) { isPaused = paused }
    public func setAutoMoveThreshold(_ threshold: Int) { autoMoveThreshold = threshold }
    public func setSuggestThreshold(_ threshold: Int) { suggestThreshold = threshold }

    /// Process a file event. The `folderRole` determines behavior:
    /// - `.inbox`: full auto-move/suggest pipeline
    /// - `.archive`: skip (archive folders are on-demand only via BulkCleanupEngine)
    /// - `.watchOnly`: skip (watch-only folders learn from rename pairs, not from new files)
    public func processFile(
        _ candidate: FileCandidate,
        folderRole: FolderRole = .inbox,
        folderIgnorePatterns: [String] = []
    ) async throws -> OrchestratorEvent? {
        // Only inbox folders get real-time processing
        guard folderRole == .inbox else { return nil }

        if folderIgnorePatterns.isEmpty {
            if ignoreFilter.shouldIgnore(filename: candidate.filename) { return nil }
        } else {
            if ignoreFilter.shouldIgnore(filename: candidate.filename, folderPatterns: folderIgnorePatterns) { return nil }
        }
        if isPaused { return nil }

        guard let decision = try await scoringEngine.route(candidate) else {
            return .newFile(candidate: candidate)
        }

        switch decision.tier {
        case .autoMove:
            let moveResult = try fileMover.move(from: candidate.path, toDirectory: decision.destination)
            try undoLog.recordMove(
                filename: candidate.filename, sourcePath: candidate.path,
                destinationPath: moveResult.destinationPath,
                confidence: decision.confidence, wasAuto: true
            )
            let moveRecord = try undoLog.lastMove()!
            return .autoMoved(move: moveRecord, decision: decision)
        case .suggest:
            return .suggested(candidate: candidate, decision: decision)
        case .ask:
            return .newFile(candidate: candidate)
        }
    }

    /// Record a move observed in a watch-only folder.
    /// Used when FSEvents detects a rename pair (file moved from watched folder to destination).
    public func recordWatchOnlyMove(
        filename: String,
        fileSize: UInt64,
        sourcePath: String,
        destinationPath: String
    ) throws -> OrchestratorEvent? {
        if ignoreFilter.shouldIgnore(filename: filename) { return nil }
        let candidate = FileCandidate(path: sourcePath, fileSize: fileSize)
        let destination = (destinationPath as NSString).deletingLastPathComponent
        try signalRecorder.recordObservation(candidate: candidate, destination: destination)
        return .learnedMove(filename: filename, source: sourcePath, destination: destinationPath)
    }

    public func recordUserMove(
        filename: String, fileSize: UInt64, destination: String
    ) throws -> OrchestratorEvent? {
        if ignoreFilter.shouldIgnore(filename: filename) { return nil }
        let candidate = FileCandidate(path: "/\(filename)", fileSize: fileSize)
        try signalRecorder.recordObservation(candidate: candidate, destination: destination)
        return .observed(filename: filename, destination: destination)
    }

    public func confirmAutoMove(candidate: FileCandidate, destination: String) throws {
        try signalRecorder.recordConfirmation(candidate: candidate, destination: destination)
    }

    public func approveSuggestion(candidate: FileCandidate, destination: String) throws -> MoveRecord {
        let moveResult = try fileMover.move(from: candidate.path, toDirectory: destination)
        try undoLog.recordMove(
            filename: candidate.filename, sourcePath: candidate.path,
            destinationPath: moveResult.destinationPath, confidence: nil, wasAuto: false
        )
        try signalRecorder.recordConfirmation(candidate: candidate, destination: destination)
        return try undoLog.lastMove()!
    }

    public func redirect(
        candidate: FileCandidate, suggestedDestination: String?, chosenDestination: String
    ) throws -> MoveRecord {
        let moveResult = try fileMover.move(from: candidate.path, toDirectory: chosenDestination)
        try undoLog.recordMove(
            filename: candidate.filename, sourcePath: candidate.path,
            destinationPath: moveResult.destinationPath, confidence: nil, wasAuto: false
        )
        if let suggested = suggestedDestination, suggested != chosenDestination {
            try signalRecorder.recordCorrection(
                candidate: candidate, wrongDestination: suggested, correctDestination: chosenDestination
            )
        } else {
            try signalRecorder.recordObservation(candidate: candidate, destination: chosenDestination)
        }
        return try undoLog.lastMove()!
    }

    public func undoLastMove() throws -> MoveRecord? {
        guard let lastMove = try undoLog.lastUndoableMove() else { return nil }
        _ = try fileMover.undoMove(from: lastMove.destinationPath, to: lastMove.sourcePath)
        try undoLog.markUndone(moveId: lastMove.id!)
        return lastMove
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MoveOrchestratorTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Orchestrator/MoveOrchestrator.swift Tests/TidyCoreTests/MoveOrchestratorTests.swift
git commit -m "feat: MoveOrchestrator respects FolderRole with watch-only move learning"
```

---

## Task 7: BulkCleanupEngine

**Files:**
- Create: `Sources/TidyCore/Orchestrator/BulkCleanupEngine.swift`
- Create: `Tests/TidyCoreTests/BulkCleanupEngineTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/BulkCleanupEngineTests.swift
import Testing
@testable import TidyCore

@Suite("BulkCleanupEngine")
struct BulkCleanupEngineTests {
    @Test("scan finds all non-hidden files in directory")
    func scanFindsFiles() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-scan")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        createFile(atPath: dir + "/report.pdf")
        createFile(atPath: dir + "/photo.jpg")
        createFile(atPath: dir + "/.hidden")
        createFile(atPath: dir + "/notes.txt")

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let scoringEngine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let engine = BulkCleanupEngine(
            scoringEngine: scoringEngine,
            knowledgeBase: kb
        )

        let candidates = await engine.scan(directory: URL(fileURLWithPath: dir))
        // Should find 3 visible files, skip .hidden
        #expect(candidates.count == 3)
    }

    @Test("scan with recursive flag includes subdirectory files")
    func scanRecursive() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-recursive")
        try createDirectory(atPath: dir)
        try createDirectory(atPath: dir + "/subdir")
        defer { removeItem(atPath: dir) }

        createFile(atPath: dir + "/root.pdf")
        createFile(atPath: dir + "/subdir/nested.pdf")

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let scoringEngine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let engine = BulkCleanupEngine(
            scoringEngine: scoringEngine,
            knowledgeBase: kb
        )

        let nonRecursive = await engine.scan(directory: URL(fileURLWithPath: dir), recursive: false)
        #expect(nonRecursive.count == 1)

        let recursive = await engine.scan(directory: URL(fileURLWithPath: dir), recursive: true)
        #expect(recursive.count == 2)
    }

    @Test("batchId is a UUID string")
    func batchIdFormat() async throws {
        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let scoringEngine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let engine = BulkCleanupEngine(
            scoringEngine: scoringEngine,
            knowledgeBase: kb
        )

        let batchId = await engine.generateBatchId()
        // Should be a valid UUID
        #expect(UUID(uuidString: batchId) != nil)
    }

    @Test("CleanupResult groups by confidence tier")
    func resultTiers() {
        let high = CleanupItem(
            candidate: FileCandidate(path: "/tmp/a.pdf", fileSize: 100),
            decision: RoutingDecision(
                destination: "/dst", confidence: 90,
                layerBreakdown: [:], reason: "test"
            )
        )
        let medium = CleanupItem(
            candidate: FileCandidate(path: "/tmp/b.pdf", fileSize: 100),
            decision: RoutingDecision(
                destination: "/dst", confidence: 65,
                layerBreakdown: [:], reason: "test"
            )
        )
        let low = CleanupItem(
            candidate: FileCandidate(path: "/tmp/c.pdf", fileSize: 100),
            decision: nil
        )

        let result = CleanupResult(
            items: [high, medium, low],
            batchId: "test-batch"
        )

        #expect(result.highConfidence.count == 1)
        #expect(result.suggestions.count == 1)
        #expect(result.needsReview.count == 1)
        #expect(result.totalCount == 3)
    }

    @Test("CleanupProgress tracks scanning state")
    func progressTracking() {
        var progress = CleanupProgress(total: 100)
        #expect(progress.scanned == 0)
        #expect(progress.fraction == 0.0)

        progress.scanned = 50
        #expect(progress.fraction == 0.5)

        progress.scanned = 100
        #expect(progress.fraction == 1.0)
        #expect(progress.isComplete)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BulkCleanupEngineTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL -- types don't exist

- [ ] **Step 3: Create BulkCleanupEngine.swift**

```swift
// Sources/TidyCore/Orchestrator/BulkCleanupEngine.swift
import Foundation

// MARK: - Supporting Types

public struct CleanupItem: Sendable {
    public let candidate: FileCandidate
    public let decision: RoutingDecision?

    public init(candidate: FileCandidate, decision: RoutingDecision?) {
        self.candidate = candidate
        self.decision = decision
    }

    public var tier: ConfidenceTier {
        guard let decision else { return .ask }
        return decision.tier
    }
}

public struct CleanupResult: Sendable {
    public let items: [CleanupItem]
    public let batchId: String

    public init(items: [CleanupItem], batchId: String) {
        self.items = items
        self.batchId = batchId
    }

    /// Items with confidence 80-100 (recommended moves).
    public var highConfidence: [CleanupItem] {
        items.filter { $0.tier == .autoMove }
    }

    /// Items with confidence 50-79 (suggestions).
    public var suggestions: [CleanupItem] {
        items.filter { $0.tier == .suggest }
    }

    /// Items with confidence 0-49 (needs manual review).
    public var needsReview: [CleanupItem] {
        items.filter { $0.tier == .ask }
    }

    public var totalCount: Int { items.count }
}

public struct CleanupProgress: Sendable {
    public let total: Int
    public var scanned: Int

    public init(total: Int, scanned: Int = 0) {
        self.total = total
        self.scanned = scanned
    }

    public var fraction: Double {
        guard total > 0 else { return 0.0 }
        return Double(scanned) / Double(total)
    }

    public var isComplete: Bool {
        scanned >= total
    }
}

// MARK: - BulkCleanupEngine

public actor BulkCleanupEngine {
    private let scoringEngine: ScoringEngine
    private let knowledgeBase: KnowledgeBase
    private let fileMover: FileMover
    private let undoLog: UndoLog
    private let ignoreFilter: IgnoreFilter
    private var isCancelled: Bool = false

    /// Batch size for processing large folders.
    public static let batchSize = 50

    public init(
        scoringEngine: ScoringEngine,
        knowledgeBase: KnowledgeBase
    ) {
        self.scoringEngine = scoringEngine
        self.knowledgeBase = knowledgeBase
        self.fileMover = FileMover()
        self.undoLog = UndoLog(knowledgeBase: knowledgeBase)
        self.ignoreFilter = IgnoreFilter()
    }

    /// Generate a unique batch ID for a cleanup run.
    public func generateBatchId() -> String {
        UUID().uuidString
    }

    /// Cancel an in-progress cleanup scan.
    public func cancel() {
        isCancelled = true
    }

    /// Reset cancellation state for a new scan.
    public func resetCancellation() {
        isCancelled = false
    }

    /// Scan a directory and return all eligible file candidates.
    /// - Parameters:
    ///   - directory: The folder to scan.
    ///   - recursive: Whether to include files in subdirectories.
    ///   - folderIgnorePatterns: Per-folder ignore patterns to apply.
    /// - Returns: Array of `FileCandidate` for eligible files.
    public func scan(
        directory: URL,
        recursive: Bool = false,
        folderIgnorePatterns: [String] = []
    ) -> [FileCandidate] {
        let fm = FileManager.default
        let path = directory.path

        var candidates: [FileCandidate] = []

        if recursive {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true else { continue }
                let filename = fileURL.lastPathComponent
                if folderIgnorePatterns.isEmpty {
                    if ignoreFilter.shouldIgnore(filename: filename) { continue }
                } else {
                    if ignoreFilter.shouldIgnore(filename: filename, folderPatterns: folderIgnorePatterns) { continue }
                }
                let fileSize = UInt64(values.fileSize ?? 0)
                candidates.append(FileCandidate(path: fileURL.path, fileSize: fileSize))
            }
        } else {
            guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }
            for filename in contents {
                let fullPath = (path as NSString).appendingPathComponent(filename)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }
                if folderIgnorePatterns.isEmpty {
                    if ignoreFilter.shouldIgnore(filename: filename) { continue }
                } else {
                    if ignoreFilter.shouldIgnore(filename: filename, folderPatterns: folderIgnorePatterns) { continue }
                }
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let fileSize = attrs?[.size] as? UInt64 ?? 0
                candidates.append(FileCandidate(path: fullPath, fileSize: fileSize))
            }
        }

        return candidates
    }

    /// Run a full cleanup: scan, score, and tier results.
    /// Calls the `onProgress` closure after each batch completes.
    /// - Parameters:
    ///   - directory: The folder to clean up.
    ///   - recursive: Whether to include subdirectories.
    ///   - folderIgnorePatterns: Per-folder ignore patterns.
    ///   - onProgress: Called with updated progress after each batch.
    /// - Returns: The `CleanupResult` with all items grouped by tier, or nil if cancelled.
    public func cleanup(
        directory: URL,
        recursive: Bool = false,
        folderIgnorePatterns: [String] = [],
        onProgress: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async throws -> CleanupResult? {
        resetCancellation()

        let candidates = scan(
            directory: directory,
            recursive: recursive,
            folderIgnorePatterns: folderIgnorePatterns
        )

        let batchId = generateBatchId()
        var items: [CleanupItem] = []
        var progress = CleanupProgress(total: candidates.count)
        onProgress?(progress)

        // Process in batches
        let batches = stride(from: 0, to: candidates.count, by: Self.batchSize).map {
            Array(candidates[$0..<min($0 + Self.batchSize, candidates.count)])
        }

        for batch in batches {
            if isCancelled { return nil }

            for candidate in batch {
                if isCancelled { return nil }

                let decision = try await scoringEngine.route(candidate)
                items.append(CleanupItem(candidate: candidate, decision: decision))

                progress.scanned += 1
            }
            onProgress?(progress)
        }

        return CleanupResult(items: items, batchId: batchId)
    }

    /// Execute a set of approved moves from a cleanup result.
    /// - Parameters:
    ///   - items: The cleanup items to move.
    ///   - batchId: The batch ID to tag all moves with.
    /// - Returns: Array of `MoveRecord` for successfully moved files.
    public func executeApproved(items: [CleanupItem], batchId: String) throws -> [MoveRecord] {
        var records: [MoveRecord] = []
        for item in items {
            guard let decision = item.decision else { continue }
            do {
                let moveResult = try fileMover.move(
                    from: item.candidate.path,
                    toDirectory: decision.destination
                )
                try undoLog.recordMove(
                    filename: item.candidate.filename,
                    sourcePath: item.candidate.path,
                    destinationPath: moveResult.destinationPath,
                    confidence: decision.confidence,
                    wasAuto: false,
                    batchId: batchId
                )
                if let last = try undoLog.lastMove() {
                    records.append(last)
                }
            } catch {
                // Skip files that fail to move (e.g., source already gone)
                continue
            }
        }
        return records
    }

    /// Undo all moves from a batch.
    /// Checks that each file still exists at the moved-to location before reverting.
    /// - Parameter batchId: The batch ID to undo.
    /// - Returns: Number of successfully undone moves.
    public func undoBatch(batchId: String) throws -> Int {
        let moves = try knowledgeBase.undoableBatchMoves(batchId: batchId)
        var undoneCount = 0
        let fm = FileManager.default

        for move in moves {
            // Only undo if file still exists at the destination
            guard fm.fileExists(atPath: move.destinationPath) else { continue }
            do {
                _ = try fileMover.undoMove(from: move.destinationPath, to: move.sourcePath)
                try knowledgeBase.markMoveUndone(id: move.id!)
                undoneCount += 1
            } catch {
                continue
            }
        }
        return undoneCount
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BulkCleanupEngineTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Orchestrator/BulkCleanupEngine.swift Tests/TidyCoreTests/BulkCleanupEngineTests.swift
git commit -m "feat: add BulkCleanupEngine actor with scan, score, tier, execute, and batch undo"
```

---

## Task 8: AppState Migration from watchPath to watchedFolders

**Files:**
- Modify: `Sources/Tidy/AppState.swift`

- [ ] **Step 1: Add WatchedFolders property and migration logic**

In `Sources/Tidy/AppState.swift`, add the `watchedFolders` property and migration:

Replace the `watchPath` property with:

```swift
var watchedFolders: [WatchedFolder] = [] {
    didSet { saveWatchedFolders() }
}
```

Add migration method and persistence:

```swift
private func saveWatchedFolders() {
    if let data = try? JSONEncoder().encode(watchedFolders) {
        UserDefaults.standard.set(data, forKey: "watchedFolders")
    }
}

private func loadWatchedFolders() {
    // Try loading v2 format first
    if let data = UserDefaults.standard.data(forKey: "watchedFolders"),
       let folders = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
        watchedFolders = folders
        return
    }

    // Migrate from v1 single watchPath
    if let oldPath = UserDefaults.standard.string(forKey: "watchPath") {
        let expandedPath = NSString(string: oldPath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        watchedFolders = [WatchedFolder(url: url, role: .inbox)]
        saveWatchedFolders()
        // Remove old key after migration
        UserDefaults.standard.removeObject(forKey: "watchPath")
        return
    }

    // Default: watch ~/Downloads as inbox
    let defaultPath = NSString(string: "~/Downloads").expandingTildeInPath
    watchedFolders = [WatchedFolder(url: URL(fileURLWithPath: defaultPath), role: .inbox)]
    saveWatchedFolders()
}
```

- [ ] **Step 2: Update start() to use watchedFolders and create multi-path FileWatcher**

Replace the relevant section of `start()`:

```swift
func start() async {
    // Load saved settings
    loadWatchedFolders()
    autoMoveThreshold = UserDefaults.standard.object(forKey: "autoMoveThreshold") as? Double ?? 80
    suggestThreshold = UserDefaults.standard.object(forKey: "suggestThreshold") as? Double ?? 50
    settleTime = UserDefaults.standard.object(forKey: "settleTime") as? Double ?? 5
    showNotifications = UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true
    soundOnAutoMove = UserDefaults.standard.bool(forKey: "soundOnAutoMove")
    dropboxSyncPath = UserDefaults.standard.string(forKey: "dropboxSyncPath") ?? "~/Dropbox"

    loadPinnedRules()

    do {
        // ... existing KnowledgeBase setup code stays the same ...
        let syncPath = NSString(string: dropboxSyncPath).expandingTildeInPath
        let dbPath: String
        let tidyDir = "\(syncPath)/.tidy"
        let dropboxPath = "\(tidyDir)/knowledge.db"
        if FileManager.default.fileExists(atPath: syncPath) {
            try FileManager.default.createDirectory(atPath: tidyDir, withIntermediateDirectories: true)
            dbPath = dropboxPath
        } else {
            let appSupport = NSString(string: "~/Library/Application Support/Tidy").expandingTildeInPath
            try FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
            dbPath = "\(appSupport)/knowledge.db"
        }

        let kb = try KnowledgeBase(path: dbPath)
        patternCount = (try? kb.patternCount()) ?? 0

        let roots = [
            NSString(string: "~/Documents").expandingTildeInPath,
            NSString(string: "~/Dropbox").expandingTildeInPath,
            NSString(string: "~/Desktop").expandingTildeInPath,
            NSString(string: "~/Pictures").expandingTildeInPath,
        ].filter { FileManager.default.fileExists(atPath: $0) }

        let affinities = FolderArchaeologist().scan(roots: roots)
        let clusters = TokenClusterer().buildClusters(roots: roots)
        let heuristics = HeuristicsEngine(affinities: affinities, clusters: clusters)
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)

        let orch = MoveOrchestrator(
            scoringEngine: engine, knowledgeBase: kb, settleSeconds: settleTime
        )
        self.orchestrator = orch

        // Create BulkCleanupEngine
        self.bulkCleanupEngine = BulkCleanupEngine(
            scoringEngine: engine, knowledgeBase: kb
        )

        // Multi-folder FileWatcher
        let enabledPaths = watchedFolders
            .filter { $0.isEnabled }
            .map { $0.expandedPath }

        guard !enabledPaths.isEmpty else { return }

        let watcher = FileWatcher(watchPaths: enabledPaths)
        self.fileWatcher = watcher
        watcher.start()

        watchTask = Task { [weak self] in
            for await event in watcher.events {
                await self?.handleFileEvent(event)
            }
        }

        recentMoves = try kb.recentMoves(limit: 20)
        updateCounts()
    } catch { }
}
```

- [ ] **Step 3: Update handleFileEvent to use source folder and folder roles**

Replace `handleFileEvent` in `AppState.swift`:

```swift
private func handleFileEvent(_ event: FileEvent) async {
    guard let orchestrator else { return }

    // Find the WatchedFolder for this event's source
    func folderForSource(_ sourceFolder: String) -> WatchedFolder? {
        watchedFolders.first { $0.expandedPath == sourceFolder }
    }

    switch event {
    case .created(let path, let sourceFolder), .modified(let path, let sourceFolder):
        guard let folder = folderForSource(sourceFolder) else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attrs?[.size] as? UInt64 ?? 0
        let metadata = FileMetadataExtractor().extract(from: path)
        let candidate = FileCandidate(path: path, fileSize: fileSize, metadata: metadata)

        iconState = .processing
        defer { updateIconState() }

        if let orchEvent = try? await orchestrator.processFile(
            candidate,
            folderRole: folder.role,
            folderIgnorePatterns: folder.ignorePatterns
        ) {
            handleOrchestratorEvent(orchEvent)
        }

    case .movedOut(let path, let sourceFolder):
        guard let folder = folderForSource(sourceFolder) else { return }
        if folder.role == .inbox {
            let filename = (path as NSString).lastPathComponent
            _ = try? await orchestrator.recordUserMove(filename: filename, fileSize: 0, destination: "unknown")
        }

    case .movedIn(_, _):
        // File arrived from outside -- no action needed unless future feature
        break

    case .renamedPair(let oldPath, let newPath, let sourceFolder):
        guard let folder = folderForSource(sourceFolder) else { return }
        if folder.role == .watchOnly {
            // Learn from the move in a watch-only folder
            let filename = (oldPath as NSString).lastPathComponent
            let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
            let fileSize = attrs?[.size] as? UInt64 ?? 0
            if let event = try? await orchestrator.recordWatchOnlyMove(
                filename: filename,
                fileSize: fileSize,
                sourcePath: oldPath,
                destinationPath: newPath
            ) {
                handleOrchestratorEvent(event)
            }
        }

    case .removed:
        break
    }
}
```

- [ ] **Step 4: Add bulk cleanup state properties**

Add to `AppState`:

```swift
private var bulkCleanupEngine: BulkCleanupEngine?
var cleanupResult: CleanupResult?
var cleanupProgress: CleanupProgress?
var isCleaningUp: Bool = false
var lastBatchId: String?
```

- [ ] **Step 5: Add bulk cleanup methods to AppState**

```swift
func startCleanup(directory: URL, recursive: Bool = false) {
    guard let bulkCleanupEngine, !isCleaningUp else { return }
    isCleaningUp = true
    cleanupResult = nil
    cleanupProgress = CleanupProgress(total: 0)

    Task {
        do {
            let result = try await bulkCleanupEngine.cleanup(
                directory: directory,
                recursive: recursive,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.cleanupProgress = progress
                    }
                }
            )
            cleanupResult = result
            lastBatchId = result?.batchId
            isCleaningUp = false
        } catch {
            isCleaningUp = false
        }
    }
}

func cancelCleanup() {
    guard let bulkCleanupEngine else { return }
    Task {
        await bulkCleanupEngine.cancel()
        isCleaningUp = false
    }
}

func moveAllHighConfidence() {
    guard let bulkCleanupEngine, let result = cleanupResult else { return }
    Task {
        let records = try await bulkCleanupEngine.executeApproved(
            items: result.highConfidence,
            batchId: result.batchId
        )
        for record in records {
            recentMoves.insert(record, at: 0)
        }
        if recentMoves.count > 20 { recentMoves = Array(recentMoves.prefix(20)) }
        movedTodayCount += records.count
        // Remove moved items from cleanup result
        let movedPaths = Set(records.map { $0.sourcePath })
        let remaining = result.items.filter { !movedPaths.contains($0.candidate.path) }
        cleanupResult = CleanupResult(items: remaining, batchId: result.batchId)
        updateIconState()
    }
}

func undoLastBatch() {
    guard let bulkCleanupEngine, let batchId = lastBatchId else { return }
    Task {
        let count = try await bulkCleanupEngine.undoBatch(batchId: batchId)
        if count > 0 {
            movedTodayCount = max(0, movedTodayCount - count)
            // Reload recent moves
            if let kb = try? KnowledgeBase(path: "") {
                // In practice, reloadMoves from the stored kb
            }
            lastBatchId = nil
            cleanupResult = nil
            updateIconState()
        }
    }
}
```

- [ ] **Step 6: Update updateCounts() for multi-folder**

```swift
private func updateCounts() {
    var total = 0
    for folder in watchedFolders where folder.isEnabled && folder.role == .inbox {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.expandedPath)) ?? []
        total += contents.filter { !$0.hasPrefix(".") }.count
    }
    unsortedCount = total
}
```

- [ ] **Step 7: Add folder management methods**

```swift
func addWatchedFolder(url: URL, role: FolderRole) {
    guard !watchedFolders.contains(where: { $0.url == url }) else { return }
    watchedFolders.append(WatchedFolder(url: url, role: role))
    restartWatcher()
}

func removeWatchedFolder(url: URL) {
    watchedFolders.removeAll { $0.url == url }
    restartWatcher()
}

func updateFolderRole(url: URL, role: FolderRole) {
    if let index = watchedFolders.firstIndex(where: { $0.url == url }) {
        watchedFolders[index].role = role
    }
}

func toggleFolder(url: URL, enabled: Bool) {
    if let index = watchedFolders.firstIndex(where: { $0.url == url }) {
        watchedFolders[index].isEnabled = enabled
        restartWatcher()
    }
}

func updateFolderIgnorePatterns(url: URL, patterns: [String]) {
    if let index = watchedFolders.firstIndex(where: { $0.url == url }) {
        watchedFolders[index].ignorePatterns = patterns
    }
}

private func restartWatcher() {
    fileWatcher?.stop()
    watchTask?.cancel()

    let enabledPaths = watchedFolders
        .filter { $0.isEnabled }
        .map { $0.expandedPath }

    guard !enabledPaths.isEmpty else { return }

    let watcher = FileWatcher(watchPaths: enabledPaths)
    self.fileWatcher = watcher
    watcher.start()

    watchTask = Task { [weak self] in
        for await event in watcher.events {
            await self?.handleFileEvent(event)
        }
    }
}
```

- [ ] **Step 8: Verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 9: Commit**

```bash
git add Sources/Tidy/AppState.swift
git commit -m "feat: migrate AppState to multi-folder watching with bulk cleanup support

Converts watchPath to watchedFolders JSON array in UserDefaults. Auto-migrates
v1 single watch path. FileWatcher uses multiple paths. Event handling respects
folder roles. Bulk cleanup state management and folder CRUD methods added."
```

---

## Task 9: Settings UI — Folder List Editor

**Files:**
- Modify: `Sources/Tidy/Views/SettingsView.swift`

- [ ] **Step 1: Replace the watch folder section with a folder list editor**

In `Sources/Tidy/Views/SettingsView.swift`, replace the `LabeledContent("Watch folder")` block with:

```swift
// Watched folders
VStack(alignment: .leading, spacing: 4) {
    Text("Watched folders").font(.system(size: 12, weight: .semibold))
    ForEach(state.watchedFolders) { folder in
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { folder.isEnabled },
                set: { state.toggleFolder(url: folder.url, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.tildeCompactedPath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(folder.role.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { folder.role },
                set: { state.updateFolderRole(url: folder.url, role: $0) }
            )) {
                ForEach(FolderRole.allCases, id: \.self) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .controlSize(.small)

            Button(action: { state.removeWatchedFolder(url: folder.url) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    Button("+ Add folder") { pickNewWatchFolder() }
        .font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
}
```

- [ ] **Step 2: Add the folder picker method**

Add to `SettingsView`:

```swift
private func pickNewWatchFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Watch Folder"
    if panel.runModal() == .OK, let url = panel.url {
        state.addWatchedFolder(url: url, role: .inbox)
    }
}
```

- [ ] **Step 3: Remove old pickWatchFolder method**

Remove the old `pickWatchFolder()` method and any references to `state.watchPath` in SettingsView.

- [ ] **Step 4: Verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/Tidy/Views/SettingsView.swift
git commit -m "feat: replace single watch folder with folder list editor and role selector"
```

---

## Task 10: Panel UI — Clean Up Button and Progress

**Files:**
- Modify: `Sources/Tidy/Views/PanelView.swift`

- [ ] **Step 1: Add Clean Up button to header**

In `Sources/Tidy/Views/PanelView.swift`, add to the header HStack (before the settings button):

```swift
HStack {
    Text("Tidy").font(.headline)
    Spacer()
    Button(action: { showCleanupPicker = true }) {
        Image(systemName: "sparkles")
    }.buttonStyle(.plain)
    Button(action: { state.showSettings.toggle() }) {
        Image(systemName: "gearshape")
    }.buttonStyle(.plain)
    Button(action: { state.isPaused.toggle() }) {
        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
    }.buttonStyle(.plain)
}
```

Add `@State private var showCleanupPicker = false` at the top of PanelView.

- [ ] **Step 2: Add cleanup progress and results section**

After the header Divider, add a cleanup section before the existing content:

```swift
// Cleanup progress/results
if state.isCleaningUp {
    VStack(spacing: 4) {
        HStack {
            Text("Scanning...")
                .font(.caption.weight(.medium))
            Spacer()
            if let progress = state.cleanupProgress {
                Text("\(progress.scanned)/\(progress.total) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Cancel") { state.cancelCleanup() }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
        }
        if let progress = state.cleanupProgress {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
        }
    }
    .padding(.horizontal)
    .padding(.vertical, 6)
    Divider()
}

if let result = state.cleanupResult, !result.items.isEmpty {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text("Cleanup Results")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !result.highConfidence.isEmpty {
                Button("Move All (\(result.highConfidence.count))") {
                    state.moveAllHighConfidence()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)

        if !result.highConfidence.isEmpty {
            Text("High confidence (\(result.highConfidence.count))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal)
        }
        if !result.suggestions.isEmpty {
            Text("Suggestions (\(result.suggestions.count))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal)
        }
        if !result.needsReview.isEmpty {
            Text("Needs review (\(result.needsReview.count))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }

        if state.lastBatchId != nil {
            Button("Undo Cleanup") { state.undoLastBatch() }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .padding(.horizontal)
        }
    }
    .padding(.vertical, 6)
    Divider()
}
```

- [ ] **Step 3: Add folder picker sheet for cleanup**

Add at the end of the view body, after `.frame(width: 360, height: 480)`:

```swift
.sheet(isPresented: $showCleanupPicker) {
    VStack(spacing: 12) {
        Text("Clean Up Folder").font(.headline)
        Text("Select a folder to organize")
            .font(.caption).foregroundStyle(.secondary)

        Button("Choose Folder...") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Clean Up"
            if panel.runModal() == .OK, let url = panel.url {
                showCleanupPicker = false
                state.startCleanup(directory: url)
            }
        }

        Button("Cancel") { showCleanupPicker = false }
            .font(.caption)
    }
    .padding()
    .frame(width: 280)
}
```

- [ ] **Step 4: Update StatusFooter to show multi-folder count**

In `Sources/Tidy/Views/PanelView.swift`, update the StatusFooter to use the first inbox folder's name or a generic label:

```swift
StatusFooter(
    watchPath: state.watchedFolders.first(where: { $0.role == .inbox })?.tildeCompactedPath ?? "No folders",
    unsortedCount: state.unsortedCount,
    movedTodayCount: state.movedTodayCount
)
```

- [ ] **Step 5: Verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/Tidy/Views/PanelView.swift
git commit -m "feat: add Clean Up button, progress indicator, and batch undo to panel UI"
```

---

## Task 11: Integration Test — Full Multi-Folder Pipeline

**Files:**
- Create: `Tests/TidyCoreTests/MultiFolderIntegrationTests.swift`

- [ ] **Step 1: Write the integration test**

```swift
// Tests/TidyCoreTests/MultiFolderIntegrationTests.swift
import Testing
@testable import TidyCore

@Suite("Multi-Folder Integration")
struct MultiFolderIntegrationTests {
    @Test("WatchedFolder with inbox role processes files through orchestrator")
    func inboxProcessing() async throws {
        let dir = makeTemporaryDirectory(prefix: "inbox-test")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let filePath = dir + "/report.pdf"
        createFile(atPath: filePath, text: "quarterly report content")

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let orchestrator = MoveOrchestrator(scoringEngine: engine, knowledgeBase: kb)

        let candidate = FileCandidate(path: filePath, fileSize: 24)
        let event = try await orchestrator.processFile(candidate, folderRole: .inbox)

        // Should return newFile since no patterns exist
        #expect(event != nil)
        if case .newFile = event {
            // Expected
        } else {
            #expect(Bool(false), "Expected newFile event for unrecognized file")
        }
    }

    @Test("BulkCleanupEngine scans and scores folder contents")
    func bulkCleanupIntegration() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-integration")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        // Create test files
        createFile(atPath: dir + "/invoice.pdf", text: "Invoice #123")
        createFile(atPath: dir + "/photo.jpg")
        createFile(atPath: dir + "/notes.txt", text: "Meeting notes")

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)

        let cleanup = BulkCleanupEngine(scoringEngine: engine, knowledgeBase: kb)

        var progressUpdates: [CleanupProgress] = []
        let result = try await cleanup.cleanup(
            directory: URL(fileURLWithPath: dir),
            onProgress: { progress in
                progressUpdates.append(progress)
            }
        )

        #expect(result != nil)
        #expect(result!.totalCount == 3)
        // No patterns exist, so all should be in needsReview
        #expect(result!.needsReview.count == 3)
        #expect(result!.batchId.isEmpty == false)
        // At least one progress update
        #expect(!progressUpdates.isEmpty)
    }

    @Test("BulkCleanupEngine cancel stops processing")
    func bulkCleanupCancel() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-cancel")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        // Create many files
        for i in 0..<100 {
            createFile(atPath: dir + "/file\(i).txt", text: "content \(i)")
        }

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let cleanup = BulkCleanupEngine(scoringEngine: engine, knowledgeBase: kb)

        // Cancel immediately
        await cleanup.cancel()

        let result = try await cleanup.cleanup(directory: URL(fileURLWithPath: dir))
        // Should return nil when cancelled
        #expect(result == nil)
    }

    @Test("IgnoreFilter applies per-folder patterns during bulk scan")
    func perFolderIgnoreInBulk() async throws {
        let dir = makeTemporaryDirectory(prefix: "bulk-ignore")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        createFile(atPath: dir + "/report.pdf")
        createFile(atPath: dir + "/debug.log")
        createFile(atPath: dir + "/app.log")

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let cleanup = BulkCleanupEngine(scoringEngine: engine, knowledgeBase: kb)

        let candidates = await cleanup.scan(
            directory: URL(fileURLWithPath: dir),
            folderIgnorePatterns: ["*.log"]
        )
        // Should find only report.pdf, skipping .log files
        #expect(candidates.count == 1)
        #expect(candidates[0].filename == "report.pdf")
    }

    @Test("batch undo reverts moves and skips already-moved files")
    func batchUndoIntegration() async throws {
        let sourceDir = makeTemporaryDirectory(prefix: "batch-src")
        let destDir = makeTemporaryDirectory(prefix: "batch-dst")
        try createDirectory(atPath: sourceDir)
        try createDirectory(atPath: destDir)
        defer {
            removeItem(atPath: sourceDir)
            removeItem(atPath: destDir)
        }

        // Create and move files manually to simulate cleanup
        createFile(atPath: sourceDir + "/a.txt", text: "aaa")
        createFile(atPath: sourceDir + "/b.txt", text: "bbb")

        let kb = try KnowledgeBase.inMemory()
        let heuristics = HeuristicsEngine(affinities: [], clusters: [])
        let engine = try ScoringEngine(knowledgeBase: kb, heuristicsEngine: heuristics)
        let cleanup = BulkCleanupEngine(scoringEngine: engine, knowledgeBase: kb)

        let batchId = await cleanup.generateBatchId()

        // Simulate moves with batch ID
        let fm = FileManager.default
        try fm.moveItem(atPath: sourceDir + "/a.txt", toPath: destDir + "/a.txt")
        try fm.moveItem(atPath: sourceDir + "/b.txt", toPath: destDir + "/b.txt")

        try kb.recordMove(
            filename: "a.txt", sourcePath: sourceDir + "/a.txt",
            destinationPath: destDir + "/a.txt", confidence: 90, wasAuto: false, batchId: batchId
        )
        try kb.recordMove(
            filename: "b.txt", sourcePath: sourceDir + "/b.txt",
            destinationPath: destDir + "/b.txt", confidence: 85, wasAuto: false, batchId: batchId
        )

        // Remove one file from destination (simulates user manually moving it)
        try fm.removeItem(atPath: destDir + "/b.txt")

        // Undo batch -- should undo only a.txt (b.txt is gone)
        let undone = try await cleanup.undoBatch(batchId: batchId)
        #expect(undone == 1)
        #expect(fm.fileExists(atPath: sourceDir + "/a.txt"))
        #expect(!fm.fileExists(atPath: destDir + "/a.txt"))
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter MultiFolderIntegrationTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add Tests/TidyCoreTests/MultiFolderIntegrationTests.swift
git commit -m "test: add multi-folder and bulk cleanup integration tests"
```

---

## Task 12: Run Full Test Suite and Fix Compilation

**Files:**
- Various test files may need updates for FileEvent API changes

- [ ] **Step 1: Attempt full test suite build**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: May fail if existing tests reference old `FileEvent` cases without `sourceFolder`

- [ ] **Step 2: Fix any compilation errors in existing tests**

Update any existing test files that create `FileEvent` values to include the `sourceFolder` parameter:

- `FileEvent.created(path:)` becomes `FileEvent.created(path:, sourceFolder: "")`
- `FileEvent.modified(path:)` becomes `FileEvent.modified(path:, sourceFolder: "")`
- `FileEvent.removed(path:)` becomes `FileEvent.removed(path:, sourceFolder: "")`
- `FileEvent.movedOut(path:)` becomes `FileEvent.movedOut(path:, sourceFolder: "")`

Also update any code in `AppState.swift` that pattern-matches on `FileEvent` cases to use the new signatures (the `handleFileEvent` method already handles this in Task 8).

- [ ] **Step 3: Fix any test references to old `MoveRecord` init**

If tests create `MoveRecord` directly, add `batchId: nil` to the initializer.

- [ ] **Step 4: Run full test suite again**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix: update existing tests for FileEvent sourceFolder and MoveRecord batchId changes"
```

---

## Summary

| Task | New/Modified Files | What it does |
|------|--------------------|-------------|
| 1 | `WatchedFolder.swift`, test | FolderRole enum + WatchedFolder Codable struct |
| 2 | `FileWatcher.swift`, test | Multi-path FSEvents stream, sourceFolder tagging, rename pair detection |
| 3 | `IgnoreFilter.swift`, test | Per-folder glob-style ignore patterns |
| 4 | `MoveRecord.swift`, `KnowledgeBase.swift`, `UndoLog.swift`, test | batchId property, batch query methods, batch undo |
| 5 | `OrchestratorEvent.swift` | Add learnedMove case for watch-only observations |
| 6 | `MoveOrchestrator.swift`, test | FolderRole-aware processFile, recordWatchOnlyMove |
| 7 | `BulkCleanupEngine.swift`, test | Full cleanup actor: scan, score, tier, execute, batch undo |
| 8 | `AppState.swift` | watchPath-to-watchedFolders migration, multi-folder watcher, cleanup state |
| 9 | `SettingsView.swift` | Folder list editor with role picker, add/remove folders |
| 10 | `PanelView.swift` | Clean Up button, progress bar, batch undo button |
| 11 | Integration test | End-to-end multi-folder + bulk cleanup tests |
| 12 | Various | Fix compilation across full test suite |

**Estimated time:** 12 tasks, ~60-90 minutes total with TDD cadence.
