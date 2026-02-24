import SwiftUI

struct SongPickerView: View {
    @Bindable var state: GameState

    var body: some View {
        ZStack {
            Constants.pastelGradient
                .ignoresSafeArea()

            bokehOverlay

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                    Text("Piano Tiles")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Song list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(SongCatalog.songs) { song in
                            songRow(song)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
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

    private func songRow(_ song: SongDescriptor) -> some View {
        let songStats = state.statsStore.stats(for: song.id)

        return Button(action: { state.selectSong(song) }) {
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.15)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(song.composer)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                if songStats.bestScore > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(songStats.bestScore)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        if let lastPlayed = songStats.lastPlayed {
                            Text(relativeDate(lastPlayed))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.12))
            )
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
