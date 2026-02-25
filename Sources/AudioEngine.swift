import AVFoundation
import Foundation
import os

// MARK: - Free‑function envelope

private func computeEnvelope(
    phase: inout Double,
    attackEnd: Double,
    decayTau: Double,
    sustainLevel: Double,
    releaseStart: Double,
    releaseDuration: Double,
    releaseAmplitude: Double,
    sampleRate: Double
) -> Float {
    let t = phase
    phase += 1.0 / sampleRate

    if releaseStart > 0 {
        let elapsed = t - releaseStart
        if elapsed >= releaseDuration { return 0 }
        let frac = elapsed / releaseDuration
        return Float(releaseAmplitude * (1.0 - frac))
    }

    if t < attackEnd {
        return Float(t / attackEnd)
    }

    let decayElapsed = t - attackEnd
    let decayed = (1.0 - sustainLevel) * exp(-decayElapsed / decayTau) + sustainLevel
    return Float(decayed)
}

// MARK: - Voice

private struct Voice {
    var active: Bool = false
    var midiNote: UInt8 = 0
    var frequency: Double = 0
    var phase: Double = 0
    var envelopeTime: Double = 0
    var velocity: Float = 0
    var age: UInt64 = 0
    var releaseStart: Double = 0
    var releaseAmplitude: Float = 0
}

// MARK: - AudioEngine

