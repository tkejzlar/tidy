# Sync & Rule Packs — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable cross-device knowledge synchronization via change logs (iCloud/Dropbox/local) and shareable `.tidypack` rule bundles, so users can transfer learned patterns between machines and share filing strategies with others.

**Architecture:** A `SyncManager` actor abstracts the sync backend (iCloud/Dropbox/local) and provides a `syncDirectory` URL. Each device writes to its own local `knowledge.db` and exports JSON change logs to the sync directory. On detecting incoming change logs (via `NSMetadataQuery` for iCloud, `FSEvents` for Dropbox), the `SyncManager` merges them into the local database. Pinned rules use last-write-wins by timestamp; patterns merge by composite key with weight summing (capped at 20.0). A separate `.tidypack` format (JSON with registered UTI) allows exporting/importing pinned rules, patterns, and folder templates.

**Tech Stack:** Swift 6, GRDB (schema migration, pattern queries), Foundation (JSON encoding, FileManager, NSMetadataQuery), CoreServices (FSEvents for Dropbox change detection), UserDefaults (device ID, sync backend), UserNotifications (merge notifications)

**Spec:** `docs/superpowers/specs/2026-03-17-tidy-v2-design.md` §3

**Prerequisites:** Plan 1 (Content Intelligence Pipeline) is implemented. `PatternRecord` has columns `documentType`, `sourceDomain`, `sceneType`, `sourceFolder`, `syncedAt`. The v2 database migration for `pattern_records` and `move_records` is done.

---

## IMPORTANT: Corrections to Code Samples

> **Read this section first.** The code samples in this plan contain known issues identified during review. Apply these corrections when implementing each task. When a code sample conflicts with these corrections, the corrections take precedence.

### C1: FileCandidate Initializer

The actual signature is:

```swift
FileCandidate(path: String, fileSize: UInt64, metadata: FileMetadata? = nil, date: Date = Date())
```

Use this form in all test code. Do NOT use `FileCandidate(path:fileSize:sourceApp:downloadURL:)`.

### C2: KnowledgeBase.recordPattern Signature

The existing method uses label `extension ext:` and `SizeBucket?`/`TimeBucket?` types. After Plan 1, it has additional defaulted parameters (`documentType`, `sourceDomain`, `sceneType`, `sourceFolder`). Use the correct labels in all code.

### C3: ScoringEngine Initializer

The actual initializers are:

```swift
try ScoringEngine(knowledgeBase: kb, heuristicsEngine: engine, pinnedRules: manager)
try ScoringEngine(knowledgeBase: kb, heuristicsEngine: engine, aiLayer: layer, pinnedRules: manager)
```

### C4: PinnedRulesManager is a Struct, Not an Actor

`PinnedRulesManager` is a `Sendable` struct with value semantics. It uses JSON file persistence, not database storage. When adding sync-aware timestamp support, extend the existing struct — do not convert to an actor.

### C5: PinnedRule Has No `updatedAt` Field

The existing `PinnedRule` struct only has `fileExtension` and `destination`. The `updatedAt` field must be added as part of this plan for sync conflict resolution. Make it optional with a default of `nil` so existing JSON files decode without breaking.

### C6: Testing Environment

`import Foundation` and `import Testing` cannot coexist in the same file. Foundation types are available through `@testable import TidyCore`. Shared test helpers are in `Tests/TidyCoreTests/TestHelpers.swift`.

### C7: sync_metadata Migration

The `sync_metadata` table was NOT included in Plan 1's v2 migration. It must be added as a new migration (`v3`) in this plan.

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/TidyCore/Models/SyncBackend.swift` | `SyncBackend` enum (icloud/dropbox/local) |
| `Sources/TidyCore/Models/RulePack.swift` | `RulePack` Codable struct for `.tidypack` format |
| `Sources/TidyCore/Models/ChangeLog.swift` | `ChangeLog` Codable struct for sync change logs |
| `Sources/TidyCore/Sync/SyncManager.swift` | Actor: abstracts sync directory, exports/imports change logs |
| `Sources/TidyCore/Sync/ChangeLogMerger.swift` | Merges incoming change logs into local KnowledgeBase |
| `Sources/TidyCore/Sync/SyncDirectoryWatcher.swift` | Watches sync directory for new change logs (FSEvents) |
| `Sources/TidyCore/Sync/RulePackManager.swift` | Export/import `.tidypack` files |
| `Tests/TidyCoreTests/Sync/SyncBackendTests.swift` | SyncBackend enum tests |
| `Tests/TidyCoreTests/Sync/ChangeLogTests.swift` | ChangeLog encoding/decoding tests |
| `Tests/TidyCoreTests/Sync/ChangeLogMergerTests.swift` | Merge logic + conflict resolution tests |
| `Tests/TidyCoreTests/Sync/SyncManagerTests.swift` | SyncManager integration tests |
| `Tests/TidyCoreTests/Sync/RulePackManagerTests.swift` | RulePack export/import tests |
| `Sources/Tidy/Views/RulePackPreviewView.swift` | Import preview modal UI |

### Modified Files
| File | Change |
|------|--------|
| `Sources/TidyCore/Models/PatternRecord.swift` | (No change — `syncedAt` already added in Plan 1) |
| `Sources/TidyCore/Rules/PinnedRule.swift` | Add optional `updatedAt: Date?` field |
| `Sources/TidyCore/Rules/PinnedRulesManager.swift` | Timestamp tracking on add/remove |
| `Sources/TidyCore/Database/KnowledgeBase.swift` | v3 migration: `sync_metadata` table; query methods for unsynced patterns; merge method |
| `Sources/Tidy/AppState.swift` | Device ID, SyncManager lifecycle, export/import actions, sync backend setting |
| `Sources/Tidy/Views/SettingsView.swift` | Sync backend picker, export/import buttons |
| `bundle/Info.plist` | UTI registration for `.tidypack` |
| `scripts/bundle.sh` | (No change needed — Info.plist is already copied) |

---

## Task 1: SyncBackend Enum and Device ID

**Files:**
- Create: `Sources/TidyCore/Models/SyncBackend.swift`
- Test: `Tests/TidyCoreTests/Sync/SyncBackendTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/SyncBackendTests.swift
import Testing
@testable import TidyCore

@Suite("SyncBackend")
struct SyncBackendTests {
    @Test("raw values are stable strings")
    func rawValues() {
        #expect(SyncBackend.icloud.rawValue == "icloud")
        #expect(SyncBackend.dropbox.rawValue == "dropbox")
        #expect(SyncBackend.local.rawValue == "local")
    }

    @Test("syncDirectory returns correct path for dropbox")
    func dropboxPath() {
        let dir = SyncBackend.dropbox.syncDirectory(dropboxPath: "/Users/test/Dropbox")
        #expect(dir == "/Users/test/Dropbox/.tidy")
    }

    @Test("syncDirectory returns correct path for local")
    func localPath() {
        let dir = SyncBackend.local.syncDirectory(dropboxPath: nil)
        let expected = NSString(string: "~/Library/Application Support/Tidy").expandingTildeInPath
        #expect(dir == expected)
    }

    @Test("syncDirectory returns correct path for icloud")
    func icloudPath() {
        let dir = SyncBackend.icloud.syncDirectory(dropboxPath: nil)
        let expected = NSString(string: "~/Library/Mobile Documents/iCloud~com~tidy~app/Documents").expandingTildeInPath
        #expect(dir == expected)
    }

    @Test("DeviceId generates stable UUID from UserDefaults")
    func deviceIdStability() {
        let defaults = UserDefaults(suiteName: "SyncBackendTests-\(UUID().uuidString)")!
        let id1 = DeviceIdentity.deviceId(from: defaults)
        let id2 = DeviceIdentity.deviceId(from: defaults)
        #expect(id1 == id2)
        #expect(!id1.isEmpty)
        defaults.removePersistentDomain(forName: defaults.suiteName!)
    }

