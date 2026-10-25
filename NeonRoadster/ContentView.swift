import SwiftUI

struct ContentView: View {
    @State private var session = GameSession()
    @State private var showMenu = !ProcessInfo.processInfo.arguments.contains("-autostart")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            GameView(session: session)
                .ignoresSafeArea()

            if !showMenu && session.phase != .finished {
                HUDView(session: session) {
                    session.reset()
                    showMenu = true
                }
                .transition(.opacity)
            }

            if !showMenu && session.phase == .playing {
                TouchControlsView(session: session)
                    .transition(.opacity)
            }

            if showMenu {
                MenuView(session: session) {
                    showMenu = false
                    session.start()
                }
                .transition(.opacity)
            }

            if session.phase == .finished && !showMenu {
                ResultsView(
                    session: session,
                    onRetry: {
                        session.start()
                    },
                    onMenu: {
                        session.reset()
                        showMenu = true
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: showMenu)
        .animation(.easeInOut(duration: 0.24), value: session.phase)
        .statusBarHidden(true)
        .modifier(PhoneImmersiveModifier())
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if session.phase == .playing {
                    AudioEngine.shared.startEngine()
                }
            case .inactive, .background:
                session.input.boost = false
                session.input.steer = .zero
                AudioEngine.shared.stopEngine()
            @unknown default:
                break
            }
        }
        .task {
            if !showMenu {
                session.start()
            }
        }
    }
}

private struct PhoneImmersiveModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            content.persistentSystemOverlays(.hidden)
        } else {
            content
        }
    }
}
