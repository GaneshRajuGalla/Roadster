import Foundation
import Observation
import simd

enum CrashCause: String {
    case traffic
    case wall
    case ground
    case finished

    var title: String {
        switch self {
        case .traffic: "TRAFFIC"
        case .wall: "BUILDING"
        case .ground: "GROUND"
        case .finished: "FINISH"
        }
    }

    var line: String {
        switch self {
        case .traffic: "The flight lane was optional, apparently."
        case .wall: "Rapid unscheduled disassembly."
        case .ground: "It's a jumping car."
        case .finished: "2028, actually."
        }
    }
}

@Observable
@MainActor
final class GameSession {
    enum Phase: Equatable {
        case menu
        case playing
        case crashing
        case finished
    }

    struct InputState {
        var steer: SIMD2<Float> = .zero
        var boost = false
        var flipRequested = false
    }

    struct HUD: Equatable {
        var score = 0
        var speedKmh: Float = 0
        var altitude: Float = 0
        var rings = 0
        var boost: Float = 1
        var combo = 1
        var boosting = false
        var progress: Float = 0
        var fanSaveAvailable = true
        var fanSaveFlash: Float = 0
        var flipReady = true
    }

    // Presentation state read by SwiftUI.
    var phase: Phase = .menu
    var hud = HUD()
    var bestScore: Int
    var crashCause: CrashCause = .traffic

    // Simulation state. Deliberately not observable: the HUD reads `hud`,
    // and RealityKit reads these values directly from the update loop.
    @ObservationIgnored var input = InputState()
    @ObservationIgnored var distance: Float = 0
    @ObservationIgnored var lateral: Float = 0
    @ObservationIgnored var vertical: Float = 0
    @ObservationIgnored var lateralVelocity: Float = 0
    @ObservationIgnored var verticalVelocity: Float = 0
    @ObservationIgnored var speed: Float = 55
    @ObservationIgnored var boost: Float = 1
    @ObservationIgnored var elapsed: TimeInterval = 0
    @ObservationIgnored var crashTimer: Float = 0
    @ObservationIgnored var timeScale: Float = 1
    @ObservationIgnored var invulnerable: Float = 0
    @ObservationIgnored var flipProgress: Float = 0
    @ObservationIgnored var flipCooldown: Float = 0
    @ObservationIgnored var ringsCollected = 0
    @ObservationIgnored var nearMisses = 0
    @ObservationIgnored var flips = 0
    @ObservationIgnored var topSpeed: Float = 0
    @ObservationIgnored var fanSaveAvailable = true
    @ObservationIgnored var fanSaveFlash: Float = 0

    @ObservationIgnored private var eventScore = 0
    @ObservationIgnored private var combo = 1
    @ObservationIgnored private var bestCombo = 1
    @ObservationIgnored private var lastEventTime: TimeInterval = 0
    @ObservationIgnored private var hudClock: Float = 0
    @ObservationIgnored private let defaults = UserDefaults.standard

    private let lateralSpeed: Float = 27
    private let verticalSpeed: Float = 21
    private let baseSpeed: Float = 55
    private let boostMultiplier: Float = 1.7

    init() {
        bestScore = UserDefaults.standard.integer(forKey: "Roadster.bestScore")
        reset()
    }

    // MARK: - Lifecycle

    func start() {
        reset()
        phase = .playing
        speed = baseSpeed
        distance = 0
        lateral = 0
        vertical = 0
        boost = 1
        fanSaveAvailable = true
        lastEventTime = 0
        publishHUD(force: true)
    }

    func reset() {
        phase = .menu
        distance = 0
        lateral = 0
        vertical = 0
        lateralVelocity = 0
        verticalVelocity = 0
        speed = baseSpeed
        boost = 1
        elapsed = 0
        crashTimer = 0
        timeScale = 1
        invulnerable = 0
        flipProgress = 0
        flipCooldown = 0
        ringsCollected = 0
        nearMisses = 0
        flips = 0
        topSpeed = 0
        fanSaveAvailable = true
        fanSaveFlash = 0
        eventScore = 0
        combo = 1
        bestCombo = 1
        lastEventTime = 0
        input = InputState()
        hud = HUD()
        publishHUD(force: true)
    }

    // MARK: - Simulation

