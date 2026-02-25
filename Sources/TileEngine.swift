import Foundation

struct Tile: Identifiable, Sendable {
    let id: UUID
    let noteEvent: NoteEvent
    let targetTime: Double
    let lane: Int
    var yPosition: CGFloat
    var state: TileState
    var tappedTime: Double?

    let isHold: Bool
    let holdEndTime: Double
    var holdingTouchID: ObjectIdentifier?

    let visualHeight: CGFloat

    enum TileState: Sendable {
        case falling
        case tapped
        case missed
        case failed
        case holding
        case holdComplete
    }

    init(noteEvent: NoteEvent, targetTime: Double, bpm: Double, lane: Int, fallSpeed: CGFloat) {
        self.id = UUID()
        self.noteEvent = noteEvent
        self.targetTime = targetTime
        self.lane = lane
        self.yPosition = 0
        self.state = .falling
        self.tappedTime = nil
        self.holdingTouchID = nil

        let durationSeconds = noteEvent.durationBeats * 60.0 / bpm
        self.isHold = noteEvent.durationBeats > Constants.holdBeatThreshold
        self.holdEndTime = targetTime + durationSeconds

        if self.isHold {
            self.visualHeight = max(Constants.holdTileMinHeight, CGFloat(durationSeconds) * fallSpeed)
        } else {
            self.visualHeight = Constants.tileHeight
        }
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
        let laneStepSeconds = songData.tileSnapGridUnitSeconds
        // Minimum target time so tiles enter from above the visible screen
        let screenTravelTime = Double(state.hitZoneY) / Double(songData.fallSpeed)

        while state.nextNoteIndex < songData.notes.count {
            let note = songData.notes[state.nextNoteIndex]
            let noteTime = note.startBeat * 60.0 / songData.bpm + state.loopTimeOffset

            if noteTime <= currentTime + lookAhead {
                let effectiveLane = note.lane

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
                    lane: effectiveLane,
                    fallSpeed: songData.fallSpeed
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
            state.tiles[i].yPosition = hitY - CGFloat(timeUntilHit) * state.songData.fallSpeed

            if tile.state == .falling {
                // Missed: tile fully off-screen (top edge past screen bottom)
                let tileTopY = state.tiles[i].yPosition - tile.visualHeight
                if tileTopY > state.screenSize.height {
                    state.tiles[i].state = .missed
                    state.endGame(reason: .missed)
                    return
                }
            } else if tile.state == .holding {
                if currentTime >= tile.holdEndTime {
                    state.tiles[i].state = .holdComplete
                    state.tiles[i].tappedTime = currentTime
                    state.tiles[i].holdingTouchID = nil
                    state.audioEngine.stopNote(tile.noteEvent.midiNote)
                    state.addScore(points: Constants.holdMaxPoints)
                    state.incrementTilesCompleted()
                }
            }
        }

        // Remove resolved tiles only after they have moved off-screen.
        state.tiles.removeAll { tile in
            guard tile.state == .tapped || tile.state == .missed || tile.state == .holdComplete else { return false }
            let tileTopY = tile.yPosition - tile.visualHeight
            return tileTopY > state.screenSize.height + tile.visualHeight
        }
    }

    static func handleTouchDown(lane: Int, touchY: CGFloat, touchID: ObjectIdentifier, state: GameState) {
        guard state.phase == .playing, !state.isInCountdown, !state.isFailing, !state.isPaused else { return }

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

        // Play the note
        state.audioEngine.playNote(tile.noteEvent.midiNote, velocity: 110)
        state.tiles[nextIdx].tappedTime = state.songElapsedTime

        if tile.isHold {
            // Hold tile: start holding, do NOT schedule note-off
            state.tiles[nextIdx].state = .holding
            state.tiles[nextIdx].holdingTouchID = touchID
        } else {
            // Regular tile: tap and score immediately
            state.tiles[nextIdx].state = .tapped

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
            state.incrementTilesCompleted()

            // Schedule note-off after duration
            let durationSeconds = tile.noteEvent.durationBeats * 60.0 / state.songData.bpm
            let midiNote = tile.noteEvent.midiNote
            let engine = state.audioEngine
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(durationSeconds * 1000)))
                engine.stopNote(midiNote)
            }
        }
    }

    static func handleTouchUp(lane: Int, touchID: ObjectIdentifier, state: GameState) {
        guard let idx = state.tiles.firstIndex(where: {
            $0.state == .holding && $0.holdingTouchID == touchID
        }) else { return }

        let tile = state.tiles[idx]

        // Stop audio
        state.audioEngine.stopNote(tile.noteEvent.midiNote)

        // Compute hold fraction for partial scoring
        let totalHoldDuration = tile.holdEndTime - tile.targetTime
        let heldDuration = state.songElapsedTime - (tile.tappedTime ?? tile.targetTime)
        let holdFraction = min(1.0, max(0.0, heldDuration / totalHoldDuration))
        let points = Constants.holdMinPoints + Int(holdFraction * Double(Constants.holdMaxPoints - Constants.holdMinPoints))
        state.addScore(points: points)
        state.incrementTilesCompleted()

        // Transition to complete
        state.tiles[idx].state = .holdComplete
        state.tiles[idx].tappedTime = state.songElapsedTime
        state.tiles[idx].holdingTouchID = nil
    }

    static func checkAndLoopSong(state: GameState) {
        guard state.nextNoteIndex >= state.songData.notes.count else { return }
        let allDone = state.tiles.allSatisfy {
            $0.state != .falling && $0.state != .holding
        }
        guard allDone else { return }

        // Use actual last tile time (not theoretical song duration) to avoid
        // overlap from grid-snapping pushing tiles later than musical time
        let lastTargetTime = state.laneLastTargetTime.max() ?? state.songElapsedTime
        state.loopTimeOffset = lastTargetTime + state.songData.tileSnapGridUnitSeconds

        state.nextNoteIndex = 0
        state.loopCount += 1
    }
}
