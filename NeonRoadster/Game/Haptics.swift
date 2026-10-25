import CoreHaptics
import UIKit

/// Small, battery-friendly haptic layer. Falls back to UIKit impact
/// generators on devices without Core Haptics.
@MainActor
enum Haptics {
    private static var engine: CHHapticEngine?
    private static var didPrepare = false

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "Roadster.haptics") as? Bool ?? true
    }

    private static func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let newEngine = try CHHapticEngine()
            newEngine.playsHapticsOnly = true
            newEngine.isAutoShutdownEnabled = true
            newEngine.resetHandler = { [weak newEngine] in
                try? newEngine?.start()
            }
            try newEngine.start()
            engine = newEngine
        } catch {
            engine = nil
        }
    }

    private static func transient(
        intensity: Float,
        sharpness: Float,
        delay: TimeInterval = 0
    ) {
        guard enabled else { return }
        prepare()
        if let engine {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: intensity),
                    .init(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: delay
            )
            if let pattern = try? CHHapticPattern(events: [event], parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: 0)
                return
            }
        }
        let generator = UIImpactFeedbackGenerator(style: intensity > 0.7 ? .heavy : .medium)
        generator.impactOccurred(intensity: CGFloat(intensity))
    }

    static func ring(perfect: Bool) {
        transient(intensity: perfect ? 0.85 : 0.5, sharpness: perfect ? 0.7 : 0.45)
        if perfect {
            transient(intensity: 0.55, sharpness: 0.8, delay: 0.06)
        }
    }

    static func nearMiss() {
        transient(intensity: 0.35, sharpness: 0.8)
        transient(intensity: 0.25, sharpness: 0.6, delay: 0.05)
    }

    static func boost() {
        transient(intensity: 0.4, sharpness: 0.3)
    }

    static func crash() {
        transient(intensity: 1.0, sharpness: 0.9)
        transient(intensity: 0.7, sharpness: 0.4, delay: 0.09)
    }

    static func fanSave() {
        transient(intensity: 0.6, sharpness: 0.5)
        transient(intensity: 0.8, sharpness: 0.8, delay: 0.07)
    }

    static func flip() {
        transient(intensity: 0.55, sharpness: 0.75)
    }
}