    func tick(dt rawDt: Float) {
        let rawDt = min(max(rawDt, 0), 1.0 / 20.0)

        if phase == .crashing {
            crashTimer += rawDt
            timeScale = 0.35
            if crashTimer >= 1.35 {
                phase = .finished
                timeScale = 1
                publishHUD(force: true)
            }
            return
        }

        guard phase == .playing else { return }

        let dt = rawDt * timeScale
        elapsed += TimeInterval(dt)
        invulnerable = max(0, invulnerable - dt)
        flipCooldown = max(0, flipCooldown - dt)
        fanSaveFlash = max(0, fanSaveFlash - dt * 2.5)

        // Steering: a single floating pad controls lateral + vertical movement.
        let targetLateral = input.steer.x * lateralSpeed
        let targetVertical = input.steer.y * verticalSpeed
        let lateralBlend = 1 - exp(-9 * dt)
        let verticalBlend = 1 - exp(-8 * dt)
        lateralVelocity += (targetLateral - lateralVelocity) * lateralBlend
        verticalVelocity += (targetVertical - verticalVelocity) * verticalBlend

        lateral += lateralVelocity * dt
        vertical += verticalVelocity * dt

        if abs(lateral) > FlightPath.corridorHalfWidth {
            lateral = min(
                FlightPath.corridorHalfWidth,
                max(-FlightPath.corridorHalfWidth, lateral)
            )
            lateralVelocity = 0
        }
        if abs(vertical) > FlightPath.corridorHalfHeight {
            vertical = min(
                FlightPath.corridorHalfHeight,
                max(-FlightPath.corridorHalfHeight, vertical)
            )
            verticalVelocity = 0
        }

        // Finite nitrogen: exactly 5 seconds of thrust, then a slow refill.
        let wantsBoost = input.boost && boost > 0.005
        if wantsBoost {
            boost = max(0, boost - dt / 5.0)
        } else {
            boost = min(1, boost + dt / 6.0)
        }

        let cruise = baseSpeed + min(20, Float(elapsed) * 0.18)
        let targetSpeed = wantsBoost ? cruise * boostMultiplier : cruise
        speed += (targetSpeed - speed) * (1 - exp(-2.2 * dt))
        topSpeed = max(topSpeed, speed)
        distance += speed * dt

        // Kickflip: one button, one signature trick.
        if input.flipRequested {
            input.flipRequested = false
            if flipCooldown <= 0 && flipProgress == 0 {
                flipProgress = 0.001
                flipCooldown = 1.25
                flips += 1
                eventScore += 500 * combo
                boost = min(1, boost + 0.25)
                combo = min(10, combo + 1)
                bestCombo = max(bestCombo, combo)
                lastEventTime = elapsed
                timeScale = 0.55
            }
        }

        if flipProgress > 0 {
            flipProgress += dt / 0.62
            if flipProgress >= 1 {
                flipProgress = 0
                timeScale = 1
            }
        } else {
            timeScale = 1
        }

        // Combo decays if the player stops doing anything interesting.
        if elapsed - lastEventTime > 5.0 {
            combo = 1
        }

        publishHUD(force: false, dt: dt)

        if distance >= CityBuilder.finishDistance {
            finish()
        }
    }

    // MARK: - Events

    func collectRing(perfect: Bool) {
        guard phase == .playing else { return }
        ringsCollected += 1
        combo = min(10, combo + 1)
        bestCombo = max(bestCombo, combo)
        eventScore += (perfect ? 375 : 250) * combo
        boost = min(1, boost + 0.6)
        lastEventTime = elapsed
    }

    func nearMiss() {
        guard phase == .playing else { return }
        nearMisses += 1
        combo = min(10, combo + 1)
        bestCombo = max(bestCombo, combo)
        eventScore += 100 * combo
        boost = min(1, boost + 0.35)
        lastEventTime = elapsed
    }

    func crash(_ cause: CrashCause) {
        guard phase == .playing else { return }
        if cause == .traffic && attemptFanSave() {
            return
        }
        crashCause = cause
        phase = .crashing
        crashTimer = 0
        timeScale = 0.35
        combo = 1
        saveBest()
        publishHUD(force: true)
    }

    func finish() {
        guard phase == .playing else { return }
        eventScore += 10_000
        crashCause = .finished
        phase = .finished
        timeScale = 1
        saveBest()
        publishHUD(force: true)
    }

    private func attemptFanSave() -> Bool {
        guard fanSaveAvailable, boost > 0.2 else { return false }
        fanSaveAvailable = false
        boost = max(0, boost - 0.25)
        speed *= 0.62
        combo = max(1, combo / 2)
        invulnerable = 1.5
        fanSaveFlash = 1
        lastEventTime = elapsed
        publishHUD(force: true)
        return true
    }

    private func saveBest() {
        if score > bestScore {
            bestScore = score
            defaults.set(bestScore, forKey: "Roadster.bestScore")
        }
    }

    // MARK: - Presentation

    var score: Int {
        eventScore + Int(distance * 0.5)
    }

    var position: SIMD3<Float> {
        FlightPath.worldPoint(at: distance, lateral: lateral, vertical: vertical)
    }

    var forward: SIMD3<Float> {
        FlightPath.frame(at: distance).forward
    }

    var bank: Float {
        -lateralVelocity / lateralSpeed * 0.42
    }

    var pitchVisual: Float {
        verticalVelocity / verticalSpeed * 0.28
    }

    var flipAngle: Float {
        flipProgress * 2 * .pi
    }

    var comboCount: Int { combo }
    var bestComboCount: Int { bestCombo }
    var isFanSaveActive: Bool { fanSaveFlash > 0 }
    var topSpeedKmh: Int { Int(topSpeed * 3.6) }
    var distanceMeters: Int { Int(distance) }
    var resultTitle: String {
        crashCause == .finished ? "COURSE CLEAR" : "DAMAGE REPORT"
    }
    var resultLine: String { crashCause.line }

    var grade: String {
        switch score {
        case 140_000...: return "S+"
        case 95_000...: return "S"
        case 60_000...: return "A"
        case 32_000...: return "B"
        default: return "C"
        }
    }

    private func publishHUD(force: Bool, dt: Float = 0) {
        hudClock += dt
        guard force || hudClock >= 0.1 else { return }
        hudClock = 0
        hud = HUD(
            score: score,
            speedKmh: speed * 3.6,
            altitude: position.y,
            rings: ringsCollected,
            boost: boost,
            combo: combo,
            boosting: input.boost && boost > 0.005,
            progress: min(1, distance / CityBuilder.finishDistance),
            fanSaveAvailable: fanSaveAvailable,
            fanSaveFlash: fanSaveFlash,
            flipReady: flipCooldown <= 0 && flipProgress == 0
        )
    }
}
