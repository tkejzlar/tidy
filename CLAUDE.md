# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tidy is a native macOS menu bar utility that learns where downloaded files belong by observing user behavior, then organizes them automatically. Privacy-first: all intelligence runs locally — no cloud APIs, no data leaves the device.

See DESIGN.md for the full product specification.

## Tech Stack

- **Swift 6 + SwiftUI** — native menu bar app, `MenuBarExtra` with `.window` style
- **GRDB.swift 7.x** — SQLite ORM for the local knowledge base
- **Foundation Models framework** — on-device 3B LLM for semantic file classification (macOS 26+ only, guarded with `#if canImport`)
- **FSEvents (CoreServices)** — battery-efficient file system watching
- **PDFKit** — PDF text extraction for content-aware classification
- **Spotlight / MDItem APIs** — file metadata extraction (UTI, download URL, source app, dimensions)
- **ServiceManagement** — launch-at-login without a LaunchAgent plist
- **UserNotifications** — native macOS notifications for auto-moves

## Build & Development

Two SPM targets: `TidyCore` (library with all logic) and `Tidy` (executable menu bar app).

```bash
# Build
swift build

# Run the app directly
swift run Tidy

# Package as .app bundle (builds release + creates build/Tidy.app)
./scripts/bundle.sh

# Install to /Applications
cp -r build/Tidy.app /Applications/

# Run tests (CommandLineTools-only env; with Xcode, plain `swift test` works)
swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks

# Single test
swift test --filter SuiteName/testMethodName -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

### Environment Quirks

**Testing:** `import Foundation` and `import Testing` cannot coexist in the same file under CommandLineTools. Foundation types are available through `@testable import TidyCore`. Shared test helpers (file creation, temp paths) go in `Tests/TidyCoreTests/TestHelpers.swift` (imports Foundation but not Testing).

**Foundation Models:** macOS 26 SDK headers are present in CommandLineTools but the `FoundationModelsMacros` compiler plugin is missing. The `@Generable` code is double-guarded with `#if canImport(FoundationModels) && FOUNDATION_MODELS_MACROS_AVAILABLE`. To enable: uncomment the `.define("FOUNDATION_MODELS_MACROS_AVAILABLE")` line in Package.swift (requires Xcode with the macro plugin).

**App bundling:** SPM doesn't produce `.app` bundles natively. `scripts/bundle.sh` wraps the release binary into `build/Tidy.app` with an `Info.plist` (`LSUIElement=true` hides from dock) and ad-hoc code signature.

## Code Structure

```
Sources/TidyCore/                    38 source files — all business logic
  Models/                            Data types
    FileCandidate.swift              Input to scoring: path, tokens, extension, size/time bucket, metadata
    SizeBucket.swift                 Enum: tiny/small/medium/large/huge (byte thresholds)
    TimeBucket.swift                 Enum: morning/midday/afternoon/evening/night
    PatternRecord.swift              GRDB record: learned pattern + signal type + weight
    MoveRecord.swift                 GRDB record: move history for undo
    RoutingDecision.swift            Output: destination, confidence (0-100), tier, layer breakdown
  Database/
    KnowledgeBase.swift              GRDB DatabaseQueue wrapper — migrations, pattern CRUD, move log, pruning
  Metadata/
    FileMetadataExtractor.swift      Wraps MDItem/Spotlight APIs → FileMetadata struct
  Heuristics/                        Day-one intelligence (Layer 3)
    ScreenshotDetector.swift         Regex filename matching + kMDItemIsScreenCapture
    InstallerDetector.swift          Extension set: dmg/pkg/mpkg/app
    FolderArchaeologist.swift        Scans folder tree → extension affinity map + confidence boost
    TokenClusterer.swift             Builds token sets from organized folder filenames
    RecencyWeighter.swift            Exponential decay: weight = 0.95^days
    HeuristicsEngine.swift           Composes all heuristics → ScoringLayer
  Matching/                          Learned intelligence (Layer 1)
    PatternMatcher.swift             Weighted feature vector: ext(0.35) + tokens(0.30) + app(0.15) + size(0.10) + time(0.10)
  Scoring/
    ScoringLayer.swift               Protocol: func score(_:) async throws -> [ScoredDestination]
    ScoringEngine.swift              Combines layers with shifting weights; pinned rules override at 100%
  Intelligence/                      Semantic intelligence (Layer 2, macOS 26+)
    ContentExtractor.swift           Extracts text from PDF/TXT/MD/CSV (first ~500 words)
    InvocationPolicy.swift           Energy budget: when to invoke AI based on confidence + file type
    FileClassification.swift         @Generable struct: category, subfolder, confidence, summary
    AppleIntelligenceLayer.swift     ScoringLayer using on-device Foundation Models
  Watcher/
    FileWatcher.swift                FSEvents wrapper → AsyncStream<FileEvent>
    SettleTimer.swift                Actor: tracks file stability before acting (default 5s)
    IgnoreFilter.swift               Rejects dotfiles, .part/.crdownload/.download, tmp/temp
  Operations/
    FileMover.swift                  Atomic moves with collision handling (-2, -3 suffix)
    UndoLog.swift                    Last 500 moves with auto-pruning, undo support
    SignalRecorder.swift             Records observation/correction/confirmation → KnowledgeBase
  Orchestrator/
    MoveOrchestrator.swift           Actor: full pipeline watch → filter → score → move/suggest
    OrchestratorEvent.swift          Enum: autoMoved, suggested, newFile, undone, observed
  Rules/
    PinnedRule.swift                 Model: extension → destination mapping (100% confidence)
    PinnedRulesManager.swift         JSON persistence, match, add/remove

Sources/Tidy/                        7 source files — SwiftUI app
  TidyApp.swift                      @main with MenuBarExtra, notification permission, lifecycle
  AppState.swift                     @Observable @MainActor: bridges TidyCore → SwiftUI
                                     Settings persistence (UserDefaults), FileWatcher event loop,
                                     user actions (approve/reject/redirect/undo), pinned rules mgmt
  Views/
    PanelView.swift                  Main dropdown: header, suggestions list, recent moves, empty state
    SuggestionCard.swift             File card: icon, filename, destination, confidence, action buttons
    RecentMoveRow.swift              Move entry: filename, destination, time-ago, undo button
    SettingsView.swift               Watch folder, confidence sliders, settle time, toggles,
                                     pinned rules editor, KB stats, launch-at-login, sync path
    StatusFooter.swift               Bottom bar: unsorted file count, moved-today counter

bundle/
  Info.plist                         App bundle metadata: LSUIElement=true, bundle ID, version

scripts/
  bundle.sh                          Builds release binary → build/Tidy.app with ad-hoc signing

Tests/TidyCoreTests/                 22 test files, 94 tests across 21 suites
  TestHelpers.swift                  Foundation-based test utilities (temp files, cleanup)
```

