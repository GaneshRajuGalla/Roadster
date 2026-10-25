import SwiftUI

struct MenuView: View {
    @Bindable var session: GameSession
    let onPlay: () -> Void

    @AppStorage("Roadster.sound") private var soundEnabled = true
    @AppStorage("Roadster.haptics") private var hapticsEnabled = true
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        bestBadge
                        Spacer()
                        settings
                    }

                    Spacer().frame(height: 16)

                    VStack(spacing: 8) {
                        Text("NEON CITY FLIGHT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(5)
                            .foregroundStyle(.white.opacity(0.55))

                        Text("FIVE SECONDS OF THRUST. ZERO TRAFFIC LAWS.")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.7), radius: 6, y: 1)

                        Text("ROADSTER")
                            .font(
                                .system(
                                    size: min(
                                        96,
                                        max(
                                            54,
                                            min(
                                                geo.size.width * 0.155,
                                                geo.size.height * 0.19
                                            )
                                        )
                                    ),
                                    weight: .black,
                                    design: .rounded
                                )
                            )
                            .tracking(3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .pink, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .cyan.opacity(0.55), radius: 24)
                    }

                    Spacer(minLength: 20)

                    playButton
                        .scaleEffect(pulse ? 1.025 : 1)
                        .animation(
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                            value: pulse
                        )

                    Text("DRAG TO FLY   ·   HOLD BOOST   ·   TAP FLIP")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.top, 16)
                        .multilineTextAlignment(.center)

                    Text("An original fan-fiction flyer. Not affiliated with any vehicle manufacturer.")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 22)
                .padding(.top, geo.safeAreaInsets.top + 8)
                .padding(.bottom, geo.safeAreaInsets.bottom + 10)
            }
        }
        .onAppear { pulse = true }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.78), location: 0.0),
                    .init(color: .black.opacity(0.18), location: 0.32),
                    .init(color: .black.opacity(0.06), location: 0.58),
                    .init(color: .black.opacity(0.84), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [.cyan.opacity(0.13), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [.black.opacity(0.26), .clear],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    private var bestBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
            Text("BEST")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
            Text("\(session.bestScore)")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.32), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Best score \(session.bestScore)")
    }

    private var settings: some View {
        HStack(spacing: 8) {
            settingsButton(
                icon: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                active: soundEnabled,
                label: soundEnabled ? "Mute sound" : "Enable sound"
            ) {
                soundEnabled.toggle()
                if !soundEnabled {
                    AudioEngine.shared.stopEngine()
                }
            }

            settingsButton(
                icon: "iphone.radiowaves.left.and.right",
                active: hapticsEnabled,
                label: hapticsEnabled ? "Disable haptics" : "Enable haptics"
            ) {
                hapticsEnabled.toggle()
            }
        }
    }

    private func settingsButton(
        icon: String,
        active: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? .cyan : .white.opacity(0.35))
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.32), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .black))
                Text("TAP TO FLY")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .tracking(1.5)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 38)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.cyan, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .cyan.opacity(0.45), radius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start flight")
    }
}