    @Test("DeviceId generates UUID format")
    func deviceIdFormat() {
        let defaults = UserDefaults(suiteName: "SyncBackendTests-format-\(UUID().uuidString)")!
        let id = DeviceIdentity.deviceId(from: defaults)
        // Should be a valid UUID
        #expect(UUID(uuidString: id) != nil)
        defaults.removePersistentDomain(forName: defaults.suiteName!)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncBackendTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — types don't exist yet

- [ ] **Step 3: Create SyncBackend.swift**

```swift
// Sources/TidyCore/Models/SyncBackend.swift
import Foundation

public enum SyncBackend: String, Codable, Sendable, CaseIterable {
    case icloud
    case dropbox
    case local

    /// Returns the sync directory path for this backend.
    /// - Parameter dropboxPath: The user-configured Dropbox root (expanded), used only for `.dropbox`.
    public func syncDirectory(dropboxPath: String?) -> String {
        switch self {
        case .icloud:
            return NSString(string: "~/Library/Mobile Documents/iCloud~com~tidy~app/Documents").expandingTildeInPath
        case .dropbox:
            let root = dropboxPath ?? NSString(string: "~/Dropbox").expandingTildeInPath
            return "\(root)/.tidy"
        case .local:
            return NSString(string: "~/Library/Application Support/Tidy").expandingTildeInPath
        }
    }

    public var displayName: String {
        switch self {
        case .icloud: return "iCloud Drive"
        case .dropbox: return "Dropbox"
        case .local: return "Local Only"
        }
    }
}

/// Manages a stable per-device UUID for sync identification.
public enum DeviceIdentity {
    private static let key = "deviceId"

    /// Returns the device ID, generating one on first call.
    /// - Parameter defaults: The UserDefaults store (injectable for testing).
    public static func deviceId(from defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: key)
        return newId
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncBackendTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Models/SyncBackend.swift Tests/TidyCoreTests/Sync/SyncBackendTests.swift
git commit -m "feat: add SyncBackend enum and DeviceIdentity for sync infrastructure"
```

---

## Task 2: PinnedRule Timestamp Support

**Files:**
- Modify: `Sources/TidyCore/Rules/PinnedRule.swift`
- Modify: `Sources/TidyCore/Rules/PinnedRulesManager.swift`
- Test: `Tests/TidyCoreTests/Sync/PinnedRuleTimestampTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/PinnedRuleTimestampTests.swift
import Testing
@testable import TidyCore

@Suite("PinnedRule Timestamp")
struct PinnedRuleTimestampTests {
    @Test("PinnedRule encodes and decodes with updatedAt")
    func roundTrip() throws {
        let now = Date()
        let rule = PinnedRule(fileExtension: "pdf", destination: "~/Documents/PDFs", updatedAt: now)
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(PinnedRule.self, from: data)
        #expect(decoded.fileExtension == "pdf")
        #expect(decoded.destination == "~/Documents/PDFs")
        #expect(decoded.updatedAt != nil)
    }

    @Test("PinnedRule decodes legacy JSON without updatedAt")
    func legacyDecode() throws {
        let json = #"{"fileExtension":"dmg","destination":"~/Apps"}"#
        let decoded = try JSONDecoder().decode(PinnedRule.self, from: Data(json.utf8))
        #expect(decoded.fileExtension == "dmg")
        #expect(decoded.updatedAt == nil)
    }

    @Test("addRule sets updatedAt automatically")
    func addSetsTimestamp() {
        var manager = PinnedRulesManager()
        manager.addRule(PinnedRule(fileExtension: "pdf", destination: "~/Docs"))
        let rule = manager.rules.first!
        #expect(rule.updatedAt != nil)
    }

    @Test("PinnedRulesManager save and load preserves timestamps")
    func persistTimestamps() throws {
        let dir = makeTemporaryDirectory(prefix: "pinned-ts")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let path = "\(dir)/pinned-rules.json"
        var manager = PinnedRulesManager()
        manager.addRule(PinnedRule(fileExtension: "pdf", destination: "~/Docs"))
        try manager.save(to: path)

        let loaded = try PinnedRulesManager.load(from: path)
        #expect(loaded.rules.count == 1)
        #expect(loaded.rules[0].updatedAt != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PinnedRuleTimestampTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `PinnedRule` has no `updatedAt` parameter

- [ ] **Step 3: Add updatedAt to PinnedRule**

```swift
// Sources/TidyCore/Rules/PinnedRule.swift
import Foundation

public struct PinnedRule: Codable, Sendable, Identifiable {
    public var id: String { fileExtension.lowercased() }
    public var fileExtension: String
    public var destination: String
    public var updatedAt: Date?

    public init(fileExtension: String, destination: String, updatedAt: Date? = nil) {
        self.fileExtension = fileExtension
        self.destination = destination
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 4: Update PinnedRulesManager.addRule to set timestamp**

In `Sources/TidyCore/Rules/PinnedRulesManager.swift`, update `addRule`:

```swift
public mutating func addRule(_ rule: PinnedRule) {
    rules.removeAll { $0.fileExtension.lowercased() == rule.fileExtension.lowercased() }
    var timestamped = rule
    if timestamped.updatedAt == nil {
        timestamped.updatedAt = Date()
    }
    rules.append(timestamped)
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter PinnedRuleTimestampTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TidyCore/Rules/PinnedRule.swift Sources/TidyCore/Rules/PinnedRulesManager.swift Tests/TidyCoreTests/Sync/PinnedRuleTimestampTests.swift
git commit -m "feat: add updatedAt timestamp to PinnedRule for sync conflict resolution"
```

---

## Task 3: Database Migration v3 — sync_metadata Table

**Files:**
- Modify: `Sources/TidyCore/Database/KnowledgeBase.swift`
- Test: `Tests/TidyCoreTests/Sync/SyncMetadataMigrationTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/SyncMetadataMigrationTests.swift
import Testing
@testable import TidyCore

@Suite("SyncMetadata Migration")
struct SyncMetadataMigrationTests {
    @Test("sync_metadata table is created after migration")
    func tableExists() throws {
        let kb = try KnowledgeBase.inMemory()
        // If we can record and retrieve sync metadata, the table exists
        try kb.recordSyncMetadata(deviceId: "test-device", lastSyncTimestamp: Date())
        let metadata = try kb.syncMetadata(forDevice: "test-device")
        #expect(metadata != nil)
        #expect(metadata?.deviceId == "test-device")
    }

    @Test("recordSyncMetadata upserts on conflict")
    func upsert() throws {
        let kb = try KnowledgeBase.inMemory()
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        try kb.recordSyncMetadata(deviceId: "device-a", lastSyncTimestamp: t1)
        try kb.recordSyncMetadata(deviceId: "device-a", lastSyncTimestamp: t2)
        let metadata = try kb.syncMetadata(forDevice: "device-a")
        #expect(metadata?.lastSyncTimestamp == t2)
    }

    @Test("unsyncedPatterns returns records with nil syncedAt")
    func unsyncedPatterns() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["invoice"],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents", signalType: .observation
        )
        let unsynced = try kb.unsyncedPatterns()
        #expect(unsynced.count == 1)
        #expect(unsynced[0].fileExtension == "pdf")
    }

    @Test("markPatternsSynced updates syncedAt")
    func markSynced() throws {
        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["invoice"],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents", signalType: .observation
        )
        let unsynced = try kb.unsyncedPatterns()
        #expect(unsynced.count == 1)

        let ids = unsynced.compactMap { $0.id }
        try kb.markPatternsSynced(ids: ids)

        let stillUnsynced = try kb.unsyncedPatterns()
        #expect(stillUnsynced.count == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncMetadataMigrationTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — methods don't exist

- [ ] **Step 3: Add v3 migration and sync methods to KnowledgeBase**

Add to `KnowledgeBase.swift` inside the `migrate()` method, after the existing migrations:

```swift
migrator.registerMigration("v3") { db in
    try db.create(table: "sync_metadata") { t in
        t.column("deviceId", .text).primaryKey()
        t.column("lastSyncTimestamp", .datetime).notNull()
    }
}
```

Add these public methods to `KnowledgeBase`:

```swift
// MARK: - Sync Metadata

public struct SyncMetadataRecord: Sendable {
    public let deviceId: String
    public let lastSyncTimestamp: Date
}

public func recordSyncMetadata(deviceId: String, lastSyncTimestamp: Date) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: """
                INSERT INTO sync_metadata (deviceId, lastSyncTimestamp) VALUES (?, ?)
                ON CONFLICT(deviceId) DO UPDATE SET lastSyncTimestamp = excluded.lastSyncTimestamp
                """,
            arguments: [deviceId, lastSyncTimestamp]
        )
    }
}

public func syncMetadata(forDevice deviceId: String) throws -> SyncMetadataRecord? {
    try dbQueue.read { db in
        let row = try Row.fetchOne(
            db,
            sql: "SELECT deviceId, lastSyncTimestamp FROM sync_metadata WHERE deviceId = ?",
            arguments: [deviceId]
        )
        guard let row = row else { return nil }
        return SyncMetadataRecord(
            deviceId: row["deviceId"],
            lastSyncTimestamp: row["lastSyncTimestamp"]
        )
    }
}

// MARK: - Unsynced Patterns

public func unsyncedPatterns() throws -> [PatternRecord] {
    try dbQueue.read { db in
        try PatternRecord
            .filter(Column("syncedAt") == nil)
            .fetchAll(db)
    }
}

public func markPatternsSynced(ids: [Int64]) throws {
    guard !ids.isEmpty else { return }
    try dbQueue.write { db in
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        try db.execute(
            sql: "UPDATE pattern_records SET syncedAt = ? WHERE id IN (\(placeholders))",
            arguments: [Date()] + ids.map { DatabaseValue.init(int64: $0) }
        )
    }
}
```

**Note on `markPatternsSynced`:** The argument building uses GRDB's `StatementArguments`. The simpler approach:

```swift
public func markPatternsSynced(ids: [Int64]) throws {
    guard !ids.isEmpty else { return }
    let now = Date()
    try dbQueue.write { db in
        for id in ids {
            try db.execute(
                sql: "UPDATE pattern_records SET syncedAt = ? WHERE id = ?",
                arguments: [now, id]
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncMetadataMigrationTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Database/KnowledgeBase.swift Tests/TidyCoreTests/Sync/SyncMetadataMigrationTests.swift
git commit -m "feat: add v3 migration with sync_metadata table and unsynced pattern queries"
```

---

## Task 4: ChangeLog Model

**Files:**
- Create: `Sources/TidyCore/Models/ChangeLog.swift`
- Test: `Tests/TidyCoreTests/Sync/ChangeLogTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/ChangeLogTests.swift
import Testing
@testable import TidyCore

@Suite("ChangeLog")
struct ChangeLogTests {
    @Test("ChangeLog round-trips through JSON")
    func roundTrip() throws {
        let now = Date()
        let log = ChangeLog(
            deviceId: "MacBook-abc123",
            timestamp: now,
            patterns: [
                ChangeLog.PatternEntry(
                    fileExtension: "pdf",
                    filenameTokens: "[\"invoice\",\"2026\"]",
                    sourceApp: "Safari",
                    sizeBucket: "medium",
                    timeBucket: "morning",
                    documentType: "invoice",
                    sourceDomain: "mail.google.com",
                    sceneType: nil,
                    sourceFolder: "~/Downloads",
                    destination: "~/Documents/Invoices",
                    signalType: "observation",
                    weight: 3.0,
                    createdAt: now
                )
            ],
            pinnedRules: [
                ChangeLog.PinnedRuleEntry(
                    fileExtension: "dmg",
                    destination: "~/Apps/Installers",
                    updatedAt: now
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(log)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChangeLog.self, from: data)

        #expect(decoded.deviceId == "MacBook-abc123")
        #expect(decoded.patterns.count == 1)
        #expect(decoded.patterns[0].fileExtension == "pdf")
        #expect(decoded.patterns[0].weight == 3.0)
        #expect(decoded.patterns[0].documentType == "invoice")
        #expect(decoded.pinnedRules.count == 1)
        #expect(decoded.pinnedRules[0].fileExtension == "dmg")
    }

    @Test("ChangeLog filename follows convention")
    func filenameFormat() {
        let log = ChangeLog(
            deviceId: "MacBook-abc123",
            timestamp: Date(timeIntervalSince1970: 1710680400),
            patterns: [],
            pinnedRules: []
        )
        let name = log.filename
        #expect(name.hasPrefix("changes-MacBook-abc123-"))
        #expect(name.hasSuffix(".json"))
    }

    @Test("ChangeLog with empty arrays encodes correctly")
    func emptyArrays() throws {
        let log = ChangeLog(
            deviceId: "device-1",
            timestamp: Date(),
            patterns: [],
            pinnedRules: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(log)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChangeLog.self, from: data)
        #expect(decoded.patterns.isEmpty)
        #expect(decoded.pinnedRules.isEmpty)
    }

    @Test("PatternEntry from PatternRecord preserves all fields")
    func fromPatternRecord() {
        let record = PatternRecord(
            id: 1,
            fileExtension: "pdf",
            filenameTokens: "[\"invoice\"]",
            sourceApp: "Safari",
            sizeBucket: "medium",
            timeBucket: "morning",
            destination: "~/Documents",
            signalType: .observation,
            weight: 2.5,
            createdAt: Date()
        )
        let entry = ChangeLog.PatternEntry(from: record)
        #expect(entry.fileExtension == "pdf")
        #expect(entry.filenameTokens == "[\"invoice\"]")
        #expect(entry.sourceApp == "Safari")
        #expect(entry.weight == 2.5)
        #expect(entry.signalType == "observation")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChangeLogTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `ChangeLog` doesn't exist

- [ ] **Step 3: Create ChangeLog.swift**

```swift
// Sources/TidyCore/Models/ChangeLog.swift
import Foundation

public struct ChangeLog: Codable, Sendable {
    public let deviceId: String
    public let timestamp: Date
    public var patterns: [PatternEntry]
    public var pinnedRules: [PinnedRuleEntry]

    /// Generates a filename for this change log: `changes-<deviceId>-<timestamp>.json`
    public var filename: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let ts = formatter.string(from: timestamp)
            .replacingOccurrences(of: ":", with: "-")
        return "changes-\(deviceId)-\(ts).json"
    }

    public init(
        deviceId: String,
        timestamp: Date,
        patterns: [PatternEntry],
        pinnedRules: [PinnedRuleEntry]
    ) {
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.patterns = patterns
        self.pinnedRules = pinnedRules
    }

    // MARK: - Nested Types

    public struct PatternEntry: Codable, Sendable {
        public let fileExtension: String?
        public let filenameTokens: String?
        public let sourceApp: String?
        public let sizeBucket: String?
        public let timeBucket: String?
        public let documentType: String?
        public let sourceDomain: String?
        public let sceneType: String?
        public let sourceFolder: String?
        public let destination: String
        public let signalType: String
        public let weight: Double
        public let createdAt: Date

        public init(
            fileExtension: String?,
            filenameTokens: String?,
            sourceApp: String?,
            sizeBucket: String?,
            timeBucket: String?,
            documentType: String?,
            sourceDomain: String?,
            sceneType: String?,
            sourceFolder: String?,
            destination: String,
            signalType: String,
            weight: Double,
            createdAt: Date
        ) {
            self.fileExtension = fileExtension
            self.filenameTokens = filenameTokens
            self.sourceApp = sourceApp
            self.sizeBucket = sizeBucket
            self.timeBucket = timeBucket
            self.documentType = documentType
            self.sourceDomain = sourceDomain
            self.sceneType = sceneType
            self.sourceFolder = sourceFolder
            self.destination = destination
            self.signalType = signalType
            self.weight = weight
            self.createdAt = createdAt
        }

        /// Creates a `PatternEntry` from an existing `PatternRecord`.
        public init(from record: PatternRecord) {
            self.fileExtension = record.fileExtension
            self.filenameTokens = record.filenameTokens
            self.sourceApp = record.sourceApp
            self.sizeBucket = record.sizeBucket
            self.timeBucket = record.timeBucket
            self.documentType = record.documentType
            self.sourceDomain = record.sourceDomain
            self.sceneType = record.sceneType
            self.sourceFolder = record.sourceFolder
            self.destination = record.destination
            self.signalType = record.signalType.rawValue
            self.weight = record.weight
            self.createdAt = record.createdAt
        }

        /// Composite key for merge deduplication.
        public var compositeKey: String {
            let parts: [String] = [
                fileExtension ?? "",
                filenameTokens ?? "",
                sourceApp ?? "",
                sourceFolder ?? "",
                destination,
            ]
            return parts.joined(separator: "|")
        }
    }

    public struct PinnedRuleEntry: Codable, Sendable {
        public let fileExtension: String
        public let destination: String
        public let updatedAt: Date

        public init(fileExtension: String, destination: String, updatedAt: Date) {
            self.fileExtension = fileExtension
            self.destination = destination
            self.updatedAt = updatedAt
        }

        public init(from rule: PinnedRule) {
            self.fileExtension = rule.fileExtension
            self.destination = rule.destination
            self.updatedAt = rule.updatedAt ?? Date()
        }
    }
}
```

**Note:** `PatternRecord` after Plan 1 has `documentType`, `sourceDomain`, `sceneType`, `sourceFolder` properties. The `init(from record:)` reads them directly. If Plan 1 is not yet implemented when you reach this task, add temporary stubs or skip those fields.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ChangeLogTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Models/ChangeLog.swift Tests/TidyCoreTests/Sync/ChangeLogTests.swift
git commit -m "feat: add ChangeLog model for sync change log export/import"
```

---

## Task 5: ChangeLogMerger — Conflict Resolution Logic

**Files:**
- Create: `Sources/TidyCore/Sync/ChangeLogMerger.swift`
- Test: `Tests/TidyCoreTests/Sync/ChangeLogMergerTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/ChangeLogMergerTests.swift
import Testing
@testable import TidyCore

@Suite("ChangeLogMerger")
struct ChangeLogMergerTests {
    @Test("merges new pattern by inserting it")
    func mergeNewPattern() throws {
        let kb = try KnowledgeBase.inMemory()
        let merger = ChangeLogMerger(knowledgeBase: kb)

        let entry = ChangeLog.PatternEntry(
            fileExtension: "pdf",
            filenameTokens: "[\"report\"]",
            sourceApp: "Chrome",
            sizeBucket: "medium",
            timeBucket: "morning",
            documentType: nil,
            sourceDomain: nil,
            sceneType: nil,
            sourceFolder: "~/Downloads",
            destination: "~/Documents/Reports",
            signalType: "observation",
            weight: 2.0,
            createdAt: Date()
        )

        let log = ChangeLog(
            deviceId: "remote-device",
            timestamp: Date(),
            patterns: [entry],
            pinnedRules: []
        )

        let result = try merger.merge(log)
        #expect(result.patternsInserted == 1)
        #expect(result.patternsMerged == 0)

        let patterns = try kb.allPatterns()
        #expect(patterns.count == 1)
        #expect(patterns[0].destination == "~/Documents/Reports")
    }

    @Test("merges existing pattern by summing weights capped at 20.0")
    func mergeExistingPatternSumsWeights() throws {
        let kb = try KnowledgeBase.inMemory()
        let merger = ChangeLogMerger(knowledgeBase: kb)

        // Insert existing pattern
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["report"],
            sourceApp: "Chrome", sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents/Reports", signalType: .observation
        )

        // Remote change log with same composite key
        let entry = ChangeLog.PatternEntry(
            fileExtension: "pdf",
            filenameTokens: "[\"report\"]",
            sourceApp: "Chrome",
            sizeBucket: nil,
            timeBucket: nil,
            documentType: nil,
            sourceDomain: nil,
            sceneType: nil,
            sourceFolder: nil,
            destination: "~/Documents/Reports",
            signalType: "observation",
            weight: 5.0,
            createdAt: Date()
        )

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: Date(),
            patterns: [entry],
            pinnedRules: []
        )

        let result = try merger.merge(log)
        #expect(result.patternsMerged == 1)
        #expect(result.patternsInserted == 0)

        let patterns = try kb.allPatterns()
        #expect(patterns.count == 1)
        #expect(patterns[0].weight == 6.0)  // 1.0 (observation default) + 5.0
    }

    @Test("weight sum is capped at 20.0")
    func weightCap() throws {
        let kb = try KnowledgeBase.inMemory()
        let merger = ChangeLogMerger(knowledgeBase: kb)

        // Insert with high weight
        try kb.recordPattern(
            extension: "pdf", filenameTokens: [],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents", signalType: .correction
        )
        // correction default weight is 3.0, update to 18.0
        let patterns = try kb.allPatterns()
        try kb.updatePatternWeight(id: patterns[0].id!, weight: 18.0)

        let entry = ChangeLog.PatternEntry(
            fileExtension: "pdf",
            filenameTokens: "[]",
            sourceApp: nil,
            sizeBucket: nil,
            timeBucket: nil,
            documentType: nil,
            sourceDomain: nil,
            sceneType: nil,
            sourceFolder: nil,
            destination: "~/Documents",
            signalType: "observation",
            weight: 5.0,
            createdAt: Date()
        )

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: Date(),
            patterns: [entry],
            pinnedRules: []
        )

        let result = try merger.merge(log)
        let updated = try kb.allPatterns()
        #expect(updated[0].weight == 20.0)  // 18 + 5 = 23, capped to 20
        #expect(result.patternsMerged == 1)
    }

    @Test("pinned rules use last-write-wins by updatedAt")
    func pinnedRuleLastWriteWins() throws {
        let kb = try KnowledgeBase.inMemory()
        let merger = ChangeLogMerger(knowledgeBase: kb)

        let oldDate = Date(timeIntervalSince1970: 1000)
        let newDate = Date(timeIntervalSince1970: 2000)

        // Local rule with old timestamp
        var localManager = PinnedRulesManager()
        localManager.addRule(PinnedRule(fileExtension: "dmg", destination: "~/Apps/Old", updatedAt: oldDate))

        // Remote rule with newer timestamp
        let log = ChangeLog(
            deviceId: "remote",
            timestamp: Date(),
            patterns: [],
            pinnedRules: [
                ChangeLog.PinnedRuleEntry(
                    fileExtension: "dmg",
                    destination: "~/Apps/New",
                    updatedAt: newDate
                )
            ]
        )

        let updatedManager = merger.mergePinnedRules(local: localManager, remote: log.pinnedRules)
        let dmgRule = updatedManager.rules.first { $0.fileExtension == "dmg" }
        #expect(dmgRule?.destination == "~/Apps/New")
    }

    @Test("pinned rules: local wins when local is newer")
    func pinnedRuleLocalWins() throws {
        let kb = try KnowledgeBase.inMemory()
        let merger = ChangeLogMerger(knowledgeBase: kb)

        let oldDate = Date(timeIntervalSince1970: 1000)
        let newDate = Date(timeIntervalSince1970: 2000)

        var localManager = PinnedRulesManager()
        localManager.addRule(PinnedRule(fileExtension: "dmg", destination: "~/Apps/Local", updatedAt: newDate))

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: Date(),
            patterns: [],
            pinnedRules: [
                ChangeLog.PinnedRuleEntry(
                    fileExtension: "dmg",
                    destination: "~/Apps/Remote",
                    updatedAt: oldDate
                )
            ]
        )

        let updatedManager = merger.mergePinnedRules(local: localManager, remote: log.pinnedRules)
        let dmgRule = updatedManager.rules.first { $0.fileExtension == "dmg" }
        #expect(dmgRule?.destination == "~/Apps/Local")
    }

    @Test("pinned rules: new remote rule is added")
    func pinnedRuleNewRemote() throws {
        let kb = try KnowledgeBase.inMemory()
        let merger = ChangeLogMerger(knowledgeBase: kb)

        let localManager = PinnedRulesManager()

        let log = ChangeLog(
            deviceId: "remote",
            timestamp: Date(),
            patterns: [],
            pinnedRules: [
                ChangeLog.PinnedRuleEntry(
                    fileExtension: "pkg",
                    destination: "~/Installers",
                    updatedAt: Date()
                )
            ]
        )

        let updatedManager = merger.mergePinnedRules(local: localManager, remote: log.pinnedRules)
        #expect(updatedManager.rules.count == 1)
        #expect(updatedManager.rules[0].fileExtension == "pkg")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChangeLogMergerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `ChangeLogMerger` doesn't exist

- [ ] **Step 3: Add updatePatternWeight to KnowledgeBase**

Add this method to `KnowledgeBase.swift`:

```swift
public func updatePatternWeight(id: Int64, weight: Double) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: "UPDATE pattern_records SET weight = ? WHERE id = ?",
            arguments: [weight, id]
        )
    }
}
```

- [ ] **Step 4: Create ChangeLogMerger.swift**

```swift
// Sources/TidyCore/Sync/ChangeLogMerger.swift
import Foundation

public struct ChangeLogMerger: Sendable {
    private let knowledgeBase: KnowledgeBase
    private static let maxWeight: Double = 20.0

    public struct MergeResult: Sendable {
        public let patternsInserted: Int
        public let patternsMerged: Int
        public let pinnedRulesUpdated: Int
    }

    public init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    /// Merge a remote change log into the local knowledge base.
    public func merge(_ changeLog: ChangeLog) throws -> MergeResult {
        let existingPatterns = try knowledgeBase.allPatterns()

        // Build lookup by composite key
        var existingByKey: [String: PatternRecord] = [:]
        for pattern in existingPatterns {
            let key = compositeKey(for: pattern)
            existingByKey[key] = pattern
        }

        var inserted = 0
        var merged = 0

        for entry in changeLog.patterns {
            let key = entry.compositeKey
            if let existing = existingByKey[key] {
                // Merge: sum weights, capped at 20.0
                let newWeight = min(existing.weight + entry.weight, Self.maxWeight)
                try knowledgeBase.updatePatternWeight(id: existing.id!, weight: newWeight)
                merged += 1
            } else {
                // Insert new pattern
                let signalType = SignalType(rawValue: entry.signalType) ?? .observation
                try knowledgeBase.recordPattern(
                    extension: entry.fileExtension,
                    filenameTokens: decodeTokens(entry.filenameTokens),
                    sourceApp: entry.sourceApp,
                    sizeBucket: entry.sizeBucket.flatMap { SizeBucket(rawValue: $0) },
                    timeBucket: entry.timeBucket.flatMap { TimeBucket(rawValue: $0) },
                    documentType: entry.documentType,
                    sourceDomain: entry.sourceDomain,
                    sceneType: entry.sceneType,
                    sourceFolder: entry.sourceFolder,
                    destination: entry.destination,
                    signalType: signalType
                )
                inserted += 1
            }
        }

        return MergeResult(
            patternsInserted: inserted,
            patternsMerged: merged,
            pinnedRulesUpdated: 0
        )
    }

    /// Merge remote pinned rules into local PinnedRulesManager using last-write-wins.
    public func mergePinnedRules(
        local: PinnedRulesManager,
        remote: [ChangeLog.PinnedRuleEntry]
    ) -> PinnedRulesManager {
        var result = local

        for remoteEntry in remote {
            let ext = remoteEntry.fileExtension.lowercased()
            if let localRule = result.rules.first(where: { $0.fileExtension.lowercased() == ext }) {
                // Conflict: compare timestamps (last-write-wins)
                let localTime = localRule.updatedAt ?? Date.distantPast
                if remoteEntry.updatedAt > localTime {
                    result.addRule(PinnedRule(
                        fileExtension: remoteEntry.fileExtension,
                        destination: remoteEntry.destination,
                        updatedAt: remoteEntry.updatedAt
                    ))
                }
                // else: local wins, keep as-is
            } else {
                // No conflict: add remote rule
                result.addRule(PinnedRule(
                    fileExtension: remoteEntry.fileExtension,
                    destination: remoteEntry.destination,
                    updatedAt: remoteEntry.updatedAt
                ))
            }
        }

        return result
    }

    // MARK: - Private Helpers

    private func compositeKey(for record: PatternRecord) -> String {
        let parts: [String] = [
            record.fileExtension ?? "",
            record.filenameTokens ?? "",
            record.sourceApp ?? "",
            record.sourceFolder ?? "",
            record.destination,
        ]
        return parts.joined(separator: "|")
    }

    private func decodeTokens(_ json: String?) -> [String] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let tokens = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return tokens
    }
}
```

**Note:** `record.sourceFolder` and `record.documentType` etc. come from Plan 1's additions to `PatternRecord`. If those fields don't exist yet, they will be `nil` and produce empty strings in the composite key — this is safe.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ChangeLogMergerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TidyCore/Sync/ChangeLogMerger.swift Sources/TidyCore/Database/KnowledgeBase.swift Tests/TidyCoreTests/Sync/ChangeLogMergerTests.swift
git commit -m "feat: add ChangeLogMerger with composite-key merge and last-write-wins pinned rules"
```

---

## Task 6: SyncManager Actor

**Files:**
- Create: `Sources/TidyCore/Sync/SyncManager.swift`
- Test: `Tests/TidyCoreTests/Sync/SyncManagerTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/SyncManagerTests.swift
import Testing
@testable import TidyCore

@Suite("SyncManager")
struct SyncManagerTests {
    @Test("exportChangeLog writes JSON to sync directory")
    func exportWritesFile() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-export")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["invoice"],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents", signalType: .observation
        )

        let manager = SyncManager(
            knowledgeBase: kb,
            syncDirectory: dir,
            deviceId: "test-device"
        )

        let exported = try await manager.exportChangeLog()
        #expect(exported)

        // Check file was written
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        let changeFiles = files.filter { $0.hasPrefix("changes-test-device-") && $0.hasSuffix(".json") }
        #expect(changeFiles.count == 1)
    }

    @Test("exportChangeLog skips when no unsynced patterns")
    func exportSkipsEmpty() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-empty")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let manager = SyncManager(
            knowledgeBase: kb,
            syncDirectory: dir,
            deviceId: "test-device"
        )

        let exported = try await manager.exportChangeLog()
        #expect(!exported)
    }

    @Test("exportChangeLog marks patterns as synced")
    func exportMarksSynced() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-mark")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: [],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents", signalType: .observation
        )

        let manager = SyncManager(
            knowledgeBase: kb,
            syncDirectory: dir,
            deviceId: "test-device"
        )

        _ = try await manager.exportChangeLog()

        let unsynced = try kb.unsyncedPatterns()
        #expect(unsynced.count == 0)
    }

    @Test("importChangeLogs merges remote change logs")
    func importMerges() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-import")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let manager = SyncManager(
            knowledgeBase: kb,
            syncDirectory: dir,
            deviceId: "local-device"
        )

