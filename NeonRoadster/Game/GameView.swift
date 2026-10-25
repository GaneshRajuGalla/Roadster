import RealityKit
import SwiftUI
import UIKit
import simd

/// Owns the RealityKit scene graph and advances the simulation from the
/// renderer's update event. A fixed timestep keeps the flight model stable
/// even when the renderer drops frames.
@MainActor
final class GameWorld {
    let root = Entity()
    let session: GameSession
    let camera = PerspectiveCamera()
    private(set) var city: City
    private(set) var roadster: RoadsterModel

    private var subscription: EventSubscription?
    private var accumulator: Float = 0
    private let fixedStep: Float = 1.0 / 120.0
    private var visualTime: Float = 0
    private var lastPhase: GameSession.Phase = .menu
    private var snapCamera = true

    private var cameraPosition = SIMD3<Float>(0, 0, 0)
    private var cameraOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var currentFOV: Float = 54

    private let autopilot: Bool
    private let crashDemo: Bool
    private let isPad = UIDevice.current.userInterfaceIdiom == .pad
    private var demoClock: Float = 0
    private var crashDemoClock: Float = 0
    private var wasBoosting = false
    private var loggedMenuCar = false

    /// Landscape uses a narrower vertical field of view at the same horizontal
    /// FOV, so the camera pulls back to keep the car from filling the screen.
    var landscape = false

    init(
        session: GameSession,
        autopilot: Bool = false,
        crashDemo: Bool = false,
        landscape: Bool = false
    ) {
        self.session = session
        self.autopilot = autopilot
        self.crashDemo = crashDemo
        self.landscape = landscape
        self.city = CityBuilder.build()
        self.roadster = RoadsterFactory.make()

        root.name = "World"
        root.addChild(city.root)
        root.addChild(roadster.root)

        if let roads = city.root.children.first(where: { $0.name == "Roads" }) {
            NSLog("ROADSTER: roads bounds %@", String(describing: roads.visualBounds(relativeTo: nil)))
        }
        for child in city.root.children {
            NSLog("CITY: %@ bounds %@", child.name, String(describing: child.visualBounds(relativeTo: nil)))
        }

        camera.name = "ChaseCam"
        camera.camera = PerspectiveCameraComponent(
            near: 0.3,
            far: 1_400,
            fieldOfViewInDegrees: 54,
            fieldOfViewOrientation: .horizontal
        )
        root.addChild(camera)

        let sun = DirectionalLight()
        sun.name = "SunsetKey"
        sun.light.color = UIColor(red: 1.0, green: 0.70, blue: 0.44, alpha: 1)
        sun.light.intensity = 16_000
        sun.orientation = simd_quatf(from: [0, 0, -1], to: -CityBuilder.sunDirection)
        root.addChild(sun)

        let skyFill = DirectionalLight()
        skyFill.name = "SkyFill"
        skyFill.light.color = UIColor(red: 0.55, green: 0.70, blue: 0.95, alpha: 1)
        skyFill.light.intensity = 1_800
        skyFill.orientation = simd_quatf(angle: -.pi / 2.6, axis: [1, 0, 0])
        root.addChild(skyFill)

        // The chase camera looks at the car's rear, which faces away from the
        // key light. A soft warm rear fill keeps the tail panel white instead
        // of leaving it as a dark silhouette.
        let rearFill = DirectionalLight()
        rearFill.name = "RearFill"
        rearFill.light.color = UIColor(red: 1.0, green: 0.82, blue: 0.68, alpha: 1)
        rearFill.light.intensity = 2_600
        rearFill.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        root.addChild(rearFill)

        let horizonFill = DirectionalLight()
        horizonFill.name = "HorizonFill"
        horizonFill.light.color = UIColor(red: 1.0, green: 0.58, blue: 0.38, alpha: 1)
        horizonFill.light.intensity = 1_400
        horizonFill.orientation = simd_quatf(
            from: [0, 0, -1],
            to: -SIMD3<Float>(-0.9, 0.1, 0.2)
        )
        root.addChild(horizonFill)

        // Neutral side fills keep the white body white without turning its
        // flanks the color of the sunset.
        for angle in [Float.pi / 2.8, -Float.pi / 2.8] {
            let side = DirectionalLight()
            side.name = "SideFill"
            side.light.color = UIColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            side.light.intensity = 1_600
            side.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
                * simd_quatf(angle: -.pi / 6, axis: [1, 0, 0])
            root.addChild(side)
        }

        resetCourse()
        updateVisuals(dt: 0)
    }

