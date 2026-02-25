import Foundation

struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z = z ^ (z >> 31)
        return z
    }
}

enum LaneAssigner {
    static func computeSeed(from notes: [NoteEvent]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let count = min(notes.count, 64)
        for i in 0..<count {
            let note = notes[i]
            hash ^= UInt64(note.midiNote)
            hash &*= 0x100000001b3
            hash ^= note.startBeat.bitPattern
            hash &*= 0x100000001b3
        }
        return hash
    }

    static func assignLanes(to notes: [NoteEvent], seed: UInt64? = nil) -> [NoteEvent] {
        guard !notes.isEmpty else { return notes }

        let effectiveSeed = seed ?? computeSeed(from: notes)
        var rng = SeededRandomNumberGenerator(seed: effectiveSeed)
        let laneCount = Constants.laneCount

        var recentLanes: [Int] = []
        var result: [NoteEvent] = []

        for note in notes {
            var weights = Array(repeating: 1.0, count: laneCount)

            if recentLanes.count >= 1 {
                weights[recentLanes[recentLanes.count - 1]] = 0.05
            }
            if recentLanes.count >= 2 {
                weights[recentLanes[recentLanes.count - 2]] = 0.2
            }
            if recentLanes.count >= 3 {
                weights[recentLanes[recentLanes.count - 3]] = 0.5
            }

            let totalWeight = weights.reduce(0, +)
            var r = Double.random(in: 0..<totalWeight, using: &rng)
            var selectedLane = 0
            for i in 0..<laneCount {
                r -= weights[i]
                if r <= 0 {
                    selectedLane = i
                    break
                }
            }

            result.append(NoteEvent(
                midiNote: note.midiNote,
                startBeat: note.startBeat,
                durationBeats: note.durationBeats,
                lane: selectedLane
            ))

            recentLanes.append(selectedLane)
            if recentLanes.count > 3 {
                recentLanes.removeFirst()
            }
        }

        return result
    }

    static func resolveHoldConflicts(_ notes: [NoteEvent], bpm: Double) -> [NoteEvent] {
        var result = notes

        for i in 0..<result.count {
            let note = result[i]
            guard note.durationBeats > Constants.holdBeatThreshold else { continue }

            let holdEndBeat = note.startBeat + note.durationBeats

            for j in (i + 1)..<result.count {
                guard result[j].startBeat < holdEndBeat else { break }
                if result[j].lane == note.lane {
                    let alt = (note.lane + 2) % Constants.laneCount
                    result[j] = NoteEvent(
                        midiNote: result[j].midiNote,
                        startBeat: result[j].startBeat,
                        durationBeats: result[j].durationBeats,
                        lane: alt
                    )
                }
            }
        }

        return result
    }
}