final class AudioEngine: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var isRunning = false

    private let voiceCount = 8
    private let voiceStorage: UnsafeMutablePointer<Voice>
    private let lockStorage: UnsafeMutablePointer<os_unfair_lock>
    private var ageCounter: UInt64 = 0

    private let sampleRate: Double = 44100
    private let harmonicAmplitudes: [Double] = [1.0, 0.5, 0.25, 0.12, 0.06]
    private let attackDuration: Double = 0.005
    private let decayTau: Double = 0.06
    private let sustainLevel: Double = 0.15
    private let releaseDuration: Double = 0.1

    init() {
        voiceStorage = .allocate(capacity: 8)
        voiceStorage.initialize(repeating: Voice(), count: 8)
        lockStorage = .allocate(capacity: 1)
        lockStorage.initialize(to: os_unfair_lock())
    }

    deinit {
        voiceStorage.deinitialize(count: 8)
        voiceStorage.deallocate()
        lockStorage.deinitialize(count: 1)
        lockStorage.deallocate()
    }

    func start() {
        if let old = engine {
            old.stop()
            if let node = sourceNode { old.detach(node) }
        }

        for i in 0..<voiceCount {
            voiceStorage[i] = Voice()
        }
        ageCounter = 0

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }

        let newEngine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let voices = voiceStorage
        let lock = lockStorage
        let harmonics = harmonicAmplitudes
        let vc = voiceCount
        let sr = sampleRate
        let atkEnd = attackDuration
        let dTau = decayTau
        let susLvl = sustainLevel
        let relDur = releaseDuration

        let node = AVAudioSourceNode(format: format) {
            _, _, frameCount, audioBufferList -> OSStatus in

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            guard let leftBuffer = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuffer = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            for frame in 0..<frames {
                var sample: Float = 0

                os_unfair_lock_lock(lock)
                for v in 0..<vc {
                    guard voices[v].active else { continue }

                    let env = computeEnvelope(
                        phase: &voices[v].envelopeTime,
                        attackEnd: atkEnd,
                        decayTau: dTau,
                        sustainLevel: susLvl,
                        releaseStart: voices[v].releaseStart,
                        releaseDuration: relDur,
                        releaseAmplitude: Double(voices[v].releaseAmplitude),
                        sampleRate: sr
                    )

                    if env <= 0.0001 && voices[v].releaseStart > 0 {
                        voices[v].active = false
                        continue
                    }

                    var tone: Float = 0
                    let basePhase = voices[v].phase
                    for (h, amp) in harmonics.enumerated() {
                        let harmFreq = voices[v].frequency * Double(h + 1)
                        let theta = basePhase * harmFreq * 2.0 * .pi
                        tone += Float(amp * sin(theta))
                    }

                    let harmonicSum: Float = 1.93
                    tone /= harmonicSum

                    sample += tone * env * voices[v].velocity
                    voices[v].phase += 1.0 / sr
                }
                os_unfair_lock_unlock(lock)

                sample *= 0.3
                leftBuffer[frame] = sample
                rightBuffer[frame] = sample
            }

            return noErr
        }

        sourceNode = node
        newEngine.attach(node)
        newEngine.connect(node, to: newEngine.mainMixerNode, format: format)

        do {
            try newEngine.start()
            engine = newEngine
            isRunning = true
        } catch {
            print("Audio engine failed: \(error)")
            isRunning = false
        }
    }

    func stop() {
        engine?.stop()
        isRunning = false
    }

    func playTick() {
        guard isRunning else { return }
        // Short, bright woodblock-like tick using a high note with quick release
        playNote(90, velocity: 80)  // F#6
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.stopNote(90)
        }
    }

    func playBuzzer() {
        guard isRunning else { return }
        playNote(40, velocity: 127)  // E2
        playNote(41, velocity: 127)  // F2 — dissonant semitone pair
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.stopNote(40)
            self?.stopNote(41)
        }
    }

    func playFailureJingleAndStop() {
        guard isRunning else {
            stop()
            return
        }

        let sequence: [(note: UInt8, delay: TimeInterval)] = [
            (76, 0.00),
            (72, 0.10),
            (67, 0.22),
            (60, 0.34)
        ]

        for item in sequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + item.delay) { [weak self] in
                guard let self else { return }
                self.playNote(item.note, velocity: 120)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                    self?.stopNote(item.note)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { [weak self] in
            self?.stop()
        }
    }

    func playNote(_ note: UInt8, velocity: UInt8 = 110) {
        guard isRunning else { return }

        let freq = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        let vel = Float(velocity) / 127.0

        os_unfair_lock_lock(lockStorage)
        defer { os_unfair_lock_unlock(lockStorage) }

        ageCounter += 1

        var idx = -1
        var oldestAge: UInt64 = .max

        for i in 0..<voiceCount {
            if !voiceStorage[i].active {
                idx = i
                break
            }
        }

        if idx == -1 {
            for i in 0..<voiceCount {
                if voiceStorage[i].age < oldestAge {
                    oldestAge = voiceStorage[i].age
                    idx = i
                }
            }
        }

        guard idx >= 0 else { return }

        voiceStorage[idx] = Voice(
            active: true,
            midiNote: note,
            frequency: freq,
            phase: 0,
            envelopeTime: 0,
            velocity: vel,
            age: ageCounter,
            releaseStart: 0,
            releaseAmplitude: 0
        )
    }

    func stopAllNotes() {
        guard isRunning else { return }

        os_unfair_lock_lock(lockStorage)
        defer { os_unfair_lock_unlock(lockStorage) }

        for i in 0..<voiceCount {
            guard voiceStorage[i].active, voiceStorage[i].releaseStart == 0 else { continue }
            voiceStorage[i].releaseStart = voiceStorage[i].envelopeTime
            let t = voiceStorage[i].envelopeTime
            if t < attackDuration {
                voiceStorage[i].releaseAmplitude = Float(t / attackDuration)
            } else {
                let decayElapsed = t - attackDuration
                let decayed = (1.0 - sustainLevel) * exp(-decayElapsed / decayTau) + sustainLevel
                voiceStorage[i].releaseAmplitude = Float(decayed)
            }
        }
    }

    func stopNote(_ note: UInt8) {
        guard isRunning else { return }

        os_unfair_lock_lock(lockStorage)
        defer { os_unfair_lock_unlock(lockStorage) }

        for i in 0..<voiceCount {
            if voiceStorage[i].active &&
                voiceStorage[i].midiNote == note &&
                voiceStorage[i].releaseStart == 0 {
                voiceStorage[i].releaseStart = voiceStorage[i].envelopeTime
                let t = voiceStorage[i].envelopeTime
                if t < attackDuration {
                    voiceStorage[i].releaseAmplitude = Float(t / attackDuration)
                } else {
                    let decayElapsed = t - attackDuration
                    let decayed = (1.0 - sustainLevel) * exp(-decayElapsed / decayTau) + sustainLevel
                    voiceStorage[i].releaseAmplitude = Float(decayed)
                }
            }
        }
    }
}