    func attach(to content: RealityViewCameraContent) {
        // Strong capture is intentional: the subscription is owned by the
        // renderer, and the world must stay alive for the whole scene.
        subscription = content.subscribe(to: SceneEvents.Update.self) { event in
            self.updateFrame(dt: Float(event.deltaTime))
        }
    }

    // MARK: - Frame loop

    private func updateFrame(dt rawDt: Float) {
        let dt = min(max(rawDt, 0), 0.25)
        visualTime += dt

        switch session.phase {
        case .playing:
            accumulator += dt
            var steps = 0
            while accumulator >= fixedStep && steps < 8 {
                if autopilot {
                    updateAutopilot(dt: fixedStep)
                }
                session.tick(dt: fixedStep)
                guard session.phase == .playing else { break }

                if crashDemo {
                    crashDemoClock += fixedStep
                    if crashDemoClock > 3.0 {
                        crashDemoClock = 0
                        session.crash(.traffic)
                        guard session.phase == .playing else { break }
                    }
                }

                updateTraffic(dt: fixedStep)
                checkRings()
                checkTrafficCollisions()
                accumulator -= fixedStep
                steps += 1
            }
            if steps == 8 { accumulator = 0 }

        case .crashing:
            session.tick(dt: dt)

        case .menu, .finished:
            session.tick(dt: dt)
        }

        if session.phase == .playing && lastPhase != .playing {
            resetCourse()
            snapCamera = true
            AudioEngine.shared.startEngine()
        }
        if session.phase != .playing && lastPhase == .playing {
            AudioEngine.shared.stopEngine()
        }
        if session.phase == .finished && lastPhase != .finished {
            AudioEngine.shared.finish()
        }
        lastPhase = session.phase

        updateVisuals(dt: dt)

        let boosting = session.input.boost && session.boost > 0.005
        if boosting != wasBoosting {
            wasBoosting = boosting
            AudioEngine.shared.setBoost(boosting)
            if boosting { Haptics.boost() }
        }
        AudioEngine.shared.setSpeed(session.speed, boosting: boosting)
    }

    // MARK: - Traffic, rings, collisions

    private func updateTraffic(dt: Float) {
        for index in city.traffic.indices {
            var traffic = city.traffic[index]
            traffic.distance += traffic.speed * dt
            if traffic.distance > CityBuilder.finishDistance - 30 {
                traffic.distance = 120
            }
            if traffic.distance < 60 {
                traffic.distance = CityBuilder.finishDistance - 120
            }
            let frame = FlightPath.frame(at: traffic.distance)
            let direction = traffic.speed >= 0 ? frame.forward : -frame.forward
            traffic.entity.position = frame.offset(
                lateral: traffic.lateral,
                vertical: traffic.vertical
            )
            traffic.entity.orientation = simd_quatf(from: [0, 0, 1], to: direction)
            city.traffic[index] = traffic
        }
    }

    private func checkRings() {
        let carPosition = session.position
        for index in city.rings.indices {
            var ring = city.rings[index]
            guard !ring.collected else { continue }
            let distance = simd_length(carPosition - ring.entity.position)
            guard distance < ring.radius + 1.45 else { continue }
            ring.collected = true
            ring.entity.isEnabled = false
            city.rings[index] = ring
            let perfect = distance < 2.6
            session.collectRing(perfect: perfect)
            AudioEngine.shared.ring(perfect: perfect)
            Haptics.ring(perfect: perfect)
        }
    }

