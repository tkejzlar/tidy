# Tidy v2 — Design Spec

## Overview

Tidy v2 evolves from a Downloads-only file organizer into a full-system file intelligence platform. Three major capability areas ship together as a cohesive release:

1. **Content Intelligence Pipeline** — deep file understanding (text, images, download context)
2. **Multi-Folder Watching & Bulk Cleanup** — watch any folder, clean up existing messes
3. **Sync & Rule Packs** — cross-device sync via iCloud/Dropbox, shareable rule bundles

**Approach:** Intelligence-first. Content intelligence is the foundation — it makes bulk cleanup produce better results, multi-folder watching more useful, and exported rule packs more valuable.

**Architecture philosophy:** The existing three-layer scoring engine stays intact. V2 enriches its inputs (richer file context) and expands its scope (more folders, batch mode, sync). No architectural rewrites — additive enhancement.

---

## 1. Content Intelligence Pipeline

### Purpose

Today `FileCandidate` carries filename tokens, extension, size/time buckets, and basic Spotlight metadata. The content pipeline enriches this with deep file understanding before scoring.

### New Component: `ContentIntelligencePipeline`

A staged pipeline that runs after `FileCandidate` creation but before scoring. Produces an `EnrichedFileContext` struct that wraps `FileCandidate` with additional signals.

### Stage 1: Text Extraction (expand existing `ContentExtractor`)

**Currently supported:** PDF (via PDFKit), TXT, MD, CSV — first ~500 words.

**New formats:**
- `.docx` / `.xlsx` / `.pptx` — Office Open XML (zip + XML parsing, extract text from `word/document.xml` etc.)
- `.rtf` — via `NSAttributedString(rtf:documentAttributes:)`
- `.eml` — parse MIME headers + body text

**Budget:** ~500 words, same as today. Cheap to run, always executed when the file type is supported.

### Stage 2: Image Analysis (new `ImageAnalyzer`)

Uses Apple's Vision framework (`import Vision`), available since macOS 10.13:

- **Scene classification** via `VNClassifyImageRequest` — produces `VNClassificationObservation` labels from Apple's taxonomy. Map to `SceneType` using a lookup table (see SceneType Mapping below).
- **OCR** via `VNRecognizeTextRequest` — extract text from scanned documents and screenshots. When Stage 1 returns nil (e.g., scanned PDF with no selectable text), OCR text is promoted to `extractedText` on `EnrichedFileContext`.
- **Face detection** via `VNDetectFaceRectanglesRequest` — presence of faces is a signal (photo with faces → "Photos", not "Work Assets")
- **EXIF metadata** — camera model, GPS coordinates (travel photos vs screenshots), creation date via `CGImageSource`

**SceneType Mapping:** `VNClassifyImageRequest` returns Apple's classifier labels (e.g., "document", "screenshot", "people", "food", "landscape"). Map to `SceneType`:
- "document", "text" → `.document`
- "screenshot" → `.screenshot`
- "people", "portrait" → `.photo` (with `hasFaces = true`)
- "landscape", "nature", "food", "animal" → `.photo`
- "diagram", "chart" → `.diagram`
- "receipt" → `.receipt`
- Unrecognized labels → `.unknown`

**Graceful degradation:** Vision framework is available on macOS 10.13+, so `ImageAnalyzer` works on all supported platforms. No `#if canImport` guard needed (unlike Foundation Models). If a specific Vision request fails (e.g., model not available), that stage is skipped and the enrichment continues with remaining signals.

**Energy budget:** Moderate cost. Run for image files (JPEG, PNG, HEIC, TIFF) and PDFs with embedded images. Skip for files already classified with >85% confidence by cheaper signals. During bulk cleanup, Vision requests are dispatched with `QoS.utility` and limited to 4 concurrent image analyses to avoid CPU/GPU contention on a battery-sensitive menu bar app.

### Stage 3: Download Context (new `DownloadContextExtractor`)

Extracts provenance signals from macOS extended attributes:

- **`com.apple.metadata:kMDItemWhereFroms`** — download URL chain (the URL the file was downloaded from, plus the referring page)
- **Source classification** — parse the URL domain to categorize. Uses a configurable domain-pattern-to-category mapping dictionary (loaded from a bundled JSON file, user-extensible via sync directory). Default mappings:
  - `github.com`, `gitlab.com` → `.developer`
  - `drive.google.com`, `docs.google.com` → `.googleDrive`
  - `slack-files.com`, `files.slack.com` → `.slack`
  - `mail.google.com` → `.email`
  - etc.
  - Unrecognized domains → `.browser` (generic web download)
