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

This is a Swift Package / Xcode project. Standard commands:

```bash
# Build
swift build
# or: xcodebuild -scheme Tidy build

# Run tests (CommandLineTools-only; Xcode can use plain `swift test`)
swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks
# Single test: swift test --filter TestClassName/testMethodName -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks

# Run
swift run
```

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
