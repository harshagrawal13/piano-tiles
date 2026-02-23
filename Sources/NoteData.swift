import Foundation

struct NoteEvent: Sendable {
    let midiNote: UInt8
    let startBeat: Double
    let durationBeats: Double
    let lane: Int
}

struct SongData: Sendable {
    let title: String
    let composer: String
    let bpm: Double
    let notes: [NoteEvent]

    var totalDuration: Double {
        guard let last = notes.last else { return 0 }
        return (last.startBeat + last.durationBeats) * 60.0 / bpm
    }
}

enum ChopinNocturne {
    static func createSongData() -> SongData {
        let bpm: Double = 140

        let rawNotes: [(midi: UInt8, start: Double, dur: Double)] = [
            // Bar 1-2: Opening melody (Bb4 repeated, gentle)
            (70, 0.0, 2.0),    // Bb4
            (70, 2.0, 1.0),    // Bb4
            (72, 3.0, 1.0),    // C5
            (74, 4.0, 2.0),    // D5
            (72, 6.0, 1.0),    // C5
            (70, 7.0, 1.0),    // Bb4

            // Bar 3-4
            (74, 8.0, 2.0),    // D5
            (75, 10.0, 1.0),   // Eb5
            (77, 11.0, 1.0),   // F5
            (79, 12.0, 2.0),   // G5
            (77, 14.0, 1.0),   // F5
            (75, 15.0, 1.0),   // Eb5

            // Bar 5-6: Rising phrase
            (70, 16.0, 1.5),   // Bb4
            (72, 17.5, 0.5),   // C5
            (74, 18.0, 1.0),   // D5
            (75, 19.0, 1.0),   // Eb5
            (77, 20.0, 2.0),   // F5
            (75, 22.0, 1.0),   // Eb5
            (74, 23.0, 1.0),   // D5

            // Bar 7-8: Descending
            (72, 24.0, 2.0),   // C5
            (70, 26.0, 1.0),   // Bb4
            (68, 27.0, 1.0),   // Ab4
            (70, 28.0, 2.0),   // Bb4
            (67, 30.0, 1.0),   // G4
            (65, 31.0, 1.0),   // F4

            // Bar 9-10: Second theme
            (63, 32.0, 2.0),   // Eb4
            (65, 34.0, 1.0),   // F4
            (67, 35.0, 1.0),   // G4
            (70, 36.0, 2.0),   // Bb4
            (68, 38.0, 1.0),   // Ab4
            (67, 39.0, 1.0),   // G4

            // Bar 11-12
            (65, 40.0, 1.5),   // F4
            (67, 41.5, 0.5),   // G4
            (68, 42.0, 1.0),   // Ab4
            (70, 43.0, 1.0),   // Bb4
            (72, 44.0, 2.0),   // C5
            (70, 46.0, 1.0),   // Bb4
            (68, 47.0, 1.0),   // Ab4

            // Bar 13-14: Climax building
            (75, 48.0, 2.0),   // Eb5
            (77, 50.0, 1.0),   // F5
            (79, 51.0, 1.0),   // G5
            (82, 52.0, 2.0),   // Bb5
            (79, 54.0, 1.0),   // G5
            (77, 55.0, 1.0),   // F5

            // Bar 15-16
            (75, 56.0, 1.5),   // Eb5
            (74, 57.5, 0.5),   // D5
            (72, 58.0, 1.0),   // C5
            (70, 59.0, 1.0),   // Bb4
            (68, 60.0, 2.0),   // Ab4
            (70, 62.0, 1.0),   // Bb4
            (72, 63.0, 1.0),   // C5

            // Bar 17-18: Ornamented reprise
            (74, 64.0, 1.0),   // D5
            (75, 65.0, 0.5),   // Eb5
            (74, 65.5, 0.5),   // D5
            (72, 66.0, 1.0),   // C5
            (70, 67.0, 1.0),   // Bb4
            (74, 68.0, 2.0),   // D5
            (72, 70.0, 1.0),   // C5
            (70, 71.0, 1.0),   // Bb4

            // Bar 19-20
            (67, 72.0, 2.0),   // G4
            (70, 74.0, 1.0),   // Bb4
            (74, 75.0, 1.0),   // D5
            (77, 76.0, 2.0),   // F5
            (75, 78.0, 1.0),   // Eb5
            (74, 79.0, 1.0),   // D5

            // Bar 21-22: Final descent
            (72, 80.0, 1.5),   // C5
            (74, 81.5, 0.5),   // D5
            (75, 82.0, 1.0),   // Eb5
            (72, 83.0, 1.0),   // C5
            (70, 84.0, 2.0),   // Bb4
            (68, 86.0, 1.0),   // Ab4
            (67, 87.0, 1.0),   // G4

            // Bar 23-24: Closing
            (65, 88.0, 2.0),   // F4
            (67, 90.0, 1.0),   // G4
            (68, 91.0, 1.0),   // Ab4
            (70, 92.0, 3.0),   // Bb4
            (70, 95.0, 1.0),   // Bb4 (final)
        ]

        let notes = rawNotes.map { raw in
            NoteEvent(
                midiNote: raw.midi,
                startBeat: raw.start,
                durationBeats: raw.dur,
                lane: assignLane(midiNote: raw.midi)
            )
        }

        return SongData(
            title: "Nocturne Op. 9 No. 2",
            composer: "Chopin",
            bpm: bpm,
            notes: notes
        )
    }

    private static func assignLane(midiNote: UInt8) -> Int {
        // Range: ~63 (Eb4) to ~82 (Bb5)
        // Split into 4 lanes by pitch range
        switch midiNote {
        case 0...65:    return 0  // Low: Eb4, F4
        case 66...70:   return 1  // Mid-low: G4, Ab4, Bb4
        case 71...75:   return 2  // Mid-high: C5, D5, Eb5
        default:        return 3  // High: F5, G5, Bb5
        }
    }
}