### Key Entry Points

- **`ScoringEngine.route(_:)`** `async throws -> RoutingDecision?` — scores a file candidate through all layers (pinned rules → pattern matching → AI → heuristics), returns destination + confidence + tier
- **`MoveOrchestrator.processFile(_:)`** `async throws -> OrchestratorEvent?` — full pipeline: ignore filter → scoring → auto-move or suggest
- **`MoveOrchestrator.recordUserMove(...)`** — records observation signal when user manually moves a file (primary learning mechanism)
- **`AppState.start()`** — bootstraps KnowledgeBase, scans folders, creates ScoringEngine + MoveOrchestrator, starts FileWatcher event loop

## Architecture — Three Intelligence Layers

The scoring engine uses three independent layers whose weights shift as user history accumulates:

| Phase | Pattern (w1) | Apple Intelligence (w2) | Heuristics (w3) |
|-------|-------------|------------------------|-----------------|
| Day 1 (0 moves) | 0.0 | 0.5 | 0.5 |
| Week 1 (~30 moves) | 0.3 | 0.4 | 0.3 |
| Week 3 (~80 moves) | 0.5 | 0.3 | 0.2 |
| Month 2+ (100+ moves) | 0.6 | 0.3 | 0.1 |

Without Apple Intelligence (pre-macOS 26), weights are re-normalized to 2 layers.

**Pinned rules** bypass all layers — they always produce 100% confidence.

**Scoring formula:** `final_score = w1 × pattern + w2 × ai + w3 × heuristic` → confidence 0–100

**Confidence tiers drive behavior:**
- 80–100: Auto-move (with undo notification, confirmation signal deferred until 60s undo window expires)
- 50–79: Suggest (file stays, UI shows suggestion card)
- 0–49: Ask (no guess, "new file" indicator)

## Learning Signals

Three signal types feed the pattern matcher:

| Signal | Weight | Trigger |
|--------|--------|---------|
| Observation | 1.0x | User manually moves a file out of Downloads |
| Correction | 3.0x | User overrides Tidy's suggestion or auto-move |
| Confirmation | 1.0x | User approves suggestion or undo window expires |

## Data Storage

- **Knowledge base:** `~/Dropbox/.tidy/knowledge.db` (falls back to `~/Library/Application Support/Tidy/knowledge.db`)
- **Pinned rules:** `~/Dropbox/.tidy/pinned-rules.json` (same fallback)
- **Settings:** `UserDefaults` (watchPath, thresholds, settle time, toggles, sync path)
- **Undo log:** Stored in knowledge.db `move_records` table, auto-pruned to 500 entries

## Safety Rails

- **Never deletes** — only moves files. Worst case: wrong folder + undo.
- **Settle time** — waits N seconds (default 5) for file to stop changing before acting.
- **Ignore list** — skips dotfiles, `.part`/`.crdownload`/`.download`, files with `tmp`/`temp` tokens.
- **Undo** — last 500 moves persisted, survives restart.
- **Pause** — one click to stop all watching/moving.
- **Deferred confirmation** — auto-moves don't self-reinforce; confirmation recorded only after undo window expires.
