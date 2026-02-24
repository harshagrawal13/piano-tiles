import SwiftUI

struct GameView: View {
    @Bindable var state: GameState
    @State private var lastUpdateTime: Date?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        drawGame(context: context, size: size, now: timeline.date)
                    }
                    .onChange(of: timeline.date) { _, newDate in
                        updateGameLoop(now: newDate)
                    }
                }

                TouchOverlayView(
                    laneCount: Constants.laneCount,
                    onTouchDown: { lane, touchY in
                        TileEngine.handleTouchDown(lane: lane, touchY: touchY, state: state)
                    },
                    onTouchUp: { lane in
                        TileEngine.handleTouchUp(lane: lane, state: state)
                    }
                )
            }
            .onAppear {
                state.screenSize = geo.size
            }
            .onChange(of: geo.size) { _, newSize in
                state.screenSize = newSize
            }
        }
        .ignoresSafeArea()
    }

    private func updateGameLoop(now: Date) {
        guard state.phase == .playing else {
            lastUpdateTime = nil
            return
        }

        guard let last = lastUpdateTime else {
            lastUpdateTime = now
            return
        }

        let dt = now.timeIntervalSince(last)
        lastUpdateTime = now

        let clampedDt = min(dt, 0.05)

        // During fail animation, advance at normal speed and wait for animation to finish
        if let failStart = state.failAnimationStart {
            state.songElapsedTime += clampedDt
            if state.songElapsedTime - failStart >= Constants.failAnimationDuration {
                state.endGame(reason: state.failReason)
            }
            return
        }

        // Apply speed multiplier after countdown
        if state.isInCountdown {
            state.songElapsedTime += clampedDt
        } else {
            state.songElapsedTime += clampedDt * state.currentSpeedMultiplier
        }

        if !state.isInCountdown {
            TileEngine.spawnUpcomingTiles(state: state)
            TileEngine.updateTiles(state: state)
            TileEngine.checkSongComplete(state: state)
        }
    }

    // MARK: - Drawing

    private func drawGame(context: GraphicsContext, size: CGSize, now: Date) {
        let laneWidth = size.width / CGFloat(Constants.laneCount)
        let hitY = size.height * Constants.hitZoneRatio

        // 1. Pastel gradient background
        let gradientRect = CGRect(origin: .zero, size: size)
        let gradient = Gradient(colors: [
            Color(red: 0.97, green: 0.72, blue: 0.84),
            Color(red: 0.79, green: 0.73, blue: 1.0),
            Color(red: 0.66, green: 0.85, blue: 1.0)
        ])
        context.fill(
            Path(gradientRect),
            with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )

        // 2. Bokeh circles
        drawBokeh(context: context, size: size)

        // 3. Lane dividers (white at 20% opacity)
        for lane in 1..<Constants.laneCount {
            let lx = CGFloat(lane) * laneWidth
            var path = Path()
            path.move(to: CGPoint(x: lx, y: 0))
            path.addLine(to: CGPoint(x: lx, y: size.height))
            context.stroke(path, with: .color(Constants.laneDivider), lineWidth: 1)
        }

        // 4. Tiles
        drawTiles(context: context, size: size, laneWidth: laneWidth, hitY: hitY)

        // 5. Score (large orange, top center)
        drawHUD(context: context, size: size)

        // 6. Countdown overlay
        drawCountdown(context: context, size: size)
    }

    private func drawBokeh(context: GraphicsContext, size: CGSize) {
        // Fixed bokeh circle positions (deterministic, seeded by screen size)
        let bokehData: [(cx: CGFloat, cy: CGFloat, r: CGFloat, color: Color, opacity: Double)] = [
            (0.15, 0.10, 50, Color(red: 0.97, green: 0.72, blue: 0.84), 0.18),
            (0.80, 0.08, 35, Color(red: 0.79, green: 0.73, blue: 1.0), 0.15),
            (0.60, 0.25, 60, Color(red: 0.66, green: 0.85, blue: 1.0), 0.12),
            (0.25, 0.40, 40, Color(red: 0.97, green: 0.72, blue: 0.84), 0.14),
            (0.85, 0.55, 55, Color(red: 0.79, green: 0.73, blue: 1.0), 0.16),
            (0.10, 0.70, 45, Color(red: 0.66, green: 0.85, blue: 1.0), 0.13),
            (0.50, 0.80, 38, Color(red: 0.97, green: 0.72, blue: 0.84), 0.15),
            (0.70, 0.90, 50, Color(red: 0.79, green: 0.73, blue: 1.0), 0.12),
        ]

        for b in bokehData {
            let center = CGPoint(x: b.cx * size.width, y: b.cy * size.height)
            let circle = Path(ellipseIn: CGRect(x: center.x - b.r, y: center.y - b.r,
                                                 width: b.r * 2, height: b.r * 2))
            var blurCtx = context
            blurCtx.addFilter(.blur(radius: 20))
            blurCtx.fill(circle, with: .color(b.color.opacity(b.opacity)))
        }
    }

    private func drawTiles(context: GraphicsContext, size: CGSize,
                            laneWidth: CGFloat, hitY: CGFloat) {
        guard !state.isInCountdown else { return }
        let separatorW: CGFloat = 0.5  // thin white separator effect

        for tile in state.tiles {
            let tileH = tile.visualHeight
            let x = CGFloat(tile.lane) * laneWidth
            let topY = tile.yPosition - tileH

            guard topY < size.height + tileH && tile.yPosition > -tileH else { continue }

            let tileRect = CGRect(x: x + separatorW, y: topY + separatorW,
                                  width: laneWidth - separatorW * 2, height: tileH - separatorW * 2)

            switch tile.state {
            case .falling:
                context.fill(Path(tileRect), with: .color(Constants.tileBlack))

            case .tapped:
                context.fill(Path(tileRect),
                           with: .color(Constants.tileTapped.opacity(Constants.tappedTileOpacity)))
                if let tappedAt = tile.tappedTime {
                    let elapsed = state.songElapsedTime - tappedAt
                    if elapsed < Constants.tapFlashDuration {
                        let life = max(0.0, 1.0 - elapsed / Constants.tapFlashDuration)
                        let outlinePath = Path(
                            roundedRect: tileRect.insetBy(dx: 1.5, dy: 1.5),
                            cornerRadius: Constants.tapOutlineCornerRadius
                        )
                        context.stroke(
                            outlinePath,
                            with: .color(.white.opacity(0.9 * life)),
                            lineWidth: Constants.tapOutlineWidth
                        )
                    }
                }

            case .missed:
                context.fill(Path(tileRect), with: .color(Constants.tileMissed))

            case .failed:
                if let failStart = state.failAnimationStart {
                    let elapsed = state.songElapsedTime - failStart
                    // Ease-out expansion over 0.3s, then hold
                    let t = min(1.0, elapsed / 0.3)
                    let eased = 1.0 - (1.0 - t) * (1.0 - t)
                    let expand = Constants.failExpandAmount * CGFloat(eased)
                    let expandedRect = CGRect(
                        x: tileRect.minX,
                        y: tileRect.minY - expand,
                        width: tileRect.width,
                        height: tileRect.height + expand * 2
                    )
                    context.fill(Path(expandedRect), with: .color(Constants.tileMissed))
                }
            }
        }
    }

    private func drawHUD(context: GraphicsContext, size: CGSize) {
        // Large orange score at top center with drop shadow
        let scoreY = size.height * 0.08

        // Shadow
        context.draw(
            Text("\(state.score)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.18)),
            at: CGPoint(x: size.width / 2 + 1, y: scoreY + 2)
        )

        // Score
        context.draw(
            Text("\(state.score)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(Constants.scoreText),
            at: CGPoint(x: size.width / 2, y: scoreY)
        )

        // Combo
        if state.combo > 2 {
            context.draw(
                Text("\(state.combo)x")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: size.width / 2, y: scoreY + 32)
            )
        }
    }

    private func drawCountdown(context: GraphicsContext, size: CGSize) {
        guard state.isInCountdown else { return }

        let remaining = state.countdownRemaining
        let text = "\(remaining)"

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color.black.opacity(0.15))
        )

        let countdownY = size.height * 0.45

        // Shadow
        context.draw(
            Text(text)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.15)),
            at: CGPoint(x: size.width / 2 + 1, y: countdownY + 2)
        )

        context.draw(
            Text(text)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.white),
            at: CGPoint(x: size.width / 2, y: countdownY)
        )
    }
}
