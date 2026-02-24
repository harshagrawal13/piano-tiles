# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Command

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PianoTiles.xcodeproj -scheme PianoTiles -destination 'generic/platform=iOS' -configuration Debug build
```

Always build-check after making code changes. There are no tests or linting configured.

## Project Setup

- **Swift 6.0** with strict concurrency checking
- **iOS 17.0** deployment target, portrait-only
- Dual build system: `Package.swift` (SPM) and `PianoTiles.xcodeproj` (Xcode). The Xcode project is the primary build target. Keep both in sync when adding files or resources.
- MIDI files live in `Sources/Resources/` and must be registered in both `Package.swift` (`resources: [.process("Resources")]`) and `project.pbxproj` (PBXResourcesBuildPhase + PBXFileReference).

## Architecture

**State & rendering**: `GameState` (`@Observable @MainActor`) is the single source of truth. `PianoTilesApp` routes between views based on `GameState.phase` (menu → songSelection → playing → gameOver). `GameView` renders everything in a `Canvas` driven by `TimelineView` at ~60fps — there is no SwiftUI view hierarchy for individual tiles.

**Game loop flow**: `GameView.updateGameLoop()` → `TileEngine.spawnUpcomingTiles()` → `TileEngine.updateTiles()` → touch input via `TouchOverlay` (UIKit `UIView` subclass) → `TileEngine.handleTouchDown()` → scoring + `AudioEngine.playNote()`.

**Tile lifecycle**: Tiles spawn off-screen with a 4-second lookahead, fall at `Constants.fallSpeed × speedMultiplier`, and must be tapped sequentially at the hit zone (88% screen height). States: `.falling` → `.tapped` or `.missed`/`.failed`. Grid-snapping ensures one tile per row with consecutive tiles in different lanes.

**Audio**: `AudioEngine` is a custom 8-voice polyphonic synth using `AVAudioEngine` with additive harmonic synthesis (5 overtones) and ADSR envelopes. Thread safety via `os_unfair_lock` on an `UnsafeMutablePointer<Voice>` buffer. Note-off is scheduled via `Task.sleep`.

**Song system**: `SongCatalog` provides a static list of `SongDescriptor`s — one hardcoded Chopin Nocturne plus auto-discovered `.mid` files from the app bundle. `MIDIParser` handles standard MIDI format 0/1, converts ticks to beats via PPQN, assigns notes to 4 lanes by dividing the pitch range into equal buckets, and deduplicates overlapping notes.

## Concurrency Patterns

- `GameState`, `TileEngine`: `@MainActor` — all game state stays on main thread
- `AudioEngine`: `@unchecked Sendable` with `os_unfair_lock` for voice buffer access from the audio render callback
- Use `nonisolated(unsafe)` for `UnsafeMutablePointer` properties on `@MainActor` classes that need access from `deinit` or `@Sendable` closures
- All data types (`Tile`, `NoteEvent`, `SongData`, `SongDescriptor`) are `Sendable` structs

## Adding New Songs

Drop a `.mid` file into `Sources/Resources/`. Add a PBXFileReference + PBXBuildFile entry in `project.pbxproj`. For known songs, add metadata to the `midiMeta` array in `SongCatalog` (`NoteData.swift`); unknown files are auto-discovered with title derived from filename.