    private func checkTrafficCollisions() {
        guard session.phase == .playing, session.invulnerable <= 0 else { return }
        let carPosition = session.position

        for index in city.traffic.indices {
            var traffic = city.traffic[index]
            let distance = simd_length(carPosition - traffic.entity.position)

            if distance < traffic.radius + 1.35 {
                session.crash(.traffic)
                if session.phase == .playing {
                    // Fan save: shove the car out of the obstacle and let it
                    // keep flying, with a brief window of invulnerability.
                    let side: Float = session.lateral >= traffic.lateral ? 1 : -1
                    session.lateral = min(
                        FlightPath.corridorHalfWidth,
                        max(-FlightPath.corridorHalfWidth, session.lateral + side * 3.6)
                    )
                    session.lateralVelocity = side * 7
                    AudioEngine.shared.fanSave()
                    Haptics.fanSave()
                } else {
                    AudioEngine.shared.crash()
                    Haptics.crash()
                }
                break
            }

            if distance < 9.0 && !traffic.nearMissed {
                traffic.nearMissed = true
                city.traffic[index] = traffic
                session.nearMiss()
                AudioEngine.shared.nearMiss()
                Haptics.nearMiss()
            }
        }
    }

    // MARK: - Autopilot (debug / capture)

    private func updateAutopilot(dt: Float) {
        demoClock += dt
        var target: Ring?
        for ring in city.rings where !ring.collected && ring.distance > session.distance - 15 {
            if target == nil || ring.distance < target!.distance {
                target = ring
            }
        }

        guard let target else {
            session.input.steer = .zero
            session.input.boost = false
            return
        }

        let lateralError = target.lateral - session.lateral
        let verticalError = target.vertical - session.vertical
        session.input.steer = SIMD2<Float>(
            max(-1, min(1, lateralError / 11)),
            max(-1, min(1, verticalError / 9))
        )
        session.input.boost = session.boost > 0.4 && (target.distance - session.distance) > 90

        if demoClock > 9 {
            demoClock = 0
            session.input.flipRequested = true
        }
    }

    // MARK: - Visuals

    private func updateVisuals(dt: Float) {
        let frame = FlightPath.frame(at: session.distance)
        let carPosition = session.position
        let base = simd_quatf(from: [0, 0, 1], to: frame.forward)

        let pitch = simd_quatf(angle: -session.pitchVisual, axis: [1, 0, 0])
        let bank = simd_quatf(angle: session.bank, axis: [0, 0, 1])
        let flip = simd_quatf(angle: session.flipAngle, axis: [0, 0, 1])

        var carOrientation = base * pitch * bank * flip
        var carPositionFinal = carPosition

        switch session.phase {
        case .menu:
            city.root.isEnabled = true
            city.haze.isEnabled = true
            carPositionFinal.y += sin(visualTime * 1.15) * 0.14
            carOrientation = base * simd_quatf(angle: sin(visualTime * 0.6) * 0.03, axis: [0, 0, 1])
        case .crashing:
            let tumble = simd_quatf(angle: session.crashTimer * 6.0, axis: [0, 0, 1])
                * simd_quatf(angle: session.crashTimer * 3.4, axis: [1, 0, 0])
            carOrientation = base * tumble
            carPositionFinal.y += sin(session.crashTimer * 9) * 0.6
        case .finished:
            carPositionFinal.y += sin(visualTime * 1.2) * 0.08
        case .playing:
            break
        }

        roadster.root.position = carPositionFinal
        roadster.root.orientation = carOrientation
        if session.phase == .menu && !loggedMenuCar {
            loggedMenuCar = true
            NSLog("ROADSTER: car root %@", String(describing: carPositionFinal))
        }

        let boosting = session.input.boost && session.boost > 0.005
        let plumeBlend = dt <= 0 ? 1 : (1 - exp(-11 * dt))
        let targetRadius: Float = boosting ? 0.85 : 0.42
        let targetLength: Float = boosting ? 1.15 : 0.42
        let radius = roadster.plume.scale.x + (targetRadius - roadster.plume.scale.x) * plumeBlend
        let length = roadster.plume.scale.y + (targetLength - roadster.plume.scale.y) * plumeBlend
        roadster.plume.scale = [radius, length, radius]
        roadster.plume.isEnabled = session.phase == .playing || session.phase == .menu

        let fanPulse = 1 + sin(visualTime * 9) * 0.06
        roadster.fanGlow.scale = [fanPulse, 1, fanPulse]
        roadster.fanGlow.isEnabled = session.phase == .playing || session.phase == .menu

        updateAmbientTraffic(dt: dt)
        updateRingPulse()
        updateCamera(dt: dt, carPosition: carPositionFinal, frame: frame)
        updateAtmosphere()
    }