- **`com.apple.quarantine`** — extract the quarantine agent (which app initiated the download: Safari, Chrome, Mail, Slack, etc.)
- **URL domain as routing signal** — `github.com` files likely belong in a Developer folder, `figma.com` exports in Design, etc.

**Cost:** Essentially free — reading xattrs is a metadata-only operation. Always run.

### AI Classification: Stays as Scoring Layer (not a pipeline stage)

The existing `AppleIntelligenceLayer` remains a `ScoringLayer` — it is NOT part of the pre-scoring enrichment pipeline. This avoids a circular dependency where enrichment output feeds into scoring which includes the AI layer.

**What changes:** The `AppleIntelligenceLayer` receives `EnrichedFileContext` (with Stages 1-3 data) instead of raw `FileCandidate`, giving it richer input for classification:
- Extracted text snippet from Stage 1 (or OCR text from Stage 2)
- Image scene category from Stage 2
- Download source from Stage 3

**Enhanced `FileClassification` output** (macOS 26+ only):
- `documentType`: invoice, resume, contract, research paper, receipt, screenshot, photo, installer, source code, etc.
- `projectAssociation`: inferred project name if detectable from content/path
- `confidence`: 0.0–1.0
- `summary`: one-line description of what the file is
- `suggestedSubfolder`: more specific than today (e.g., "Invoices/2026" not just "Documents")

**Energy budget:** Same `InvocationPolicy` principle — only invoke when cheaper signals produce <85% confidence. The enriched context means AI is called less often (cheaper signals are now stronger) but produces better results when called.

### Protocol Migration: `ScoringLayer`

The `ScoringLayer` protocol changes from:

```swift
func score(_ candidate: FileCandidate) async throws -> [ScoredDestination]
```

to:

```swift
func score(_ context: EnrichedFileContext) async throws -> [ScoredDestination]
```

Since `EnrichedFileContext` wraps `FileCandidate` (accessible via `context.candidate`), existing layer implementations migrate by replacing `candidate.extension` with `context.candidate.extension` etc. Layers that don't need enrichment data can ignore the extra fields.

`ScoringEngine.route(_:)` changes signature to accept `EnrichedFileContext`. The caller (`MoveOrchestrator`) runs the `ContentIntelligencePipeline` first, then passes the enriched context to the scoring engine.

### Integration: `EnrichedFileContext`

```
EnrichedFileContext
  candidate: FileCandidate          (existing, always present)
  extractedText: String?            (Stage 1, or promoted OCR from Stage 2)
  imageAnalysis: ImageAnalysis?     (Stage 2)
    - sceneType: SceneType
    - ocrText: String?
    - hasFaces: Bool
    - exifMetadata: EXIFMetadata?
  downloadContext: DownloadContext?  (Stage 3)
    - sourceURL: URL?
    - referringURL: URL?
    - sourceCategory: SourceCategory
    - quarantineAgent: String?
```

Note: `aiClassification` is NOT part of `EnrichedFileContext` — it remains the output of the `AppleIntelligenceLayer` scoring layer.

The `PatternMatcher` feature vector expands with fixed weights:

| Signal | Weight | Source |
|--------|--------|--------|
| Extension | 0.25 | FileCandidate (existing) |
| Filename tokens | 0.20 | FileCandidate (existing) |
| Scene type / doc indicators | 0.15 | Image analysis / text extraction |
| Source domain | 0.15 | Download context |
| Source app | 0.10 | Download context / metadata |
| Size bucket | 0.10 | FileCandidate (existing) |
| Time bucket | 0.05 | FileCandidate (existing) |

Weights are fixed constants, same approach as v1. No adaptive weight learning in v2. The `PatternMatcher.score()` output normalization (dividing by `maxScore`) is preserved, so confidence calibration remains consistent with v1 despite the expanded feature vector.

---

## 2. Multi-Folder Watching & Bulk Cleanup

### Multi-Folder Watching

#### Folder Roles

Not all folders behave like Downloads. A `FolderRole` enum governs behavior:

