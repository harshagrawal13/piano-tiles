import Foundation

struct Tile: Identifiable, Sendable {
    let id: UUID
    let noteEvent: NoteEvent
    let targetTime: Double
    let lane: Int
    var yPosition: CGFloat
    var state: TileState
    var tappedTime: Double?

    let visualHeight: CGFloat

    enum TileState: Sendable {
        case falling
        case tapped
        case missed
        case failed
    }

    init(noteEvent: NoteEvent, targetTime: Double, bpm: Double, lane: Int) {
        self.id = UUID()
        self.noteEvent = noteEvent
        self.targetTime = targetTime
        self.lane = lane
        self.yPosition = 0
        self.state = .falling
        self.tappedTime = nil
        self.visualHeight = Constants.tileHeight
    }
}

@MainActor
enum TileEngine {
    private static func snapUpToGrid(_ time: Double, step: Double) -> Double {
        guard step > 0 else { return time }
        return ceil(time / step) * step
    }

    static func spawnUpcomingTiles(state: GameState) {
        let songData = state.songData
        let currentTime = state.songElapsedTime
        let lookAhead = Constants.lookAheadSeconds
        let laneStepSeconds = Constants.tileSnapGridUnitSeconds
        // Minimum target time so tiles enter from above the visible screen
        let screenTravelTime = Double(state.hitZoneY) / Double(Constants.fallSpeed)

        while state.nextNoteIndex < songData.notes.count {
            let note = songData.notes[state.nextNoteIndex]
            let noteTime = note.startBeat * 60.0 / songData.bpm

            if noteTime <= currentTime + lookAhead {
                // Ensure consecutive tiles are in different lanes
                var effectiveLane = note.lane
                if effectiveLane == state.lastSpawnedLane {
                    let others = (0..<Constants.laneCount).filter { $0 != effectiveLane }
                    effectiveLane = others.randomElement()!
                }

                let globalLastTime = state.laneLastTargetTime.max()! + laneStepSeconds

                var adjustedTargetTime = max(
                    snapUpToGrid(noteTime, step: laneStepSeconds),
                    globalLastTime,
                    screenTravelTime
                )
                adjustedTargetTime = snapUpToGrid(adjustedTargetTime, step: laneStepSeconds)

                let tile = Tile(
                    noteEvent: note,
                    targetTime: adjustedTargetTime,
                    bpm: songData.bpm,
                    lane: effectiveLane
                )
                state.tiles.append(tile)
                state.laneLastTargetTime[effectiveLane] = adjustedTargetTime
                state.lastSpawnedLane = effectiveLane
                state.nextNoteIndex += 1
            } else {
                break
            }
        }
    }

    static func updateTiles(state: GameState) {
        let currentTime = state.songElapsedTime
        let hitY = state.hitZoneY

        for i in state.tiles.indices {
            let tile = state.tiles[i]
            guard tile.state != .missed && tile.state != .failed else { continue }

            let timeUntilHit = tile.targetTime - currentTime
            state.tiles[i].yPosition = hitY - CGFloat(timeUntilHit) * Constants.fallSpeed

            if tile.state == .falling {
                // Missed: tile fully off-screen (top edge past screen bottom)
                let tileTopY = state.tiles[i].yPosition - tile.visualHeight
                if tileTopY > state.screenSize.height {
                    state.tiles[i].state = .missed
                    state.endGame(reason: .missed)
                    return
                }
            }
        }

        // Remove resolved tiles only after they have moved off-screen.
        state.tiles.removeAll { tile in
            guard tile.state == .tapped || tile.state == .missed else { return false }
            let tileTopY = tile.yPosition - tile.visualHeight
            return tileTopY > state.screenSize.height + tile.visualHeight
        }
    }

    static func handleTouchDown(lane: Int, touchY: CGFloat, state: GameState) {
        guard state.phase == .playing, !state.isInCountdown, !state.isFailing else { return }

        // Must tap tiles in sequential order — find the first falling tile
        guard let nextIdx = state.tiles.firstIndex(where: { $0.state == .falling }) else {
            return
        }

        let tile = state.tiles[nextIdx]
        let tileBottomY = tile.yPosition
        let tileTopY = tileBottomY - tile.visualHeight

        // Ignore taps while the next tile isn't visible yet
        guard tileBottomY > 0 && tileTopY < state.screenSize.height else {
            return
        }

        // Tap must land inside the tile's grid box (correct lane + correct Y)
        let correctLane = lane == tile.lane
        let correctY = touchY >= tileTopY && touchY <= tileBottomY

        guard correctLane && correctY else {
            state.tiles[nextIdx].state = .failed
            state.startFailAnimation(tileIdx: nextIdx, reason: .wrongLane)
            return
        }

        // Valid tap
        state.audioEngine.playNote(tile.noteEvent.midiNote, velocity: 110)
        state.tiles[nextIdx].state = .tapped
        state.tiles[nextIdx].tappedTime = state.songElapsedTime

        // Score based on timing accuracy
        let dt = abs(state.songElapsedTime - tile.targetTime)
        let points: Int
        if dt < 0.08 {
            points = 3
            state.perfectCount += 1
        } else if dt < 0.19 {
            points = 2
            state.goodCount += 1
        } else {
            points = 1
            state.okCount += 1
        }
        state.addScore(points: points)

        // Schedule note-off after duration
        let durationSeconds = tile.noteEvent.durationBeats * 60.0 / state.songData.bpm
        let midiNote = tile.noteEvent.midiNote
        let engine = state.audioEngine
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(durationSeconds * 1000)))
            engine.stopNote(midiNote)
        }
    }

    static func handleTouchUp(lane: Int, state: GameState) {
        // No-op without hold tiles
    }

    static func checkSongComplete(state: GameState) {
        if state.nextNoteIndex >= state.songData.notes.count {
            let allDone = state.tiles.allSatisfy {
                $0.state != .falling
            }
            if allDone {
                state.endGame(reason: .songComplete)
            }
        }
    }
}
