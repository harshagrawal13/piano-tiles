import SwiftUI

struct MenuView: View {
    @Bindable var state: GameState

    var body: some View {
        ZStack {
            // Pastel gradient background
            Constants.pastelGradient
                .ignoresSafeArea()

            // Bokeh circles
            bokehOverlay

            gameOverContent
        }
    }

    private var bokehOverlay: some View {
        Canvas { context, size in
            let circles: [(cx: CGFloat, cy: CGFloat, r: CGFloat, color: Color, op: Double)] = [
                (0.20, 0.15, 60, Constants.bgPink, 0.18),
                (0.75, 0.10, 40, Constants.bgLavender, 0.15),
                (0.55, 0.30, 70, Constants.bgSkyBlue, 0.12),
                (0.30, 0.50, 45, Constants.bgPink, 0.14),
                (0.80, 0.60, 55, Constants.bgLavender, 0.16),
                (0.12, 0.75, 50, Constants.bgSkyBlue, 0.13),
                (0.60, 0.85, 42, Constants.bgPink, 0.15),
            ]
            for c in circles {
                let center = CGPoint(x: c.cx * size.width, y: c.cy * size.height)
                let rect = CGRect(x: center.x - c.r, y: center.y - c.r, width: c.r * 2, height: c.r * 2)
                var blurCtx = context
                blurCtx.addFilter(.blur(radius: 22))
                blurCtx.fill(Path(ellipseIn: rect), with: .color(c.color.opacity(c.op)))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var gameOverContent: some View {
        VStack(spacing: 20) {
            Spacer()

            if state.songComplete {
                Image(systemName: "star.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.4), radius: 10)

                Text("Song Complete!")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.9))

                Text("Game Over")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                Text(state.gameOverReason == .wrongLane ? "Invalid tap!" : "Missed a tile!")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Stats card
            VStack(spacing: 14) {
                statRow(label: "Score", value: "\(state.score)")
                Divider().background(.white.opacity(0.2))
                statRow(label: "Max Combo", value: "\(state.maxCombo)x")
                Divider().background(.white.opacity(0.2))
                statRow(label: "Perfect", value: "\(state.perfectCount)")
                statRow(label: "Good", value: "\(state.goodCount)")
                statRow(label: "OK", value: "\(state.okCount)")
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.15))
            )
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                Button(action: { state.startGame() }) {
                    Text("Retry")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 220, height: 52)
                        .background(
                            Capsule().fill(Constants.buttonBlue)
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        )
                }

                Button(action: { state.returnToMenu() }) {
                    Text("Songs")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 220, height: 44)
                        .background(
                            Capsule().stroke(.white.opacity(0.4), lineWidth: 1.5)
                        )
                }
            }

            Spacer()
                .frame(height: 40)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}
