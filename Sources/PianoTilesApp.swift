import SwiftUI

@main
struct PianoTilesApp: App {
    @State private var gameState = GameState()

    var body: some Scene {
        WindowGroup {
            Group {
                switch gameState.phase {
                case .menu:
                    MenuView(state: gameState)
                case .playing:
                    GameView(state: gameState)
                case .gameOver:
                    MenuView(state: gameState)
                }
            }
            .ignoresSafeArea()
            .statusBarHidden()
        }
    }
}
