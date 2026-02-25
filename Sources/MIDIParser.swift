import Foundation

enum MIDIParserError: Error, LocalizedError {
    case invalidHeader
    case smpteNotSupported
    case unexpectedEnd
    case invalidTrackHeader

    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Invalid MIDI header"
        case .smpteNotSupported: return "SMPTE time division not supported"
        case .unexpectedEnd: return "Unexpected end of data"
        case .invalidTrackHeader: return "Invalid track header"
        }
    }
}

enum MIDIParser {

    // MARK: - Public API

    static func parse(data: Data, title: String, composer: String) throws -> SongData {
        var reader = DataReader(data: data)

        // --- Header chunk ---
        let headerID = try reader.readASCII(4)
        guard headerID == "MThd" else { throw MIDIParserError.invalidHeader }

        let headerLen = try reader.readUInt32BE()
        guard headerLen >= 6 else { throw MIDIParserError.invalidHeader }

        let format = try reader.readUInt16BE()
        let trackCount = try reader.readUInt16BE()
        let division = try reader.readUInt16BE()

        // Skip any extra header bytes
        if headerLen > 6 {
            try reader.skip(Int(headerLen - 6))
        }

        // Reject SMPTE
        guard division & 0x8000 == 0 else { throw MIDIParserError.smpteNotSupported }
        let ppqn = Double(division)

        // --- Parse all tracks ---
        var allNoteOns: [(channel: UInt8, note: UInt8, startTick: UInt64, endTick: UInt64)] = []
        var tempoChanges: [(tick: UInt64, microsecondsPerBeat: UInt32)] = []

        for _ in 0..<Int(trackCount) {
            let trackID = try reader.readASCII(4)
            guard trackID == "MTrk" else { throw MIDIParserError.invalidTrackHeader }

            let trackLen = try reader.readUInt32BE()
            let trackEnd = reader.offset + Int(trackLen)

            var absoluteTick: UInt64 = 0
            var runningStatus: UInt8 = 0
            // pendingNotes: key = (channel, note) → startTick
            var pendingNotes: [UInt16: UInt64] = [:]

            while reader.offset < trackEnd {
                let delta = try reader.readVLQ()
                absoluteTick += delta

                var statusByte = try reader.readUInt8()

                // Handle running status
                if statusByte < 0x80 {
                    reader.offset -= 1
                    statusByte = runningStatus
                }

                let highNibble = statusByte & 0xF0

                switch highNibble {
                case 0x80: // Note Off
                    runningStatus = statusByte
                    let channel = statusByte & 0x0F
                    let note = try reader.readUInt8()
                    _ = try reader.readUInt8() // velocity
                    let key = UInt16(channel) << 8 | UInt16(note)
                    if let startTick = pendingNotes.removeValue(forKey: key) {
                        allNoteOns.append((channel, note, startTick, absoluteTick))
                    }

                case 0x90: // Note On
                    runningStatus = statusByte
                    let channel = statusByte & 0x0F
                    let note = try reader.readUInt8()
                    let velocity = try reader.readUInt8()
                    let key = UInt16(channel) << 8 | UInt16(note)
                    if velocity == 0 {
                        // Note On with velocity 0 == Note Off
                        if let startTick = pendingNotes.removeValue(forKey: key) {
                            allNoteOns.append((channel, note, startTick, absoluteTick))
                        }
                    } else {
                        pendingNotes[key] = absoluteTick
                    }

                case 0xA0: // Aftertouch
                    runningStatus = statusByte
                    try reader.skip(2)

                case 0xB0: // Control Change
                    runningStatus = statusByte
                    try reader.skip(2)

                case 0xC0: // Program Change
                    runningStatus = statusByte
                    try reader.skip(1)

                case 0xD0: // Channel Pressure
                    runningStatus = statusByte
                    try reader.skip(1)

                case 0xE0: // Pitch Bend
                    runningStatus = statusByte
                    try reader.skip(2)

                case 0xF0: // System messages
                    if statusByte == 0xFF {
                        // Meta event
                        let metaType = try reader.readUInt8()
                        let metaLen = try reader.readVLQ()
                        if metaType == 0x51 && metaLen == 3 {
                            // Set Tempo
                            let b1 = UInt32(try reader.readUInt8())
                            let b2 = UInt32(try reader.readUInt8())
                            let b3 = UInt32(try reader.readUInt8())
                            let uspb = (b1 << 16) | (b2 << 8) | b3
                            tempoChanges.append((absoluteTick, uspb))
                        } else {
                            try reader.skip(Int(metaLen))
                        }
                    } else if statusByte == 0xF0 || statusByte == 0xF7 {
                        // SysEx
                        let sysexLen = try reader.readVLQ()
                        try reader.skip(Int(sysexLen))
                    } else {
                        // Other system messages — skip
                        break
                    }

                default:
                    break
                }
            }

            // Force-end any dangling pending notes
            for (key, startTick) in pendingNotes {
                let channel = UInt8(key >> 8)
                let note = UInt8(key & 0xFF)
                allNoteOns.append((channel, note, startTick, absoluteTick))
            }

            // Make sure we end at the right spot
            reader.offset = trackEnd
        }

        // --- Filter out channel 9 (percussion) ---
        allNoteOns.removeAll { $0.channel == 9 }

        guard !allNoteOns.isEmpty else {
            return SongData(title: title, composer: composer, bpm: 120, notes: [], fallSpeed: Constants.fallSpeed)
        }

        // --- Determine BPM (use tempo covering the most ticks) ---
        let bpm: Double
        if tempoChanges.isEmpty {
            bpm = 120.0
        } else if tempoChanges.count == 1 {
            bpm = 60_000_000.0 / Double(tempoChanges[0].microsecondsPerBeat)
        } else {
            let lastTick = allNoteOns.map(\.endTick).max() ?? 0
            var maxDuration: UInt64 = 0
            var dominantTempo = tempoChanges[0].microsecondsPerBeat
            for i in 0..<tempoChanges.count {
                let start = tempoChanges[i].tick
                let end = i + 1 < tempoChanges.count ? tempoChanges[i + 1].tick : lastTick
                let duration = end > start ? end - start : 0
                if duration > maxDuration {
                    maxDuration = duration
                    dominantTempo = tempoChanges[i].microsecondsPerBeat
                }
            }
            bpm = 60_000_000.0 / Double(dominantTempo)
        }

        // --- Convert ticks to beats ---
        // Sort by start tick, then by note
        let sorted = allNoteOns.sorted {
            if $0.startTick != $1.startTick { return $0.startTick < $1.startTick }
            return $0.note > $1.note
        }

        var notes: [NoteEvent] = []
        var lastStartBeat = -Double.infinity

        for raw in sorted {
            let startBeat = Double(raw.startTick) / ppqn
            let durationBeats = max(Double(raw.endTick - raw.startTick) / ppqn, 0.1)

            // Deduplication: skip only truly simultaneous notes (chords)
            if startBeat < lastStartBeat + 0.02 {
                continue
            }

            // Truncate previous note's duration if it overlaps with this note
            if let last = notes.last, last.startBeat + last.durationBeats > startBeat {
                let truncated = max(startBeat - last.startBeat, 0.1)
                notes[notes.count - 1] = NoteEvent(
                    midiNote: last.midiNote,
                    startBeat: last.startBeat,
                    durationBeats: truncated,
                    lane: 0
                )
            }

            notes.append(NoteEvent(
                midiNote: raw.note,
                startBeat: startBeat,
                durationBeats: durationBeats,
                lane: 0
            ))
            lastStartBeat = startBeat
        }

        // Gameplay-driven lane assignment
        notes = LaneAssigner.assignLanes(to: notes)
        notes = LaneAssigner.resolveHoldConflicts(notes, bpm: bpm)

        let speed = SongData.adaptiveFallSpeed(notes: notes, bpm: bpm)
        return SongData(title: title, composer: composer, bpm: bpm, notes: notes, fallSpeed: speed)
    }
}

// MARK: - DataReader

private struct DataReader {
    let data: Data
    var offset: Int = 0

    var remaining: Int { data.count - offset }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw MIDIParserError.unexpectedEnd }
        let val = data[offset]
        offset += 1
        return val
    }

    mutating func readUInt16BE() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw MIDIParserError.unexpectedEnd }
        let val = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2
        return val
    }

    mutating func readUInt32BE() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw MIDIParserError.unexpectedEnd }
        let val = UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
        offset += 4
        return val
    }

    mutating func readVLQ() throws -> UInt64 {
        var result: UInt64 = 0
        for _ in 0..<4 {
            let byte = try readUInt8()
            result = (result << 7) | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 { return result }
        }
        return result
    }

    mutating func readASCII(_ count: Int) throws -> String {
        guard offset + count <= data.count else { throw MIDIParserError.unexpectedEnd }
        let bytes = data[offset..<(offset + count)]
        offset += count
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    mutating func skip(_ count: Int) throws {
        guard offset + count <= data.count else { throw MIDIParserError.unexpectedEnd }
        offset += count
    }
}