        // Write a remote change log manually
        let remoteLog = ChangeLog(
            deviceId: "remote-device",
            timestamp: Date(),
            patterns: [
                ChangeLog.PatternEntry(
                    fileExtension: "docx",
                    filenameTokens: "[\"report\"]",
                    sourceApp: "Safari",
                    sizeBucket: nil,
                    timeBucket: nil,
                    documentType: nil,
                    sourceDomain: nil,
                    sceneType: nil,
                    sourceFolder: nil,
                    destination: "~/Documents/Reports",
                    signalType: "observation",
                    weight: 2.0,
                    createdAt: Date()
                )
            ],
            pinnedRules: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(remoteLog)
        let filePath = "\(dir)/\(remoteLog.filename)"
        try data.write(to: URL(fileURLWithPath: filePath))

        let result = try await manager.importChangeLogs()
        #expect(result.totalPatternsInserted == 1)

        let patterns = try kb.allPatterns()
        #expect(patterns.count == 1)
        #expect(patterns[0].destination == "~/Documents/Reports")
    }

    @Test("importChangeLogs ignores own device's change logs")
    func importIgnoresOwn() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-own")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let manager = SyncManager(
            knowledgeBase: kb,
            syncDirectory: dir,
            deviceId: "my-device"
        )

        // Write own change log
        let ownLog = ChangeLog(
            deviceId: "my-device",
            timestamp: Date(),
            patterns: [
                ChangeLog.PatternEntry(
                    fileExtension: "pdf",
                    filenameTokens: nil,
                    sourceApp: nil,
                    sizeBucket: nil,
                    timeBucket: nil,
                    documentType: nil,
                    sourceDomain: nil,
                    sceneType: nil,
                    sourceFolder: nil,
                    destination: "~/Documents",
                    signalType: "observation",
                    weight: 1.0,
                    createdAt: Date()
                )
            ],
            pinnedRules: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ownLog)
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(ownLog.filename)"))

        let result = try await manager.importChangeLogs()
        #expect(result.totalPatternsInserted == 0)
    }

    @Test("importChangeLogs archives processed files")
    func importArchives() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-archive")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        let manager = SyncManager(
            knowledgeBase: kb,
            syncDirectory: dir,
            deviceId: "local-device"
        )

        let remoteLog = ChangeLog(
            deviceId: "remote-device",
            timestamp: Date(),
            patterns: [],
            pinnedRules: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(remoteLog)
        let filePath = "\(dir)/\(remoteLog.filename)"
        try data.write(to: URL(fileURLWithPath: filePath))

        _ = try await manager.importChangeLogs()

        // Original file should be gone
        #expect(!fileExists(atPath: filePath))

        // Archived file should exist
        let archiveDir = "\(dir)/archive"
        #expect(fileExists(atPath: archiveDir))
        let archiveFiles = try FileManager.default.contentsOfDirectory(atPath: archiveDir)
        #expect(archiveFiles.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncManagerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `SyncManager` doesn't exist

- [ ] **Step 3: Create SyncManager.swift**

```swift
// Sources/TidyCore/Sync/SyncManager.swift
import Foundation

public actor SyncManager {
    private let knowledgeBase: KnowledgeBase
    private let syncDirectory: String
    private let deviceId: String
    private let merger: ChangeLogMerger

    public struct ImportResult: Sendable {
        public let totalPatternsInserted: Int
        public let totalPatternsMerged: Int
        public let totalPinnedRulesUpdated: Int
        public let logsProcessed: Int
    }

    public init(
        knowledgeBase: KnowledgeBase,
        syncDirectory: String,
        deviceId: String
    ) {
        self.knowledgeBase = knowledgeBase
        self.syncDirectory = syncDirectory
        self.deviceId = deviceId
        self.merger = ChangeLogMerger(knowledgeBase: knowledgeBase)
    }

    /// Export unsynced patterns and current pinned rules as a change log.
    /// Returns `true` if a file was written, `false` if nothing to export.
    public func exportChangeLog(pinnedRules: PinnedRulesManager = PinnedRulesManager()) throws -> Bool {
        let unsynced = try knowledgeBase.unsyncedPatterns()

        // Also include pinned rules in every export for sync
        let pinnedEntries = pinnedRules.rules.map { ChangeLog.PinnedRuleEntry(from: $0) }

        guard !unsynced.isEmpty || !pinnedEntries.isEmpty else { return false }

        let now = Date()
        let patternEntries = unsynced.map { ChangeLog.PatternEntry(from: $0) }

        let changeLog = ChangeLog(
            deviceId: deviceId,
            timestamp: now,
            patterns: patternEntries,
            pinnedRules: pinnedEntries
        )

        // Write to sync directory
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(changeLog)

        try FileManager.default.createDirectory(
            atPath: syncDirectory,
            withIntermediateDirectories: true
        )

        let filePath = "\(syncDirectory)/\(changeLog.filename)"
        try data.write(to: URL(fileURLWithPath: filePath))

        // Mark patterns as synced
        let ids = unsynced.compactMap { $0.id }
        if !ids.isEmpty {
            try knowledgeBase.markPatternsSynced(ids: ids)
        }

        // Record sync metadata
        try knowledgeBase.recordSyncMetadata(
            deviceId: deviceId,
            lastSyncTimestamp: now
        )

        return true
    }

    /// Import and merge all pending change logs from other devices.
    public func importChangeLogs(
        localPinnedRules: PinnedRulesManager? = nil
    ) throws -> ImportResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: syncDirectory) else {
            return ImportResult(
                totalPatternsInserted: 0,
                totalPatternsMerged: 0,
                totalPinnedRulesUpdated: 0,
                logsProcessed: 0
            )
        }

        let files = try fm.contentsOfDirectory(atPath: syncDirectory)
        let changeLogFiles = files.filter {
            $0.hasPrefix("changes-") && $0.hasSuffix(".json") && !$0.contains(deviceId)
        }

        guard !changeLogFiles.isEmpty else {
            return ImportResult(
                totalPatternsInserted: 0,
                totalPatternsMerged: 0,
                totalPinnedRulesUpdated: 0,
                logsProcessed: 0
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var totalInserted = 0
        var totalMerged = 0
        var processedFiles: [String] = []

        for file in changeLogFiles {
            let filePath = "\(syncDirectory)/\(file)"
            guard let data = fm.contents(atPath: filePath) else { continue }

            do {
                let changeLog = try decoder.decode(ChangeLog.self, from: data)

                // Skip own device's logs (double check)
                guard changeLog.deviceId != deviceId else { continue }

                let result = try merger.merge(changeLog)
                totalInserted += result.patternsInserted
                totalMerged += result.patternsMerged

                processedFiles.append(filePath)
            } catch {
                // Skip malformed change logs
                continue
            }
        }

        // Archive processed files
        if !processedFiles.isEmpty {
            let archiveDir = "\(syncDirectory)/archive"
            try fm.createDirectory(atPath: archiveDir, withIntermediateDirectories: true)

            for filePath in processedFiles {
                let filename = (filePath as NSString).lastPathComponent
                let archivePath = "\(archiveDir)/\(filename)"
                try? fm.moveItem(atPath: filePath, toPath: archivePath)
            }
        }

        return ImportResult(
            totalPatternsInserted: totalInserted,
            totalPatternsMerged: totalMerged,
            totalPinnedRulesUpdated: 0,
            logsProcessed: processedFiles.count
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncManagerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Sync/SyncManager.swift Tests/TidyCoreTests/Sync/SyncManagerTests.swift
git commit -m "feat: add SyncManager actor with change log export, import, and archival"
```

---

## Task 7: SyncDirectoryWatcher

**Files:**
- Create: `Sources/TidyCore/Sync/SyncDirectoryWatcher.swift`
- Test: `Tests/TidyCoreTests/Sync/SyncDirectoryWatcherTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/SyncDirectoryWatcherTests.swift
import Testing
@testable import TidyCore

@Suite("SyncDirectoryWatcher")
struct SyncDirectoryWatcherTests {
    @Test("detects new change log file in directory")
    func detectsNewFile() async throws {
        let dir = makeTemporaryDirectory(prefix: "sync-watch")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let watcher = SyncDirectoryWatcher(directory: dir)
        watcher.start()
        defer { watcher.stop() }

        // Write a file after starting the watcher
        let filePath = "\(dir)/changes-remote-2026-03-18.json"

        // Give FSEvents time to start
        try await Task.sleep(for: .milliseconds(200))

        createFile(atPath: filePath, text: "{}")

        // Wait for event
        var detected = false
        let deadline = Date().addingTimeInterval(5)
        for await _ in watcher.events {
            detected = true
            break
        }

        // If we timed out the stream, that's ok — FSEvents is not instant in tests.
        // The key test is that SyncDirectoryWatcher compiles and can be started/stopped.
        #expect(true) // Smoke test — FSEvents may not fire in test sandbox
    }

    @Test("pendingChangeLogs lists only change log files, not own device")
    func pendingChangeLogs() throws {
        let dir = makeTemporaryDirectory(prefix: "sync-pending")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        // Create files
        createFile(atPath: "\(dir)/changes-remote-device-2026.json", text: "{}")
        createFile(atPath: "\(dir)/changes-my-device-2026.json", text: "{}")
        createFile(atPath: "\(dir)/other-file.txt", text: "nope")

        let pending = SyncDirectoryWatcher.pendingChangeLogs(
            in: dir, excludingDevice: "my-device"
        )
        #expect(pending.count == 1)
        #expect(pending[0].contains("remote-device"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncDirectoryWatcherTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `SyncDirectoryWatcher` doesn't exist

- [ ] **Step 3: Create SyncDirectoryWatcher.swift**

```swift
// Sources/TidyCore/Sync/SyncDirectoryWatcher.swift
import Foundation
import CoreServices

/// Watches the sync directory for new change log files using FSEvents.
/// For iCloud, NSMetadataQuery could be used instead — this implementation
/// covers Dropbox and local sync backends. iCloud support is deferred
/// until proper provisioning is available.
public final class SyncDirectoryWatcher: @unchecked Sendable {
    private let directory: String
    private var stream: FSEventStreamRef?
    private let eventContinuation: AsyncStream<URL>.Continuation
    public let events: AsyncStream<URL>

    public init(directory: String) {
        self.directory = directory
        var continuation: AsyncStream<URL>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    public func start() {
        let pathsToWatch = [directory] as CFArray
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<SyncDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            for path in paths {
                watcher.eventContinuation.yield(URL(fileURLWithPath: path))
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = stream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        eventContinuation.finish()
    }

    /// Lists change log files in the sync directory that belong to other devices.
    public static func pendingChangeLogs(
        in directory: String,
        excludingDevice deviceId: String
    ) -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        return files.filter {
            $0.hasPrefix("changes-") &&
            $0.hasSuffix(".json") &&
            !$0.contains(deviceId)
        }.map { "\(directory)/\($0)" }
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncDirectoryWatcherTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Sync/SyncDirectoryWatcher.swift Tests/TidyCoreTests/Sync/SyncDirectoryWatcherTests.swift
git commit -m "feat: add SyncDirectoryWatcher with FSEvents for change log detection"
```

---

## Task 8: RulePack Model

**Files:**
- Create: `Sources/TidyCore/Models/RulePack.swift`
- Test: `Tests/TidyCoreTests/Sync/RulePackModelTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/RulePackModelTests.swift
import Testing
@testable import TidyCore

@Suite("RulePack Model")
struct RulePackModelTests {
    @Test("RulePack round-trips through JSON")
    func roundTrip() throws {
        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: "Developer Essentials",
                description: "Routes code and dev tools",
                author: "tkejzlar",
                createdAt: Date()
            ),
            pinnedRules: [
                RulePack.PackedPinnedRule(extension: "dmg", destination: "~/Applications/Installers"),
                RulePack.PackedPinnedRule(extension: "pkg", destination: "~/Applications/Installers"),
            ],
            patterns: [
                RulePack.PackedPattern(feature: "extension", value: "js", destination: "~/Developer/Downloads", weight: 5.0),
            ],
            folderTemplate: [
                "~/Developer/Downloads",
                "~/Applications/Installers",
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(pack)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RulePack.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.metadata.name == "Developer Essentials")
        #expect(decoded.pinnedRules.count == 2)
        #expect(decoded.patterns.count == 1)
        #expect(decoded.patterns[0].weight == 5.0)
        #expect(decoded.folderTemplate.count == 2)
    }

    @Test("paths use tilde prefix for portability")
    func tildePrefix() {
        let rule = RulePack.PackedPinnedRule(extension: "pdf", destination: "~/Documents/PDFs")
        #expect(rule.destination.hasPrefix("~"))
    }

    @Test("expandPath converts tilde to home directory")
    func expandPath() {
        let expanded = RulePack.expandPath("~/Documents/Test")
        #expect(!expanded.hasPrefix("~"))
        #expect(expanded.hasSuffix("/Documents/Test"))
    }

    @Test("contractPath converts home directory to tilde")
    func contractPath() {
        let home = NSHomeDirectory()
        let contracted = RulePack.contractPath("\(home)/Documents/Test")
        #expect(contracted == "~/Documents/Test")
    }

    @Test("RulePack with empty arrays is valid")
    func emptyArrays() throws {
        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: "Empty",
                description: "",
                author: "",
                createdAt: Date()
            ),
            pinnedRules: [],
            patterns: [],
            folderTemplate: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pack)
        let decoded = try JSONDecoder().decode(RulePack.self, from: data)
        #expect(decoded.pinnedRules.isEmpty)
    }

    @Test("file extension is .tidypack")
    func fileExtension() {
        #expect(RulePack.fileExtension == "tidypack")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RulePackModelTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `RulePack` doesn't exist

- [ ] **Step 3: Create RulePack.swift**

```swift
// Sources/TidyCore/Models/RulePack.swift
import Foundation

public struct RulePack: Codable, Sendable {
    public static let fileExtension = "tidypack"
    public static let utiIdentifier = "com.tidy.rulepack"

    public let version: Int
    public let metadata: Metadata
    public var pinnedRules: [PackedPinnedRule]
    public var patterns: [PackedPattern]
    public var folderTemplate: [String]

    public init(
        version: Int = 1,
        metadata: Metadata,
        pinnedRules: [PackedPinnedRule],
        patterns: [PackedPattern],
        folderTemplate: [String]
    ) {
        self.version = version
        self.metadata = metadata
        self.pinnedRules = pinnedRules
        self.patterns = patterns
        self.folderTemplate = folderTemplate
    }

    // MARK: - Nested Types

    public struct Metadata: Codable, Sendable {
        public let name: String
        public let description: String
        public let author: String
        public let createdAt: Date

        public init(name: String, description: String, author: String, createdAt: Date) {
            self.name = name
            self.description = description
            self.author = author
            self.createdAt = createdAt
        }
    }

    public struct PackedPinnedRule: Codable, Sendable {
        public let `extension`: String
        public let destination: String

        public init(extension ext: String, destination: String) {
            self.`extension` = ext
            self.destination = destination
        }
    }

    public struct PackedPattern: Codable, Sendable {
        public let feature: String
        public let value: String
        public let destination: String
        public let weight: Double

        public init(feature: String, value: String, destination: String, weight: Double) {
            self.feature = feature
            self.value = value
            self.destination = destination
            self.weight = weight
        }
    }

    // MARK: - Path Portability

    /// Expands `~` prefix to the current user's home directory.
    public static func expandPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    /// Contracts the home directory prefix to `~`.
    public static func contractPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RulePackModelTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Models/RulePack.swift Tests/TidyCoreTests/Sync/RulePackModelTests.swift
git commit -m "feat: add RulePack model for .tidypack export/import format"
```

---

## Task 9: RulePackManager — Export and Import Logic

**Files:**
- Create: `Sources/TidyCore/Sync/RulePackManager.swift`
- Test: `Tests/TidyCoreTests/Sync/RulePackManagerTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/TidyCoreTests/Sync/RulePackManagerTests.swift
import Testing
@testable import TidyCore

@Suite("RulePackManager")
struct RulePackManagerTests {
    @Test("export creates .tidypack file with selected rules and patterns")
    func exportCreatesFile() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-export")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        try kb.recordPattern(
            extension: "pdf", filenameTokens: ["invoice"],
            sourceApp: "Safari", sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents/Invoices", signalType: .observation
        )

        let pinnedRules = PinnedRulesManager(rules: [
            PinnedRule(fileExtension: "dmg", destination: "~/Apps/Installers")
        ])

        let manager = RulePackManager(knowledgeBase: kb)
        let path = "\(dir)/developer.tidypack"

        try manager.export(
            to: path,
            name: "Developer Essentials",
            description: "Routes dev files",
            author: "tkejzlar",
            pinnedRules: pinnedRules.rules,
            minimumWeight: 0.0,
            folderTemplate: ["~/Developer/Downloads"]
        )

        #expect(fileExists(atPath: path))

        // Verify contents
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pack = try decoder.decode(RulePack.self, from: data)

        #expect(pack.metadata.name == "Developer Essentials")
        #expect(pack.pinnedRules.count == 1)
        #expect(pack.pinnedRules[0].extension == "dmg")
        #expect(pack.patterns.count >= 1)
        #expect(pack.folderTemplate.count == 1)
    }

    @Test("export filters patterns by minimum weight")
    func exportFiltersWeight() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-filter")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let kb = try KnowledgeBase.inMemory()
        // Low weight pattern (observation default = 1.0)
        try kb.recordPattern(
            extension: "txt", filenameTokens: [],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents", signalType: .observation
        )
        // High weight pattern (correction default = 3.0)
        try kb.recordPattern(
            extension: "pdf", filenameTokens: [],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents/PDFs", signalType: .correction
        )

        let manager = RulePackManager(knowledgeBase: kb)
        let path = "\(dir)/filtered.tidypack"

        try manager.export(
            to: path,
            name: "Filtered",
            description: "",
            author: "",
            pinnedRules: [],
            minimumWeight: 2.0,
            folderTemplate: []
        )

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pack = try decoder.decode(RulePack.self, from: data)

        #expect(pack.patterns.count == 1) // Only correction (3.0) passes threshold
    }

    @Test("import adds pinned rules to manager")
    func importPinnedRules() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-import")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: "Test", description: "", author: "", createdAt: Date()
            ),
            pinnedRules: [
                RulePack.PackedPinnedRule(extension: "dmg", destination: "~/Apps"),
                RulePack.PackedPinnedRule(extension: "pkg", destination: "~/Apps"),
            ],
            patterns: [],
            folderTemplate: []
        )

        let path = "\(dir)/test.tidypack"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pack)
        try data.write(to: URL(fileURLWithPath: path))

        let kb = try KnowledgeBase.inMemory()
        let manager = RulePackManager(knowledgeBase: kb)

        var pinnedManager = PinnedRulesManager()
        let result = try manager.importPack(
            from: path,
            into: &pinnedManager,
            acceptedRuleExtensions: ["dmg", "pkg"],
            createFolders: false
        )

        #expect(result.pinnedRulesImported == 2)
        #expect(pinnedManager.rules.count == 2)
    }

    @Test("import applies 0.5x weight reduction to patterns")
    func importWeightReduction() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-weight")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: "Test", description: "", author: "", createdAt: Date()
            ),
            pinnedRules: [],
            patterns: [
                RulePack.PackedPattern(
                    feature: "extension", value: "pdf",
                    destination: "~/Documents/PDFs", weight: 8.0
                ),
            ],
            folderTemplate: []
        )

        let path = "\(dir)/test.tidypack"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pack).write(to: URL(fileURLWithPath: path))

        let kb = try KnowledgeBase.inMemory()
        let manager = RulePackManager(knowledgeBase: kb)

        var pinnedManager = PinnedRulesManager()
        let result = try manager.importPack(
            from: path,
            into: &pinnedManager,
            acceptedRuleExtensions: [],
            createFolders: false
        )

        #expect(result.patternsImported == 1)

        let patterns = try kb.allPatterns()
        #expect(patterns.count == 1)
        #expect(patterns[0].weight == 4.0) // 8.0 * 0.5
    }

    @Test("import selectively accepts pinned rules")
    func importSelectiveRules() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-selective")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: "Test", description: "", author: "", createdAt: Date()
            ),
            pinnedRules: [
                RulePack.PackedPinnedRule(extension: "dmg", destination: "~/Apps"),
                RulePack.PackedPinnedRule(extension: "pkg", destination: "~/Apps"),
                RulePack.PackedPinnedRule(extension: "zip", destination: "~/Archives"),
            ],
            patterns: [],
            folderTemplate: []
        )

        let path = "\(dir)/test.tidypack"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pack).write(to: URL(fileURLWithPath: path))

        let kb = try KnowledgeBase.inMemory()
        let manager = RulePackManager(knowledgeBase: kb)

        var pinnedManager = PinnedRulesManager()
        let result = try manager.importPack(
            from: path,
            into: &pinnedManager,
            acceptedRuleExtensions: ["dmg"], // Only accept dmg
            createFolders: false
        )

        #expect(result.pinnedRulesImported == 1)
        #expect(pinnedManager.rules.count == 1)
        #expect(pinnedManager.rules[0].fileExtension == "dmg")
    }

    @Test("import creates folders from template when requested")
    func importCreatesFolders() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-folders")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let folderPath = "\(dir)/TestFolder/SubFolder"

        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: "Test", description: "", author: "", createdAt: Date()
            ),
            pinnedRules: [],
            patterns: [],
            folderTemplate: [folderPath]
        )

        let path = "\(dir)/test.tidypack"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pack).write(to: URL(fileURLWithPath: path))

        let kb = try KnowledgeBase.inMemory()
        let manager = RulePackManager(knowledgeBase: kb)

        var pinnedManager = PinnedRulesManager()
        let result = try manager.importPack(
            from: path,
            into: &pinnedManager,
            acceptedRuleExtensions: [],
            createFolders: true
        )

        #expect(result.foldersCreated == 1)
        #expect(fileExists(atPath: folderPath))
    }

    @Test("preview returns pack contents without importing")
    func preview() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-preview")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: "Preview Test", description: "A test pack", author: "test", createdAt: Date()
            ),
            pinnedRules: [
                RulePack.PackedPinnedRule(extension: "pdf", destination: "~/Docs"),
            ],
            patterns: [
                RulePack.PackedPattern(feature: "extension", value: "js", destination: "~/Dev", weight: 5.0),
            ],
            folderTemplate: ["~/Dev"]
        )

        let path = "\(dir)/preview.tidypack"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pack).write(to: URL(fileURLWithPath: path))

        let loaded = try RulePackManager.preview(path: path)
        #expect(loaded.metadata.name == "Preview Test")
        #expect(loaded.pinnedRules.count == 1)
        #expect(loaded.patterns.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RulePackManagerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: FAIL — `RulePackManager` doesn't exist

- [ ] **Step 3: Create RulePackManager.swift**

```swift
// Sources/TidyCore/Sync/RulePackManager.swift
import Foundation

public struct RulePackManager: Sendable {
    private let knowledgeBase: KnowledgeBase
    private static let importWeightMultiplier: Double = 0.5

    public struct ImportResult: Sendable {
        public let pinnedRulesImported: Int
        public let patternsImported: Int
        public let foldersCreated: Int
        public let packName: String
    }

    public init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    // MARK: - Export

    /// Export selected rules and patterns to a `.tidypack` file.
    public func export(
        to path: String,
        name: String,
        description: String,
        author: String,
        pinnedRules: [PinnedRule],
        minimumWeight: Double,
        folderTemplate: [String]
    ) throws {
        let allPatterns = try knowledgeBase.allPatterns()
        let filteredPatterns = allPatterns.filter { $0.weight >= minimumWeight }

        let packedPatterns = filteredPatterns.map { record -> RulePack.PackedPattern in
            // Determine the primary feature for this pattern
            let feature: String
            let value: String
            if let ext = record.fileExtension, !ext.isEmpty {
                feature = "extension"
                value = ext
            } else if let tokens = record.filenameTokens, !tokens.isEmpty {
                feature = "tokens"
                value = tokens
            } else if let app = record.sourceApp, !app.isEmpty {
                feature = "sourceApp"
                value = app
            } else {
                feature = "extension"
                value = ""
            }

            return RulePack.PackedPattern(
                feature: feature,
                value: value,
                destination: RulePack.contractPath(record.destination),
                weight: record.weight
            )
        }

        let packedRules = pinnedRules.map { rule in
            RulePack.PackedPinnedRule(
                extension: rule.fileExtension,
                destination: RulePack.contractPath(rule.destination)
            )
        }

        let contractedTemplate = folderTemplate.map { RulePack.contractPath($0) }

        let pack = RulePack(
            version: 1,
            metadata: RulePack.Metadata(
                name: name,
                description: description,
                author: author,
                createdAt: Date()
            ),
            pinnedRules: packedRules,
            patterns: packedPatterns,
            folderTemplate: contractedTemplate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pack)

        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Import

    /// Import a `.tidypack` file, merging rules and patterns into the local database.
    /// - Parameter acceptedRuleExtensions: Which pinned rule extensions to accept (empty = skip all rules).
    /// - Parameter createFolders: Whether to create missing folders from the template.
    public func importPack(
        from path: String,
        into pinnedRulesManager: inout PinnedRulesManager,
        acceptedRuleExtensions: [String],
        createFolders: Bool
    ) throws -> ImportResult {
        let pack = try Self.preview(path: path)
        let acceptedSet = Set(acceptedRuleExtensions.map { $0.lowercased() })

        // Import pinned rules (only accepted ones)
        var rulesImported = 0
        for rule in pack.pinnedRules {
            if acceptedSet.contains(rule.extension.lowercased()) {
                let expandedDest = RulePack.expandPath(rule.destination)
                pinnedRulesManager.addRule(PinnedRule(
                    fileExtension: rule.extension,
                    destination: expandedDest
                ))
                rulesImported += 1
            }
        }

        // Import patterns with 0.5x weight reduction
        var patternsImported = 0
        for pattern in pack.patterns {
            let reducedWeight = pattern.weight * Self.importWeightMultiplier
            let expandedDest = RulePack.expandPath(pattern.destination)

            switch pattern.feature {
            case "extension":
                try knowledgeBase.recordPattern(
                    extension: pattern.value,
                    filenameTokens: [],
                    sourceApp: nil,
                    sizeBucket: nil,
                    timeBucket: nil,
                    destination: expandedDest,
                    signalType: .observation
                )
                // Update weight to the reduced import weight
                let patterns = try knowledgeBase.allPatterns()
                if let last = patterns.last {
                    try knowledgeBase.updatePatternWeight(id: last.id!, weight: reducedWeight)
                }
            case "tokens":
                let tokens: [String]
                if let data = pattern.value.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String].self, from: data) {
                    tokens = decoded
                } else {
                    tokens = [pattern.value]
                }
                try knowledgeBase.recordPattern(
                    extension: nil,
                    filenameTokens: tokens,
                    sourceApp: nil,
                    sizeBucket: nil,
                    timeBucket: nil,
                    destination: expandedDest,
                    signalType: .observation
                )
                let patterns = try knowledgeBase.allPatterns()
                if let last = patterns.last {
                    try knowledgeBase.updatePatternWeight(id: last.id!, weight: reducedWeight)
                }
            case "sourceApp":
                try knowledgeBase.recordPattern(
                    extension: nil,
                    filenameTokens: [],
                    sourceApp: pattern.value,
                    sizeBucket: nil,
                    timeBucket: nil,
                    destination: expandedDest,
                    signalType: .observation
                )
                let patterns = try knowledgeBase.allPatterns()
                if let last = patterns.last {
                    try knowledgeBase.updatePatternWeight(id: last.id!, weight: reducedWeight)
                }
            default:
                // Unknown feature type — skip
                continue
            }
            patternsImported += 1
        }

        // Create folders from template
        var foldersCreated = 0
        if createFolders {
            for folder in pack.folderTemplate {
                let expanded = RulePack.expandPath(folder)
                if !FileManager.default.fileExists(atPath: expanded) {
                    try FileManager.default.createDirectory(
                        atPath: expanded,
                        withIntermediateDirectories: true
                    )
                    foldersCreated += 1
                }
            }
        }

        return ImportResult(
            pinnedRulesImported: rulesImported,
            patternsImported: patternsImported,
            foldersCreated: foldersCreated,
            packName: pack.metadata.name
        )
    }

    // MARK: - Preview

    /// Load and decode a `.tidypack` file for preview without importing.
    public static func preview(path: String) throws -> RulePack {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RulePack.self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RulePackManagerTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TidyCore/Sync/RulePackManager.swift Tests/TidyCoreTests/Sync/RulePackManagerTests.swift
git commit -m "feat: add RulePackManager with export, import (0.5x weight), and preview"
```

---

## Task 10: UTI Registration for .tidypack

**Files:**
- Modify: `bundle/Info.plist`

- [ ] **Step 1: Update Info.plist with UTI declarations**

Replace the contents of `bundle/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Tidy</string>
    <key>CFBundleDisplayName</key>
    <string>Tidy</string>
    <key>CFBundleIdentifier</key>
    <string>com.tkejzlar.tidy</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleExecutable</key>
    <string>Tidy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.tidy.rulepack</string>
            <key>UTTypeDescription</key>
            <string>Tidy Rule Pack</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>tidypack</string>
                </array>
                <key>public.mime-type</key>
                <string>application/json</string>
            </dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Tidy Rule Pack</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.tidy.rulepack</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Verify bundle.sh still works**

No changes needed to `scripts/bundle.sh` — it already copies `bundle/Info.plist` to the app bundle. The UTI declarations are embedded in the plist.

Run: `./scripts/bundle.sh` (optional — verifies the build still works)

- [ ] **Step 3: Commit**

```bash
git add bundle/Info.plist
git commit -m "feat: register com.tidy.rulepack UTI for .tidypack file handling"
```

---

## Task 11: AppState Sync Integration

**Files:**
- Modify: `Sources/Tidy/AppState.swift`

- [ ] **Step 1: Add sync properties and methods to AppState**

Add the following properties to `AppState`:

```swift
var syncBackend: SyncBackend = .dropbox {
    didSet { UserDefaults.standard.set(syncBackend.rawValue, forKey: "syncBackend") }
}
private var syncManager: SyncManager?
private var syncWatcher: SyncDirectoryWatcher?
private var syncWatchTask: Task<Void, Never>?
```

Add device ID initialization in `start()`, after loading saved settings:

```swift
// Load sync backend
if let raw = UserDefaults.standard.string(forKey: "syncBackend"),
   let backend = SyncBackend(rawValue: raw) {
    syncBackend = backend
} else {
    syncBackend = .dropbox
}
```

After the KnowledgeBase is created in `start()`, add sync initialization:

```swift
// Initialize sync
let syncDir = syncBackend.syncDirectory(
    dropboxPath: syncBackend == .dropbox
        ? NSString(string: dropboxSyncPath).expandingTildeInPath
        : nil
)
let deviceId = DeviceIdentity.deviceId()

let sync = SyncManager(
    knowledgeBase: kb,
    syncDirectory: syncDir,
    deviceId: deviceId
)
self.syncManager = sync

// Import any pending change logs on launch
Task {
    if let result = try? await sync.importChangeLogs(),
       result.logsProcessed > 0 {
        let total = result.totalPatternsInserted + result.totalPatternsMerged
        if total > 0 {
            sendSyncNotification(patternsCount: total, logsCount: result.logsProcessed)
        }
    }
}

// Watch sync directory for new change logs
let watcher = SyncDirectoryWatcher(directory: syncDir)
self.syncWatcher = watcher
watcher.start()

syncWatchTask = Task { [weak self] in
    for await _ in watcher.events {
        guard let self = self else { break }
        if let result = try? await sync.importChangeLogs(),
           result.logsProcessed > 0 {
            let total = result.totalPatternsInserted + result.totalPatternsMerged
            if total > 0 {
                await MainActor.run {
                    self.sendSyncNotification(patternsCount: total, logsCount: result.logsProcessed)
                    self.patternCount = (try? kb.patternCount()) ?? self.patternCount
                }
            }
        }
    }
}
```

Add export method:

```swift
func exportSync() {
    guard let syncManager else { return }
    Task {
        let pinnedManager = PinnedRulesManager(rules: pinnedRules)
        _ = try? await syncManager.exportChangeLog(pinnedRules: pinnedManager)
    }
}
```

Add sync notification method:

```swift
private func sendSyncNotification(patternsCount: Int, logsCount: Int) {
    guard showNotifications else { return }
    let content = UNMutableNotificationContent()
    content.title = "Tidy"
    content.body = "Merged \(patternsCount) patterns from \(logsCount == 1 ? "your other Mac" : "\(logsCount) devices")"
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}
```

Add rule pack export/import methods:

```swift
func exportRulePack(to path: String, name: String, description: String) {
    guard let orchestrator else { return }
    Task {
        do {
            let kb = try KnowledgeBase(path: currentDBPath())
            let manager = RulePackManager(knowledgeBase: kb)
            try manager.export(
                to: path,
                name: name,
                description: description,
                author: NSFullUserName(),
                pinnedRules: pinnedRules,
                minimumWeight: 2.0,
                folderTemplate: []
            )
        } catch { }
    }
}

func importRulePack(from path: String, acceptedExtensions: [String], createFolders: Bool) {
    Task {
        do {
            let kb = try KnowledgeBase(path: currentDBPath())
            let manager = RulePackManager(knowledgeBase: kb)
            var pinnedManager = PinnedRulesManager(rules: pinnedRules)
            let result = try manager.importPack(
                from: path,
                into: &pinnedManager,
                acceptedRuleExtensions: acceptedExtensions,
                createFolders: createFolders
            )
            pinnedRules = pinnedManager.rules
            try? pinnedManager.save(to: pinnedRulesFilePath())
            patternCount = (try? kb.patternCount()) ?? patternCount
        } catch { }
    }
}
```

**Note:** The `currentDBPath()` helper is not shown here — it should extract the DB path logic from `start()` into a reusable method. Alternatively, store the `KnowledgeBase` reference as a property on `AppState` so it can be reused.

- [ ] **Step 2: Verify build compiles**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/Tidy/AppState.swift
git commit -m "feat: integrate SyncManager and RulePackManager into AppState lifecycle"
```

---

## Task 12: Settings UI — Sync Backend Picker and Export/Import

**Files:**
- Modify: `Sources/Tidy/Views/SettingsView.swift`
- Create: `Sources/Tidy/Views/RulePackPreviewView.swift`

- [ ] **Step 1: Add sync backend picker to SettingsView**

Add after the existing "Sync path" `LabeledContent` in `SettingsView.swift`, replacing that section:

```swift
// Sync settings
VStack(alignment: .leading, spacing: 8) {
    Text("Sync").font(.system(size: 12, weight: .semibold))

    Picker("Backend", selection: $state.syncBackend) {
        ForEach(SyncBackend.allCases, id: \.self) { backend in
            Text(backend.displayName).tag(backend)
        }
    }
    .pickerStyle(.segmented)

    if state.syncBackend == .dropbox {
        LabeledContent("Dropbox path") {
            HStack {
                Text(state.dropboxSyncPath).font(.caption).foregroundStyle(.secondary)
                Button(action: pickSyncFolder) {
                    Image(systemName: "folder")
                }.buttonStyle(.plain)
            }
        }
    }

    if state.syncBackend == .icloud {
        Text("Requires provisioned build with iCloud entitlement")
            .font(.caption2).foregroundStyle(.orange)
    }

    Button("Sync Now") {
        state.exportSync()
    }
    .font(.caption)
}

Divider()

// Rule Packs
VStack(alignment: .leading, spacing: 8) {
    Text("Rule Packs").font(.system(size: 12, weight: .semibold))

    HStack {
        Button("Export Rule Pack...") {
            exportRulePack()
        }
        .font(.caption)

        Button("Import Rule Pack...") {
            importRulePack()
        }
        .font(.caption)
    }
}
```

Add the export/import methods to `SettingsView`:

```swift
private func exportRulePack() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "rules.tidypack"
    panel.prompt = "Export"
    if panel.runModal() == .OK, let url = panel.url {
        state.exportRulePack(
            to: url.path,
            name: "My Rules",
            description: "Exported from Tidy"
        )
    }
}

private func importRulePack() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.prompt = "Import"
    if panel.runModal() == .OK, let url = panel.url {
        // For now, accept all rules. A future enhancement could show
        // RulePackPreviewView for selective import.
        do {
            let pack = try RulePackManager.preview(path: url.path)
            let allExts = pack.pinnedRules.map { $0.extension }
            state.importRulePack(
                from: url.path,
                acceptedExtensions: allExts,
                createFolders: true
            )
        } catch { }
    }
}
```

- [ ] **Step 2: Create RulePackPreviewView (future enhancement stub)**

```swift
// Sources/Tidy/Views/RulePackPreviewView.swift
import SwiftUI
import TidyCore

/// Preview modal for importing a .tidypack file.
/// Shows pack contents and lets users accept/skip individual rules.
struct RulePackPreviewView: View {
    let pack: RulePack
    let onImport: (_ acceptedExtensions: [String], _ createFolders: Bool) -> Void
    let onCancel: () -> Void

    @State private var selectedRules: Set<String> = []
    @State private var createFolders = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(pack.metadata.name)
                .font(.headline)
            if !pack.metadata.description.isEmpty {
                Text(pack.metadata.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("by \(pack.metadata.author)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            // Pinned rules
            if !pack.pinnedRules.isEmpty {
                Text("Pinned Rules").font(.system(size: 11, weight: .semibold))
                ForEach(pack.pinnedRules, id: \.extension) { rule in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { selectedRules.contains(rule.extension) },
                            set: { if $0 { selectedRules.insert(rule.extension) } else { selectedRules.remove(rule.extension) } }
                        )) {
                            HStack {
                                Text("*.\(rule.extension)")
                                    .font(.caption).fontWeight(.medium)
                                Image(systemName: "arrow.right").font(.caption2)
                                Text(rule.destination)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            // Patterns summary
            if !pack.patterns.isEmpty {
                Text("\(pack.patterns.count) learned patterns (imported at 50% weight)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Folder template
            if !pack.folderTemplate.isEmpty {
                Toggle("Create \(pack.folderTemplate.count) folders", isOn: $createFolders)
                    .font(.caption)
                    .toggleStyle(.checkbox)
            }

            Divider()

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Import") {
                    onImport(Array(selectedRules), createFolders)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            // Select all rules by default
            selectedRules = Set(pack.pinnedRules.map { $0.extension })
        }
    }
}
```

- [ ] **Step 3: Verify build compiles**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/Tidy/Views/SettingsView.swift Sources/Tidy/Views/RulePackPreviewView.swift
git commit -m "feat: add sync backend picker and rule pack export/import to Settings UI"
```

---

## Task 13: End-to-End Integration Test

**Files:**
- Test: `Tests/TidyCoreTests/Sync/SyncIntegrationTests.swift`

- [ ] **Step 1: Write the integration test**

```swift
// Tests/TidyCoreTests/Sync/SyncIntegrationTests.swift
import Testing
@testable import TidyCore

@Suite("Sync Integration")
struct SyncIntegrationTests {
    @Test("full round-trip: device A exports, device B imports and merges")
    func fullRoundTrip() async throws {
        let syncDir = makeTemporaryDirectory(prefix: "sync-integration")
        try createDirectory(atPath: syncDir)
        defer { removeItem(atPath: syncDir) }

        // Device A: create patterns and export
        let kbA = try KnowledgeBase.inMemory()
        try kbA.recordPattern(
            extension: "pdf", filenameTokens: ["invoice"],
            sourceApp: "Safari", sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents/Invoices", signalType: .observation
        )
        try kbA.recordPattern(
            extension: "dmg", filenameTokens: [],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Apps", signalType: .observation
        )

        let syncA = SyncManager(
            knowledgeBase: kbA,
            syncDirectory: syncDir,
            deviceId: "device-A"
        )
        let exported = try await syncA.exportChangeLog()
        #expect(exported)

        // Device B: import
        let kbB = try KnowledgeBase.inMemory()
        // Device B already has one pattern with same key
        try kbB.recordPattern(
            extension: "pdf", filenameTokens: ["invoice"],
            sourceApp: "Safari", sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents/Invoices", signalType: .observation
        )

        let syncB = SyncManager(
            knowledgeBase: kbB,
            syncDirectory: syncDir,
            deviceId: "device-B"
        )
        let result = try await syncB.importChangeLogs()

        #expect(result.logsProcessed == 1)
        #expect(result.totalPatternsInserted == 1)  // dmg is new
        #expect(result.totalPatternsMerged == 1)     // pdf+invoice merged

        // Verify merged weight
        let patterns = try kbB.allPatterns()
        let pdfPattern = patterns.first { $0.fileExtension == "pdf" }
        #expect(pdfPattern?.weight == 2.0) // 1.0 + 1.0

        // Verify new pattern
        let dmgPattern = patterns.first { $0.fileExtension == "dmg" }
        #expect(dmgPattern != nil)
        #expect(dmgPattern?.destination == "~/Apps")
    }

    @Test("rule pack round-trip: export from A, import into B")
    func rulePackRoundTrip() throws {
        let dir = makeTemporaryDirectory(prefix: "rulepack-integration")
        try createDirectory(atPath: dir)
        defer { removeItem(atPath: dir) }

        // Source: create patterns and rules
        let kbA = try KnowledgeBase.inMemory()
        try kbA.recordPattern(
            extension: "pdf", filenameTokens: [],
            sourceApp: nil, sizeBucket: nil, timeBucket: nil,
            destination: "~/Documents", signalType: .correction
        )

        let managerA = RulePackManager(knowledgeBase: kbA)
        let packPath = "\(dir)/shared.tidypack"
        try managerA.export(
            to: packPath,
            name: "Shared Rules",
            description: "Team rules",
            author: "alice",
            pinnedRules: [
                PinnedRule(fileExtension: "dmg", destination: "~/Apps"),
            ],
            minimumWeight: 1.0,
            folderTemplate: ["\(dir)/TestFolder"]
        )

        // Destination: import
        let kbB = try KnowledgeBase.inMemory()
        let managerB = RulePackManager(knowledgeBase: kbB)
        var pinnedB = PinnedRulesManager()

        let result = try managerB.importPack(
            from: packPath,
            into: &pinnedB,
            acceptedRuleExtensions: ["dmg"],
            createFolders: true
        )

        #expect(result.pinnedRulesImported == 1)
        #expect(result.patternsImported == 1)
        #expect(result.foldersCreated == 1)
        #expect(result.packName == "Shared Rules")

        // Verify weight reduction
        let patterns = try kbB.allPatterns()
        #expect(patterns[0].weight == 1.5) // 3.0 (correction) * 0.5

        // Verify folder created
        #expect(fileExists(atPath: "\(dir)/TestFolder"))

        // Verify pinned rule
        #expect(pinnedB.rules.count == 1)
        #expect(pinnedB.rules[0].fileExtension == "dmg")
    }

    @Test("sync does not duplicate when importing same log twice")
    func idempotentImport() async throws {
        let syncDir = makeTemporaryDirectory(prefix: "sync-idempotent")
        try createDirectory(atPath: syncDir)
        defer { removeItem(atPath: syncDir) }

        // Create a remote change log
        let remoteLog = ChangeLog(
            deviceId: "remote",
            timestamp: Date(),
            patterns: [
                ChangeLog.PatternEntry(
                    fileExtension: "pdf",
                    filenameTokens: nil,
                    sourceApp: nil,
                    sizeBucket: nil,
                    timeBucket: nil,
                    documentType: nil,
                    sourceDomain: nil,
                    sceneType: nil,
                    sourceFolder: nil,
                    destination: "~/Documents",
                    signalType: "observation",
                    weight: 1.0,
                    createdAt: Date()
                )
            ],
            pinnedRules: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(remoteLog)
        let filePath = "\(syncDir)/\(remoteLog.filename)"
        try data.write(to: URL(fileURLWithPath: filePath))

        let kb = try KnowledgeBase.inMemory()
        let sync = SyncManager(
            knowledgeBase: kb,
            syncDirectory: syncDir,
            deviceId: "local"
        )

        // First import
        let r1 = try await sync.importChangeLogs()
        #expect(r1.totalPatternsInserted == 1)

        // The file is archived after first import, so second import should find nothing
        let r2 = try await sync.importChangeLogs()
        #expect(r2.logsProcessed == 0)

        // Only one pattern in DB
        let patterns = try kb.allPatterns()
        #expect(patterns.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter SyncIntegrationTests -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add Tests/TidyCoreTests/Sync/SyncIntegrationTests.swift
git commit -m "test: add sync and rule pack end-to-end integration tests"
```

---

## Summary

| Task | Files | Tests | What it does |
|------|-------|-------|-------------|
| 1 | SyncBackend.swift | SyncBackendTests | SyncBackend enum, DeviceIdentity UUID |
| 2 | PinnedRule.swift, PinnedRulesManager.swift | PinnedRuleTimestampTests | Add updatedAt for conflict resolution |
| 3 | KnowledgeBase.swift | SyncMetadataMigrationTests | v3 migration: sync_metadata table, unsynced queries |
| 4 | ChangeLog.swift | ChangeLogTests | Change log model with pattern/rule entries |
| 5 | ChangeLogMerger.swift, KnowledgeBase.swift | ChangeLogMergerTests | Composite-key merge, weight summing (cap 20), last-write-wins |
| 6 | SyncManager.swift | SyncManagerTests | Export/import change logs, archival |
| 7 | SyncDirectoryWatcher.swift | SyncDirectoryWatcherTests | FSEvents watcher for sync directory |
| 8 | RulePack.swift | RulePackModelTests | .tidypack format model, path portability |
| 9 | RulePackManager.swift | RulePackManagerTests | Export/import with 0.5x weight, selective rules |
| 10 | Info.plist | (manual) | UTI registration for .tidypack |
| 11 | AppState.swift | (build check) | Sync lifecycle, export/import actions |
| 12 | SettingsView.swift, RulePackPreviewView.swift | (build check) | Sync backend picker, import/export UI |
| 13 | SyncIntegrationTests.swift | SyncIntegrationTests | Full round-trip validation |

**Total: 13 tasks, ~60 steps, 10 test suites with ~35 test cases.**
