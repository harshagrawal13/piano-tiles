import SwiftUI

enum GamePhase {
    case songSelection
    case playing
    case gameOver
}

enum GameOverReason {
    case missed
    case wrongLane
    case songComplete
}

@Observable
@MainActor
final class GameState {
    var phase: GamePhase = .songSelection
    let statsStore = SongStatsStore()
    var lastSongDescriptor: SongDescriptor?
    var score: Int = 0
    var combo: Int = 0
    var maxCombo: Int = 0
    var perfectCount: Int = 0
    var goodCount: Int = 0
    var okCount: Int = 0
    var gameOverReason: GameOverReason = .missed
    var songComplete: Bool = false

    // Song time starts negative for the 5-second grace period
    var songElapsedTime: Double = 0
    var tiles: [Tile] = []
    var nextNoteIndex: Int = 0
    var laneLastTargetTime: [Double] = Array(repeating: -Double.infinity, count: Constants.laneCount)
    var lastSpawnedLane: Int = -1

    // Fail animation state
    var failAnimationStart: Double?
    var failedTileIdx: Int?
    var failReason: GameOverReason = .missed
    var isFailing: Bool { failAnimationStart != nil }

    var screenSize: CGSize = CGSize(width: 390, height: 844)

    var songData: SongData = ChopinNocturne.createSongData()
    let audioEngine = AudioEngine()

    var hitZoneY: CGFloat {
        screenSize.height * Constants.hitZoneRatio
    }

    /// Countdown seconds remaining (0 means playing)
    var countdownRemaining: Int {
        if songElapsedTime >= 0 { return 0 }
        return Int(ceil(-songElapsedTime))
    }

    var isInCountdown: Bool {
        songElapsedTime < 0
    }

    var currentSpeedMultiplier: Double {
        guard songElapsedTime > 0 else { return 1.0 }
        let intervals = floor(songElapsedTime / Constants.speedIncreaseInterval)
        return 1.0 + intervals * Constants.speedIncreaseStep
    }

    func startGame() {
        phase = .playing
        score = 0
        combo = 0
        maxCombo = 0
        perfectCount = 0
        goodCount = 0
        okCount = 0
        songComplete = false
        songElapsedTime = -Constants.startDelay
        tiles = []
        nextNoteIndex = 0
        laneLastTargetTime = Array(repeating: -Double.infinity, count: Constants.laneCount)
        lastSpawnedLane = -1
        failAnimationStart = nil
        failedTileIdx = nil
        failReason = .missed
        audioEngine.start()
    }

    func startFailAnimation(tileIdx: Int, reason: GameOverReason) {
        guard !isFailing else { return }
        failAnimationStart = songElapsedTime
        failedTileIdx = tileIdx
        failReason = reason
        audioEngine.playBuzzer()
    }

    func endGame(reason: GameOverReason) {
        guard phase == .playing else { return }

        gameOverReason = reason
        songComplete = reason == .songComplete
        phase = .gameOver
        if let descriptor = lastSongDescriptor {
            statsStore.recordPlay(songID: descriptor.id, score: score)
        }
        if reason == .songComplete {
            audioEngine.stop()
        } else {
            audioEngine.playFailureJingleAndStop()
        }
    }

    func returnToMenu() {
        phase = .songSelection
    }

    func selectSong(_ descriptor: SongDescriptor) {
        if let data = SongCatalog.loadSong(descriptor) {
            songData = data
            lastSongDescriptor = descriptor
            startGame()
        }
    }

    func addScore(points: Int) {
        combo += 1
        if combo > maxCombo { maxCombo = combo }
        let multiplier = min(combo / 10 + 1, 5)
        score += points * multiplier
    }
}
