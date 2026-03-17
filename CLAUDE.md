# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tidy is a native macOS menu bar utility that learns where downloaded files belong by observing user behavior, then organizes them automatically. Privacy-first: all intelligence runs locally, no cloud APIs.

See DESIGN.md for the full specification.

## Tech Stack

- **Swift + SwiftUI** — native menu bar app targeting macOS 26 (Tahoe) with graceful fallback to macOS 14+
- **SQLite via GRDB** — local knowledge base for learned file routing patterns
- **Foundation Models framework** — on-device 3B LLM for semantic file classification (macOS 26+ only)
- **FSEvents** — file system watching for ~/Downloads
- **Spotlight / MDItem APIs** — file metadata extraction (UTI, download URL, source app)

## Build & Development

Two SPM targets: `TidyCore` (library) and `Tidy` (executable menu bar app).

```bash
# Build
swift build

# Run the app
swift run Tidy

# Run tests (CommandLineTools-only env; with Xcode, plain `swift test` works)
swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks

# Single test
swift test --filter SuiteName/testMethodName -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

**Testing quirk:** `import Foundation` and `import Testing` cannot coexist in the same file under CommandLineTools. Foundation types are available through `@testable import TidyCore`. Shared test helpers go in `Tests/TidyCoreTests/TestHelpers.swift` (which imports Foundation but not Testing).

**Foundation Models quirk:** macOS 26 SDK headers are present but CommandLineTools lacks the `FoundationModelsMacros` compiler plugin. The `@Generable` code is guarded with `#if canImport(FoundationModels) && FOUNDATION_MODELS_MACROS_AVAILABLE`. Enable the flag in Package.swift when building with Xcode.

## Code Structure

```
Sources/TidyCore/
  Models/        — FileCandidate, SizeBucket, TimeBucket, PatternRecord, MoveRecord, RoutingDecision
  Database/      — KnowledgeBase (GRDB/SQLite with migrations, undo support, pruning)
  Metadata/      — FileMetadataExtractor (Spotlight/MDItem)
  Heuristics/    — ScreenshotDetector, InstallerDetector, FolderArchaeologist,
                   TokenClusterer, RecencyWeighter, HeuristicsEngine
  Matching/      — PatternMatcher (weighted feature vector matching)
  Scoring/       — ScoringLayer protocol (async), ScoringEngine (2/3-layer with pinned rules)
  Intelligence/  — ContentExtractor, InvocationPolicy, FileClassification, AppleIntelligenceLayer
  Watcher/       — FileWatcher (FSEvents), SettleTimer (actor), IgnoreFilter
  Operations/    — FileMover, UndoLog (500-entry pruning), SignalRecorder
  Orchestrator/  — MoveOrchestrator (actor), OrchestratorEvent
  Rules/         — PinnedRule, PinnedRulesManager (JSON persistence)
Sources/Tidy/
  TidyApp.swift              — @main with MenuBarExtra
  AppState.swift             — @Observable: bridges TidyCore → SwiftUI, settings persistence
  Views/                     — PanelView, SuggestionCard, RecentMoveRow, SettingsView, StatusFooter
```

**Key entry points:**
- `ScoringEngine.route(_:) async throws -> RoutingDecision?` — scores a file, returns destination + confidence + tier
- `MoveOrchestrator.processFile(_:) async throws -> OrchestratorEvent?` — full pipeline: filter → score → move/suggest
- `AppState.start()` — bootstraps all components, starts FileWatcher event loop

## Architecture — Three Intelligence Layers

The core design uses three scoring layers that combine with shifting weights:

1. **Pattern Matching (Layer 1)** — SQLite-based feature vector matching (extension, filename tokens, source app, size bucket, time bucket). Sub-millisecond, always runs. Weight grows from 0.0 to 0.6 as user history builds.

2. **Apple Intelligence (Layer 2)** — On-device Foundation Models framework for semantic understanding. Only invoked when pattern matching confidence is low (<50%) or content classification would change routing. Weight stays at 0.3 once stabilized. Disabled on pre-macOS 26.

3. **Heuristics (Layer 3)** — Day-one bootstrap intelligence: folder archaeology, Spotlight metadata, screenshot/installer detection, filename token clustering, recency-weighted folder preference. Weight decays from 0.5 to 0.1 as learned patterns take over.

**Scoring:** `final_score(destination) = w1 × pattern + w2 × apple_intelligence + w3 × heuristic` → confidence 0–100.

**Confidence tiers:** 80–100 auto-moves (with undo), 50–79 suggests, 0–49 asks user.

## Key Design Constraints

- **Never deletes files** — only moves. Worst case is wrong folder + undo.
- **Settle time** — files must be unchanged for N seconds before acting (catches partial downloads).
- **Correction signal weighted 3x** — user overrides are the strongest learning signal.
- **Apple Intelligence is optional** — the app must work fully on macOS 14+ without it (Layers 1+3 only).
- **Dropbox sync** — knowledge.db and pinned-rules.json live in `~/Dropbox/.tidy/` for cross-device sync. Conflict resolution is last-write-wins per row via timestamps.
- **Battery conscious** — FSEvents for watching (not polling), Foundation Model only when needed.

## UI Pattern

Menu bar app with three icon states: `◇` idle, `◆` has suggestions, `↻` processing. Dropdown panel shows suggestions with approve/reject/redirect actions and recent moves with undo. Global shortcut: `⌘⇧T`.
