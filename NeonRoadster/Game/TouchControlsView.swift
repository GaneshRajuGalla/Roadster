import SwiftUI
import simd

struct TouchControlsView: View {
    @Bindable var session: GameSession

    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width

            ZStack {
                VStack(spacing: 7) {
                    Spacer()
                    Text("DRAG TO FLY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.35))
                    SteeringPad(session: session)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, geo.safeAreaInsets.leading + 18)
                .padding(.bottom, geo.safeAreaInsets.bottom + 14)

                VStack(spacing: 12) {
                    Spacer()
                    FlipButton(session: session)
                    BoostButton(session: session)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, geo.safeAreaInsets.trailing + 18)
                .padding(.bottom, geo.safeAreaInsets.bottom + 14)
            }
            .padding(.bottom, isPortrait ? 4 : 0)
        }
        .onDisappear {
            session.input.steer = .zero
            session.input.boost = false
        }
    }
}

private struct SteeringPad: View {
    @Bindable var session: GameSession
    @State private var knobOffset: CGSize = .zero
    @State private var isActive = false

    private let size: CGFloat = 150
    private let radius: CGFloat = 52
    private let knobSize: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.3))
                .overlay(
                    Circle()
                        .stroke(
                            isActive ? .cyan.opacity(0.55) : .white.opacity(0.14),
                            lineWidth: 1.5
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            .white.opacity(0.06),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 7])
                        )
                        .padding(18)
                )

            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.15))

            Circle()
                .fill(
                    LinearGradient(
                        colors: isActive ? [.cyan, .pink] : [.cyan.opacity(0.7), .blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: knobSize, height: knobSize)
                .overlay(
                    Circle().stroke(.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .cyan.opacity(isActive ? 0.6 : 0.2), radius: isActive ? 12 : 5)
                .offset(knobOffset)
                .scaleEffect(isActive ? 1.05 : 1)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    isActive = true
                    let center = CGPoint(x: size * 0.5, y: size * 0.5)
                    var dx = value.location.x - center.x
                    var dy = value.location.y - center.y
                    let distance = sqrt(dx * dx + dy * dy)

                    if distance > radius {
                        let scale = radius / distance
                        dx *= scale
                        dy *= scale
                    }

                    let magnitude = sqrt(dx * dx + dy * dy)
                    if magnitude < 4 {
                        dx = 0
                        dy = 0
                    }

                    knobOffset = CGSize(width: dx, height: dy)
                    session.input.steer = SIMD2<Float>(
                        Float(dx / radius),
                        Float(-dy / radius)
                    )
                }
                .onEnded { _ in
                    isActive = false
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        knobOffset = .zero
                    }
                    session.input.steer = .zero
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Flight steering pad")
        .accessibilityHint("Drag to steer left, right, up, or down")
    }
}

private struct BoostButton: View {
    @Bindable var session: GameSession
    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.42))

            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 5)
                .padding(4)

            Circle()
                .trim(from: 0, to: CGFloat(max(0.001, session.hud.boost)))
                .stroke(
                    AngularGradient(
                        colors: [.cyan, .blue, .pink, .cyan],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)
                .shadow(color: .cyan.opacity(session.hud.boosting ? 0.8 : 0.25), radius: 8)

            Circle()
                .fill(
                    session.hud.boosting
                        ? LinearGradient(
                            colors: [.cyan.opacity(0.55), .blue.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [.white.opacity(0.06), .white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
                .padding(10)

            VStack(spacing: 1) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .black))
                Text(session.hud.boost > 0.005 ? "BOOST" : "REFILL")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1)
            }
            .foregroundStyle(session.hud.boost > 0.005 ? .white : .orange.opacity(0.8))
        }
        .frame(width: 88, height: 88)
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    pressed = true
                    session.input.boost = true
                }
                .onEnded { _ in
                    pressed = false
                    session.input.boost = false
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Boost")
        .accessibilityValue("\(Int(session.hud.boost * 100)) percent")
        .accessibilityHint("Hold to burn the nitrogen tank")
    }
}

private struct FlipButton: View {
    @Bindable var session: GameSession

    var body: some View {
        Button {
            guard session.hud.flipReady else { return }
            session.input.flipRequested = true
            AudioEngine.shared.flip()
            Haptics.flip()
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.42))
                    .overlay(
                        Circle().stroke(
                            session.hud.flipReady ? .pink.opacity(0.55) : .white.opacity(0.1),
                            lineWidth: 1.5
                        )
                    )
                VStack(spacing: 1) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .black))
                    Text("FLIP")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(session.hud.flipReady ? .white : .white.opacity(0.3))
            }
            .frame(width: 62, height: 62)
        }
        .buttonStyle(FlipButtonStyle())
        .disabled(!session.hud.flipReady)
        .accessibilityLabel("Kickflip")
        .accessibilityHint("Tap to spin the car")
    }
}

private struct FlipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
