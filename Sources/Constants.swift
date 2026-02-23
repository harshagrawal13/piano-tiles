import SwiftUI

enum Constants {
    static let laneCount = 4
    static let tileHeight: CGFloat = 140

    // Hit zone near bottom — matches Piano Tiles 2
    static let hitZoneRatio: CGFloat = 0.88
    static let hitTolerance: CGFloat = 130
    static let tapYSlack: CGFloat = 20
    static let tappedTileOpacity: Double = 0.30
    static let tapFlashDuration: Double = 0.14
    static let tapOutlineWidth: CGFloat = 2.5
    static let tapOutlineCornerRadius: CGFloat = 10

    static let lookAheadSeconds: Double = 4.0
    static let fallSpeed: CGFloat = 280
    static let tileSnapGridUnitTiles: CGFloat = 1.0
    static var tileSnapGridUnitSeconds: Double {
        Double(tileHeight * tileSnapGridUnitTiles) / Double(fallSpeed)
    }

    // 3-second countdown before first tile arrives (3, 2, 1)
    static let startDelay: Double = 3.0

    // Fail animation
    static let failAnimationDuration: Double = 2.0
    static let failExpandAmount: CGFloat = 15.0

    // Speed increase every 15 seconds
    static let speedIncreaseInterval: Double = 15.0
    static let speedIncreaseStep: Double = 0.1

    // Tile colors
    static let tileBlack = Color.black
    static let tileTapped = Color(white: 0.35)
    static let tileMissed = Color(red: 1.0, green: 0.36, blue: 0.36)  // #FF5D5D

    // Score
    static let scoreText = Color.orange

    // Lane dividers — white at 20% opacity
    static let laneDivider = Color.white.opacity(0.20)

    // Pastel gradient stops
    static let bgPink = Color(red: 0.97, green: 0.72, blue: 0.84)       // #F7B7D7
    static let bgLavender = Color(red: 0.79, green: 0.73, blue: 1.0)    // #C9B9FF
    static let bgSkyBlue = Color(red: 0.66, green: 0.85, blue: 1.0)     // #A8D9FF

    // Button
    static let buttonBlue = Color(red: 0.33, green: 0.66, blue: 0.90)   // #55A8E5

    /// The pastel gradient used across all screens
    static let pastelGradient = LinearGradient(
        colors: [bgPink, bgLavender, bgSkyBlue],
        startPoint: .top,
        endPoint: .bottom
    )
}