| Role | Behavior | Example |
|------|----------|---------|
| **Inbox** | Full auto-move/suggest on new files | ~/Downloads, ~/Desktop |
| **Archive** | On-demand cleanup only, no real-time auto-moves | ~/Documents |
| **Watch-only** | Observe user moves for learning, never auto-move | Well-organized folders used for training |

**Watch-only move detection:** To observe where files are moved TO (not just that they left), `FileWatcher` uses `FSEventStreamEventFlagItemRenamed` paired events. When a file disappears from a watch-only folder and reappears elsewhere in the same FSEvents batch, the source→destination pair is recorded as an observation signal. If the destination can't be determined (e.g., moved to an unwatched location), only a "moved out" event is logged without a destination signal.

#### FileWatcher Changes

- Accept `[URL]` instead of a single `URL`
- One FSEvents stream with multiple paths (FSEvents natively supports this)
- Events tagged with which watched folder they originated from
- Track `FSEventStreamEventFlagItemRenamed` pairs for watch-only folder learning

#### MoveOrchestrator Changes

- Per-folder context: pattern records include a `sourceFolder` field so patterns learned from `~/Downloads` and `~/Desktop` are distinguished
- Respect `FolderRole`: inbox folders get real-time processing, archive folders only process on-demand
- `IgnoreFilter` gains per-folder ignore patterns (e.g., skip `~/Documents/Projects/` subdirectory but clean up `~/Documents/` root-level files)

#### Settings UI

- Folder list editor: add/remove watched folders
- Per-folder: role selector (Inbox / Archive / Watch-only), enable/disable toggle
- Per-folder: optional ignore pattern list

#### Migration: `watchPath` → `watchedFolders`

On first v2 launch, if the v1 `watchPath` UserDefaults key exists, automatically convert it to a single-entry `watchedFolders` array with role `.inbox`. Remove the old `watchPath` key after migration.

### Bulk Cleanup Mode

#### New Component: `BulkCleanupEngine` (actor)

Orchestrates a one-time sweep of an existing folder:

1. **Scan** — enumerate all files in target folder (optionally recursive), create `FileCandidate` for each
2. **Enrich** — run each through `ContentIntelligencePipeline`
3. **Score** — run each enriched candidate through `ScoringEngine` (same three layers as real-time mode)
4. **Tier** — group results by confidence tier:
   - 80–100: high-confidence (recommended moves)
   - 50–79: suggestions
   - 0–49: needs manual review
5. **Present** — surface results through `MoveOrchestrator` as a batch of `OrchestratorEvent.suggested` events. Batch tracking is handled by `BulkCleanupEngine` (which holds the `batchId`), not by `OrchestratorEvent` — the orchestrator is unaware of batching
6. **Execute** — user approves individually or in bulk via existing `FileMover` with full undo support

#### Key Design Decision

Bulk cleanup reuses the entire existing pipeline. It's "pretend all these files just appeared" — no separate scoring logic. The only new code is the scan + batch presentation.

#### Batch Undo

The `move_records` table gains a `batch_id: String?` column. All moves from a single bulk cleanup share the same `batchId` (UUID). `UndoLog` gains:
- `undoBatch(batchId:)` — reverts all moves in the batch that haven't been subsequently moved by the user
- Before reverting each file, check that it still exists at the moved-to location. Skip files that were manually relocated after the cleanup.
- UI shows "Undo Cleanup (N files)" button after a batch operation

#### Progress & Batching

