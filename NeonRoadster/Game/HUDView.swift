import SwiftUI

struct HUDView: View {
    @Bindable var session: GameSession
    let onMenu: () -> Void

    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            let wide = geo.size.width > 560

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        scorePanel(compactBoost: isPortrait)
                        Spacer(minLength: 8)
                        if wide {
                            progressPanel
                                .padding(.top, 4)
                        }
                        Spacer(minLength: 8)
                        menuButton
                    }

                    if !wide {
                        progressPanel
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 0)

                    if !isPortrait {
                        boostPanel
                            .padding(.bottom, 10)
                    }
                }
                .padding(.leading, geo.safeAreaInsets.leading + 14)
                .padding(.trailing, geo.safeAreaInsets.trailing + 14)
                .padding(.top, geo.safeAreaInsets.top + 8)
                .padding(.bottom, geo.safeAreaInsets.bottom + 8)

                comboBadge
                    .padding(.top, geo.safeAreaInsets.top + (isPortrait ? 148 : 84))
            }
        }
    }

    // MARK: - Score

    private func scorePanel(compactBoost: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SCORE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.cyan.opacity(0.75))

            Text("\(session.hud.score)")
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: session.hud.score)

            HStack(spacing: 12) {
                stat(
                    value: "\(Int(session.hud.speedKmh))",
                    unit: "KM/H",
                    icon: "speedometer"
                )
                stat(
                    value: "\(Int(session.hud.altitude))",
                    unit: "ALT",
                    icon: "arrow.up"
                )
                stat(
                    value: "\(session.hud.rings)",
                    unit: "RINGS",
                    icon: "circle.circle"
                )
            }

            if compactBoost {
                HStack(spacing: 5) {
                    Text("N₂")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(session.hud.boosting ? .cyan : .white.opacity(0.4))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule()
                                .fill(
                                    session.hud.boosting
                                        ? LinearGradient(
                                            colors: [.white, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        : LinearGradient(
                                            colors: [.cyan, .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                                .frame(width: max(0, geo.size.width * CGFloat(session.hud.boost)))
                        }
                    }
                    .frame(width: 120, height: 4)
                    Text(session.hud.boost <= 0.005 ? "REFILL" : String(format: "%.1fs", session.hud.boost * 5))
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(session.hud.boost <= 0.005 ? .orange : .white.opacity(0.45))
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(.cyan.opacity(0.22), lineWidth: 1)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Score \(session.hud.score), speed \(Int(session.hud.speedKmh)) kilometres per hour, altitude \(Int(session.hud.altitude)) metres, \(session.hud.rings) rings"
        )
    }

    private func stat(value: String, unit: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
            Text(unit)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
        }
    }

    // MARK: - Progress

    private var progressPanel: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("THE LOOP")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("2028")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(.pink.opacity(0.85))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(session.hud.progress)))
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .shadow(color: .cyan, radius: 5)
                        .offset(x: max(0, geo.size.width * CGFloat(session.hud.progress) - 3))
                }
            }
            .frame(height: 5)
        }
        .frame(width: 190)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.3), in: Capsule())
        .allowsHitTesting(false)
        .accessibilityLabel("Course progress \(Int(session.hud.progress * 100)) percent")
    }

    // MARK: - Combo

    @ViewBuilder
    private var comboBadge: some View {
        if session.hud.combo > 1 {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .black))
                Text("×\(session.hud.combo)")
                    .font(.system(size: 17, weight: .black, design: .monospaced))
                Text("COMBO")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [.yellow, .orange, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: .orange.opacity(0.5), radius: 12)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: session.hud.combo)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Boost

    private var boostPanel: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text("N₂ BOOST")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(session.hud.boosting ? .cyan : .white.opacity(0.45))
                Spacer()
                Text(boostLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(session.hud.boost > 0.005 ? .cyan : .orange)
                if !session.hud.fanSaveAvailable {
                    Text("FAN SAVE USED")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let threshold = Float(index) / 5.0
                    let filled = session.hud.boost > threshold + 0.001
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            filled
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: session.hud.boosting
                                            ? [.white, .cyan]
                                            : [.cyan, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                : AnyShapeStyle(.white.opacity(0.1))
                        )
                        .frame(height: 6)
                }
            }
        }
        .frame(width: 220)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(session.hud.boosting ? .cyan.opacity(0.5) : .white.opacity(0.07), lineWidth: 1)
        )
        .allowsHitTesting(false)
        .accessibilityLabel("Boost \(Int(session.hud.boost * 100)) percent")
    }

    private var boostLabel: String {
        if session.hud.boost <= 0.005 { return "REFILLING" }
        if session.hud.boosting { return "THRUST" }
        return String(format: "%.1fs", session.hud.boost * 5)
    }

    // MARK: - Menu

    private var menuButton: some View {
        Button(action: onMenu) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.38), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pause and open menu")
    }
}