    private func updateAmbientTraffic(dt: Float) {
        for index in city.ambientTraffic.indices {
            var traffic = city.ambientTraffic[index]
            traffic.distance += traffic.speed * dt
            if traffic.distance > FlightPath.length {
                traffic.distance = 0
            }
            let frame = FlightPath.frame(at: traffic.distance)
            traffic.entity.position = frame.offset(
                lateral: traffic.lateral,
                vertical: traffic.vertical
            )
            traffic.entity.orientation = simd_quatf(
                from: [0, 0, 1],
                to: frame.forward
            )
            city.ambientTraffic[index] = traffic
        }
    }

    private func updateRingPulse() {
        for index in city.rings.indices where !city.rings[index].collected {
            let ring = city.rings[index]
            let pulse = 1 + sin(visualTime * 2.2 + ring.distance * 0.012) * 0.026
            ring.entity.scale = [pulse, pulse, pulse]
        }
    }

    private func updateAtmosphere() {
        let forward = cameraOrientation.act([0, 0, -1])
        city.sun.position = cameraPosition + CityBuilder.sunDirection * 2_200
        city.haze.position = cameraPosition + forward * 900
    }

    /// Level-horizon look rotation. The shortest-arc `simd_quatf(from:to:)`
    /// can introduce roll as the path curves, which reads as the whole city
    /// tilting. A proper basis keeps the horizon stable.
    private func lookRotation(from position: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let forward = simd_normalize(target - position)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var right = simd_cross(worldUp, -forward)
        if simd_length(right) < 0.001 {
            right = SIMD3<Float>(1, 0, 0)
        }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(-forward, right))
        let basis = simd_float3x3(columns: (right, up, -forward))
        return simd_quatf(basis)
    }

    private func updateCamera(dt: Float, carPosition: SIMD3<Float>, frame: PathFrame) {
        let desiredPosition: SIMD3<Float>
        let target: SIMD3<Float>
        let blendSpeed: Float

        switch session.phase {
        case .playing:
            let distance: Float = landscape ? (isPad ? 11.5 : 13.5) : 5.6
            let height: Float = landscape ? (isPad ? 3.2 : 3.6) : 1.9
            let lookAhead: Float = landscape ? (isPad ? 15 : 17) : 12
            desiredPosition = carPosition - frame.forward * distance + frame.up * height
            target = carPosition + frame.forward * lookAhead + frame.up * 1.0
            blendSpeed = 10
        case .menu:
            let radius: Float = landscape ? (isPad ? 13.5 : 20) : 9.5
            let height: Float = landscape ? (isPad ? 5.8 : 5.6) : 4.4
            let targetY: Float = landscape ? (isPad ? 1.0 : 0.1) : 1.0
            // Stay behind and to the side of the car so the skyline and the
            // low sun are in frame instead of the empty start of the course.
            let angle = visualTime * 0.10 + 2.35
            desiredPosition = carPosition + SIMD3<Float>(
                sin(angle) * radius,
                height,
                cos(angle) * radius
            )
            target = carPosition + SIMD3<Float>(0, targetY, 0)
            blendSpeed = 3
        case .crashing:
            let radius: Float = landscape ? 14.5 : 11
            let angle = session.crashTimer * 2.2
            desiredPosition = carPosition + SIMD3<Float>(
                sin(angle) * radius,
                5.2 + session.crashTimer * 1.6,
                cos(angle) * radius
            )
            target = carPosition
            blendSpeed = 5
        case .finished:
            let radius: Float = landscape ? 13.5 : 10.5
            let height: Float = landscape ? 5.6 : 4.6
            let angle = visualTime * 0.32
            desiredPosition = carPosition + SIMD3<Float>(
                sin(angle) * radius,
                height,
                cos(angle) * radius
            )
            target = carPosition + SIMD3<Float>(0, 1.0, 0)
            blendSpeed = 3
        }

        let blend = (snapCamera || dt <= 0) ? 1 : (1 - exp(-blendSpeed * dt))
        cameraPosition += (desiredPosition - cameraPosition) * blend
        snapCamera = false

        var shake = SIMD3<Float>.zero
        if session.phase == .playing && session.input.boost && session.boost > 0.005 {
            shake = SIMD3<Float>(
                sin(visualTime * 47) * 0.035,
                cos(visualTime * 39) * 0.03,
                sin(visualTime * 53) * 0.025
            )
        } else if session.phase == .crashing {
            shake = SIMD3<Float>(
                sin(visualTime * 61) * 0.08,
                cos(visualTime * 47) * 0.06,
                sin(visualTime * 71) * 0.05
            )
        }

        let shakenPosition = cameraPosition + shake
        camera.position = shakenPosition
        let look = lookRotation(from: shakenPosition, to: target)
        let cameraBank = session.phase == .playing ? session.bank * 0.10 : 0
        cameraOrientation = look * simd_quatf(angle: -cameraBank, axis: [0, 0, 1])
        camera.orientation = cameraOrientation

        let targetFOV: Float
        if session.phase == .playing && session.input.boost && session.boost > 0.005 {
            targetFOV = landscape ? 72 : 62
        } else if session.phase == .crashing {
            targetFOV = landscape ? 56 : 48
        } else {
            targetFOV = landscape ? 62 : 52
        }
        let fovBlend = dt <= 0 ? 1 : (1 - exp(-6 * dt))
        currentFOV += (targetFOV - currentFOV) * fovBlend
        var component = camera.camera
        component.fieldOfViewInDegrees = currentFOV
        camera.camera = component
    }

    // MARK: - Course reset

    private func resetCourse() {
        for index in city.rings.indices {
            city.rings[index].collected = false
            city.rings[index].entity.isEnabled = true
        }

        for index in city.traffic.indices {
            var traffic = city.traffic[index]
            traffic.distance = traffic.initialDistance
            traffic.nearMissed = false
            let frame = FlightPath.frame(at: traffic.distance)
            traffic.entity.position = frame.offset(
                lateral: traffic.lateral,
                vertical: traffic.vertical
            )
            city.traffic[index] = traffic
        }

        accumulator = 0
        crashDemoClock = 0
        lastPhase = .menu
        snapCamera = true
    }
}

/// Holds the scene world outside SwiftUI state so the view can tell it about
/// aspect-ratio changes without recreating the RealityKit content.
@MainActor
final class WorldHolder {
    var world: GameWorld?
}

struct GameView: View {
    let session: GameSession
    @State private var holder = WorldHolder()

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            RealityView { content in
                content.camera = .virtual
                content.renderingEffects.motionBlur = .disabled
                content.renderingEffects.depthOfField = .disabled
                content.renderingEffects.cameraGrain = .disabled
                content.renderingEffects.antialiasing = .multisample4X

                let world = GameWorld(
                    session: session,
                    autopilot: ProcessInfo.processInfo.arguments.contains("-demo"),
                    crashDemo: ProcessInfo.processInfo.arguments.contains("-crashdemo"),
                    landscape: isLandscape
                )
                holder.world = world
                content.add(world.root)
                if let sky = world.city.sky {
                    content.environment = .skybox(sky)
                }
                world.attach(to: content)
            }
            .onChange(of: geo.size) { _, size in
                holder.world?.landscape = size.width > size.height
            }
        }
        .ignoresSafeArea()
    }
}