- Large folders (1000+ files) process in batches of ~50
- Progress indicator in menu bar panel: "Scanning... 234/1,891 files"
- Results stream into the suggestion list as batches complete (don't wait for full scan)
- Cancel button to abort mid-scan

#### UI

- "Clean Up" button in the menu bar panel header
- Folder picker to select target
- During scan: progress bar + file count
- After scan: suggestions list populated with all proposed moves, grouped by confidence
- "Move All High-Confidence" button for the 80+ tier (with count badge)
- Full undo support — "Undo Cleanup" reverts the entire batch

---

## 3. Sync & Rule Packs

### Live Sync

#### New Component: `SyncManager` (actor)

Abstracts sync location away from `KnowledgeBase` and `PinnedRulesManager`:

- **Backends:** iCloud Drive, Dropbox, or local-only
  - iCloud: `~/Library/Mobile Documents/iCloud~com~tidy~app/Documents/` (requires iCloud container entitlement `iCloud.com.tidy.app` — needs a properly provisioned build via Xcode with a Developer account; ad-hoc signed builds from `bundle.sh` cannot use iCloud)
  - Dropbox: `~/Dropbox/.tidy/` (existing)
  - Local: `~/Library/Application Support/Tidy/` (existing fallback)
- User selects backend in Settings
- `SyncManager` provides a `syncDirectory: URL` that consumers use — they don't know which backend is active

#### Sync Strategy: Merge-on-Open (not raw file sync)

**Important:** We do NOT sync the raw `.db` SQLite file via iCloud/Dropbox. SQLite's internal locking and `NSFileCoordinator` are incompatible approaches that risk deadlocks.

Instead, use a **change log** approach:
- Each device writes to its own local `knowledge.db` as today
- On change, export a JSON change log (`changes-<deviceId>-<timestamp>.json`) to the sync directory
- On detecting new change logs from other devices (via `NSMetadataQuery` for iCloud, or `FSEvents` for Dropbox), merge them into the local database
- After successful merge, archive processed change logs

**Change log format:**

Change logs mirror the actual `PatternRecord` multi-column structure to preserve co-occurrence information (the fact that a specific extension + tokens + source app appeared together):

```json
{
  "deviceId": "MacBook-Pro-abc123",
  "timestamp": "2026-03-17T12:00:00Z",
  "patterns": [
    {
      "fileExtension": "pdf",
      "filenameTokens": "[\"invoice\",\"2026\"]",
      "sourceApp": "Safari",
      "sizeBucket": "medium",
      "timeBucket": "morning",
      "documentType": "invoice",
      "sourceDomain": "mail.google.com",
      "sceneType": null,
      "sourceFolder": "~/Downloads",
      "destination": "~/Documents/Invoices",
      "signalType": "observation",
      "weight": 3.0,
      "createdAt": "2026-03-17T12:00:00Z"
    }
  ],
  "pinnedRules": [
    { "extension": "dmg", "destination": "~/Apps/Installers", "updatedAt": "2026-03-17T12:00:00Z" }
  ]
}
```

**Device ID generation:** A UUID generated on first launch and persisted in UserDefaults as `deviceId`. Stable across app restarts, unique per machine.

#### Conflict Resolution

| Data | Strategy | Rationale |
|------|----------|-----------|
| Pinned rules | Last-write-wins by per-rule `updatedAt` timestamp | Simple, predictable. Rules are user-explicit, conflicts are rare. |
| Pattern records | Merge by composite key `(fileExtension, filenameTokens, sourceApp, sourceFolder, destination)` — weights are **summed** (capped at 20.0) | Preserves accumulated learning from both devices. Two machines observing the same pattern reinforces it additively. |
| Move records | Local-only, not synced | Undo is device-specific. Move history is too voluminous and device-specific to sync. |

`pattern_records` gains a `syncedAt: Date?` column to track which records have been exported. Only records with `syncedAt == nil` or `syncedAt < lastModified` are included in change logs.

On merge, Tidy shows a notification: "Merged 12 patterns from your other Mac".

#### Graceful Offline

- iCloud: write change logs locally; iCloud syncs them when reconnected (handled natively by iCloud Drive)
- Dropbox: same — Dropbox client handles offline queuing

#### Migration

- First launch after v2 update: detect existing sync location, offer to keep or switch
- "Switch sync backend" in Settings: copies data to new location, verifies, then removes from old location

### Exportable Rule Packs

#### Format: `.tidypack`

A JSON file with registered UTI so Tidy opens it on double-click.

**Path portability:** All paths in `.tidypack` files use `~` prefix for home-relative paths (e.g., `~/Documents/PDFs`). Expanded via `NSString.expandingTildeInPath` at import time. This ensures packs work across different users and machines.

```json
{
  "version": 1,
  "metadata": {
    "name": "Developer Essentials",
    "description": "Routes code, packages, and dev tools to organized folders",
    "author": "tkejzlar",
    "createdAt": "2026-03-17T12:00:00Z"
  },
  "pinnedRules": [
    { "extension": "dmg", "destination": "~/Applications/Installers" },
    { "extension": "pkg", "destination": "~/Applications/Installers" }
  ],
  "patterns": [
    { "feature": "extension", "value": "js", "destination": "~/Developer/Downloads", "weight": 5.0 },
    { "feature": "sourceURL", "value": "github.com", "destination": "~/Developer/Downloads", "weight": 8.0 }
  ],
  "folderTemplate": [
    "~/Developer/Downloads",
    "~/Developer/Packages",
    "~/Applications/Installers"
  ]
}
```

#### Export Flow

Settings UI → "Export Rule Pack" → modal:
1. Name and describe the pack
2. Select which pinned rules to include (checklist)
3. Select which learned patterns to include (filtered by minimum weight threshold)
4. Optionally include folder structure template
5. Save `.tidypack` file (paths converted to `~`-relative on export)

#### Import Flow

Double-click `.tidypack` file (or Settings → "Import Rule Pack"):
1. Tidy opens and shows a preview: what rules and patterns will be imported
2. For each pinned rule: accept or skip
3. For patterns: imported with 0.5x weight reduction (don't override local learning)
4. Optionally create missing folders from the template
5. Summary: "Imported 8 rules and 24 patterns from 'Developer Essentials'"

#### UTI Registration

Register `com.tidy.rulepack` UTI in `Info.plist`:
- `UTExportedTypeDeclarations`: declare `com.tidy.rulepack` conforming to `public.json`, with `.tidypack` extension
- `CFBundleDocumentTypes`: register Tidy as handler for `com.tidy.rulepack`

Note: `scripts/bundle.sh` must be updated to include these plist entries. Ad-hoc signed apps installed outside `/Applications` may not automatically register as file handlers via Launch Services — the import flow via Settings UI is the primary path, with double-click as a convenience for `/Applications` installs.

---

## Data Model Changes

### New Types

```
FolderRole           — enum: inbox, archive, watchOnly
WatchedFolder        — struct: url, role, isEnabled, ignorePatterns (Codable, stored in UserDefaults)
ImageAnalysis        — struct: sceneType, ocrText, hasFaces, exifMetadata
SceneType            — enum: screenshot, photo, diagram, receipt, document, unknown
DownloadContext      — struct: sourceURL, referringURL, sourceCategory, quarantineAgent
SourceCategory       — enum: developer, googleDrive, slack, email, appStore, browser, unknown
EnrichedFileContext  — struct: Sendable, wraps FileCandidate + pipeline outputs (Stages 1-3 only, no AI)
RulePack             — struct: Codable, represents .tidypack contents
SyncBackend          — enum: icloud, dropbox, local
```

### Database Migrations

- `pattern_records`: add columns `document_type TEXT`, `source_domain TEXT`, `scene_type TEXT`, `source_folder TEXT`
- `pattern_records`: add column `synced_at REAL` (nullable timestamp for sync tracking)
- `move_records`: add column `batch_id TEXT` (nullable, for bulk cleanup batch undo)
- `sync_metadata`: new table (`device_id TEXT PRIMARY KEY`, `last_sync_timestamp REAL`). Note: sync backend is stored only in UserDefaults (single source of truth), not duplicated in the database.

### Settings (UserDefaults)

- `watchedFolders`: `[WatchedFolder]` encoded as JSON (replaces single `watchPath`)
- `syncBackend`: `SyncBackend` raw value
- `syncPath`: String (for Dropbox custom path)

Note: `watched_folders` is NOT a database table — folder configuration is a user preference stored in UserDefaults alongside other settings, not learned data.

---

## Safety Rails (Extended)

All existing safety rails remain. Additions:

- **Bulk cleanup is always suggest-first** — even high-confidence moves are presented for review before execution. No silent bulk auto-moves.
- **Watch-only folders never auto-move** — prevents Tidy from disrupting well-organized directories
- **Archive folders require explicit "Clean Up" trigger** — no real-time auto-moves on archive-role folders
- **Imported patterns are weight-reduced** — 0.5x prevents an imported pack from overriding local learning
- **Sync conflict notification** — user always knows when data was merged from another device
- **Batch undo** — entire bulk cleanup can be reverted as a single operation, skipping files that were subsequently moved
- **Vision concurrency limit** — max 4 concurrent image analyses at `QoS.utility` to protect battery life

---

## Out of Scope for v2

- Cloud-hosted sync service (no custom backend — rely on iCloud/Dropbox)
- Rule pack marketplace or discovery
- iOS/iPadOS companion app
- Automation/Shortcuts integration
- Custom scoring layer plugins
- Adaptive pattern weight learning (weights are fixed constants)
- Folder-specific confidence thresholds
- Content-based pinned rules (e.g., "PDFs containing 'invoice' always go to Finance")
