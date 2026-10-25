import SwiftUI
import UIKit

struct ResultsView: View {
    @Bindable var session: GameSession
    let onRetry: () -> Void
    let onMenu: () -> Void

    @State private var shareURL: URL?
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let usableHeight = max(
                0,
                geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 24
            )

            ZStack {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 14) {
                            header
                            gradeRow
                            statsGrid
                            quote
                            actions
                        }
                        .padding(20)
                        .frame(maxWidth: 520)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(red: 0.035, green: 0.035, blue: 0.06).opacity(0.96))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(
                                    LinearGradient(
                                        colors: [.cyan.opacity(0.45), .pink.opacity(0.45)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                        .padding(.horizontal, 16)
                        .scaleEffect(appeared ? 1 : 0.96)
                        .opacity(appeared ? 1 : 0)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: usableHeight)
                    .padding(.top, geo.safeAreaInsets.top + 12)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                appeared = true
            }
            renderShareCard()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("FLIGHT LOG // 2028")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.45))
            Text(session.resultTitle)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private var gradeRow: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.35))
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.cyan, .pink, .orange, .cyan],
                            center: .center
                        ),
                        lineWidth: 3
                    )
                Text(session.grade)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 2) {
                Text("SCORE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.45))
                Text("\(session.score)")
                    .font(.system(size: 36, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("BEST \(max(session.bestScore, session.score))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            stat("RINGS", "\(session.ringsCollected)", icon: "circle.circle")
            stat("NEAR MISSES", "\(session.nearMisses)", icon: "wind")
            stat("FLIPS", "\(session.flips)", icon: "arrow.triangle.2.circlepath")
            stat("TOP SPEED", "\(session.topSpeedKmh) KM/H", icon: "speedometer")
            stat("BEST COMBO", "×\(session.bestComboCount)", icon: "flame.fill")
            stat("DISTANCE", "\(session.distanceMeters) M", icon: "road.lanes")
        }
    }

    private func stat(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.cyan.opacity(0.7))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.38))
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var quote: some View {
        Text("“\(session.resultLine)”")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .italic()
            .foregroundStyle(.white.opacity(0.62))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    private var actions: some View {
        VStack(spacing: 9) {
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("RETRY")
                }
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.cyan, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: .cyan.opacity(0.35), radius: 14)
            }
            .buttonStyle(.plain)

            HStack(spacing: 9) {
                if let shareURL {
                    let preview = UIImage(contentsOfFile: shareURL.path)
                        .map { Image(uiImage: $0) }
                        ?? Image(systemName: "car.side.fill")
                    ShareLink(
                        item: shareURL,
                        preview: SharePreview("ROADSTER score", image: preview)
                    ) {
                        shareLabel
                    }
                } else {
                    ShareLink(item: "I scored \(session.score) in ROADSTER. Five seconds of thrust. Zero traffic laws.") {
                        shareLabel
                    }
                }

                Button(action: onMenu) {
                    Text("MENU")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shareLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.and.arrow.up")
            Text("SHARE")
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .tracking(1)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(.cyan.opacity(0.25), lineWidth: 1))
    }

    @MainActor
    private func renderShareCard() {
        let data = ShareCardData(
            score: session.score,
            grade: session.grade,
            rings: session.ringsCollected,
            nearMisses: session.nearMisses,
            flips: session.flips,
            topSpeed: session.topSpeedKmh,
            bestCombo: session.bestComboCount,
            distance: session.distanceMeters,
            resultTitle: session.resultTitle,
            resultLine: session.resultLine
        )
        let renderer = ImageRenderer(content: ShareCardView(data: data))
        renderer.scale = 3
        guard let image = renderer.uiImage, let png = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadster-score-\(data.score).png")
        do {
            try png.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            shareURL = nil
        }
    }
}

private struct ShareCardData {
    let score: Int
    let grade: String
    let rings: Int
    let nearMisses: Int
    let flips: Int
    let topSpeed: Int
    let bestCombo: Int
    let distance: Int
    let resultTitle: String
    let resultLine: String
}

private struct ShareCardView: View {
    let data: ShareCardData

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.025, blue: 0.06),
                    Color(red: 0.1, green: 0.02, blue: 0.16),
                    Color(red: 0.03, green: 0.01, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let horizon = size.height * 0.72
                var path = Path()
                for index in 0..<12 {
                    let t = CGFloat(index) / 11
                    let y = horizon + pow(t, 1.7) * (size.height - horizon)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                for index in 0..<11 {
                    let x = CGFloat(index) / 10 * size.width
                    path.move(to: CGPoint(x: size.width * 0.5, y: horizon))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(.cyan.opacity(0.16)), lineWidth: 1)
            }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ROADSTER")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .pink, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("FLIGHT LOG // 2028")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Text("NEON CITY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.cyan.opacity(0.6))
                }

                Spacer().frame(height: 22)

                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.cyan, .pink, .orange, .cyan],
                                    center: .center
                                ),
                                lineWidth: 3
                            )
                        Text(data.grade)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.resultTitle)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(data.score)")
                            .font(.system(size: 48, weight: .black, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("SCORE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }

                Spacer().frame(height: 18)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 7),
                        GridItem(.flexible(), spacing: 7)
                    ],
                    spacing: 7
                ) {
                    cardStat("RINGS", "\(data.rings)")
                    cardStat("NEAR MISSES", "\(data.nearMisses)")
                    cardStat("FLIPS", "\(data.flips)")
                    cardStat("TOP SPEED", "\(data.topSpeed) KM/H")
                    cardStat("BEST COMBO", "×\(data.bestCombo)")
                    cardStat("DISTANCE", "\(data.distance) M")
                }

                Spacer().frame(height: 16)

                Text("“\(data.resultLine)”")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .italic()
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 10)

                Image("ShareCar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.55), .pink.opacity(0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: .cyan.opacity(0.18), radius: 18)

                Spacer(minLength: 8)

                HStack {
                    Text("FIVE SECONDS OF THRUST.")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text("ZERO TRAFFIC LAWS.")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.pink.opacity(0.55))
                }
            }
            .padding(22)
        }
        .frame(width: 360, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [.cyan.opacity(0.5), .pink.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }

    private func cardStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
