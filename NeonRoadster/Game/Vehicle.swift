import Foundation
import simd

struct Trim {
    var mass: Float
    var mu: Float
    var power: Float
    var vmax: Float
    var maxDriveG: Float
    var clA: Float
    var cdA: Float
    var wing: Bool
    var rearThrust: Float
    var liftThrust: Float
    var tank: Float
    var refill: Float
    var perimeter: Bool
    var assistThrust: Float
    var airControl: Float
    var vMax: Float { vmax }
}

struct Wheel {
    var id: String
    var local: SIMD3<Float>
    var front: Bool
    var compression: Float = 0
    var prevCompression: Float = 0
    var contact: Bool = false
    var spin: Float = 0
    var spinRate: Float = 0
    var load: Float = 0
    var slip: Float = 0
    var world: SIMD3<Float> = .zero
    var contactPoint: SIMD3<Float> = .zero
    var onLoop: Float = -1
    var rampS: Float = -1
}

final class Vehicle {
    var trim: Trim
    var mass: Float
    var inertia: SIMD3<Float>
    var tank: Float

    var pos: SIMD3<Float> = .zero
    var vel: SIMD3<Float> = .zero
    var quat: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var angVel: SIMD3<Float> = .zero
    var force: SIMD3<Float> = .zero
    var torque: SIMD3<Float> = .zero

    var cgHeight: Float = 0.5
    var wheelRadius: Float = 0.36
    var restLength: Float = 0.35
    var springK: Float = 76000
    var damperC: Float = 6500
    var wheels: [Wheel] = []

    var steer: Float = 0
    var fanOn: Bool = true
    var wingMode: Int = 0
    var wingAngle: Float = 0
    var wingDeploy: Float = 0
    var thrustLevel: Float = 0
    var liftLevel: Float = 0
    var airborneTime: Float = 0
    var groundedWheels: Int = 0
    var lastImpact: Float = 0
    var flipState: String? = nil
    var flipT: Float = 0
    var flipDir: Float = 1
    var controlTorque: SIMD3<Float> = .zero
    var burstTimer: Float = 0
    var burstTorque: SIMD3<Float> = .zero
    var popTimer: Float = 0
    var flipCtl: SIMD3<Float> = .zero
    var flipSide: SIMD3<Float> = SIMD3<Float>(1, 0, 0)
    var rollBurn: Float = 0
    var rollDone: Float = 0
    var assistForce: SIMD3<Float> = .zero
    var assistLevel: Float = 0
    var assistEnabled: Bool = true
    var autoLift: Float = 0
    var fanLevel: Float = 0.55
    var events: [Any] = []
    var onLoop: Bool = false
    var rampS: Float = -1
    var rampTheta: Float = -1
    var rampFlight: Any? = nil
    var lateralTrim: Float = 0
    var rollSettle: Bool = false
    var flankDir: Float = 0
    var flankHold: Float = 0
    var ultraSpool: Float = 0
    var jumpOnly: Bool = false
    var kickflipTimer: Float = 0
    var flipRoll: Float = 0
    var noCollide: Bool = false

    let G: Float = 9.81
    let RHO: Float = 1.2

    init(trim: Trim) {
        self.trim = trim
        self.mass = trim.mass
        let m = trim.mass
        self.inertia = SIMD3<Float>(
            m / 12 * (pow(1.15, 2) + pow(4.4, 2)) * 0.8,
            m / 12 * (pow(2.0, 2) + pow(4.4, 2)) * 0.8,
            m / 12 * (pow(2.0, 2) + pow(1.15, 2)) * 0.8
        )
        self.tank = trim.tank

        let a: Float = 1.3, b: Float = 1.35, ht: Float = 0.85, my: Float = 0.15
        let defs: [(String, SIMD3<Float>, Bool)] = [
            ("fl", SIMD3<Float>(ht, my, a), true),
            ("fr", SIMD3<Float>(-ht, my, a), true),
            ("rl", SIMD3<Float>(ht, my, -b), false),
            ("rr", SIMD3<Float>(-ht, my, -b), false),
        ]
        self.wheels = defs.map { (id, local, front) in
            var w = Wheel(id: id, local: local, front: front)
            w.compression = 0.06
            w.prevCompression = 0.06
            return w
        }

        reset(x: 0, z: 0, yaw: 0)
    }

    func setTrim(_ t: Trim) {
        trim = t
        mass = t.mass
        let m = t.mass
        inertia = SIMD3<Float>(
            m / 12 * (pow(1.15, 2) + pow(4.4, 2)) * 0.8,
            m / 12 * (pow(2.0, 2) + pow(4.4, 2)) * 0.8,
            m / 12 * (pow(2.0, 2) + pow(1.15, 2)) * 0.8
        )
        tank = t.tank
    }

    func reset(x: Float, z: Float, yaw: Float) {
        pos = SIMD3<Float>(x, cgHeight + 0.05, z)
        vel = .zero
        quat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        angVel = .zero
        force = .zero
        torque = .zero
        tank = trim.tank
        airborneTime = 0
        for i in wheels.indices {
            wheels[i].compression = 0.06
            wheels[i].prevCompression = 0.06
            wheels[i].spinRate = 0
            wheels[i].spin = 0
            wheels[i].contact = false
            wheels[i].load = 0
            wheels[i].slip = 0
            wheels[i].onLoop = -1
        }
        flipState = nil; flipT = 0; flipRoll = 0; rollBurn = 0; rollDone = 0
        kickflipTimer = 0; burstTimer = 0; popTimer = 0; autoLift = 0; lateralTrim = 0; rollSettle = false
        liftLevel = 0; thrustLevel = 0; assistLevel = 0; lastImpact = 0; steer = 0
        flipCtl = .zero; burstTorque = .zero; controlTorque = .zero; assistForce = .zero
        force = .zero; torque = .zero; events.removeAll()
        wingAngle = 0; wingDeploy = 0; onLoop = false; groundedWheels = 0
        rampFlight = nil; rampS = -1; rampTheta = -1
        flankDir = 0; flankHold = 0; ultraSpool = 0
    }

    var speed: Float { simd_length(vel) }
    var forwardSpeed: Float {
        let fwd = simd_act(quat, SIMD3<Float>(0, 0, 1))
        return simd_dot(vel, fwd)
    }

    func toWorld(_ local: SIMD3<Float>, _ out: inout SIMD3<Float>) {
        out = pos + simd_act(quat, local)
    }

    func addForceAt(_ F: SIMD3<Float>, _ point: SIMD3<Float>) {
        force += F
        let r = point - pos
        torque += simd_cross(r, F)
    }

    // Simplified step: gravity + integration; full tire model omitted for brevity but structure present
    func step(dt: Float, input: [String: Float]) {
        let m = mass
        force = SIMD3<Float>(0, -m * G, 0)
        torque = .zero

        let up = simd_act(quat, SIMD3<Float>(0, 1, 0))
        let fwd = simd_act(quat, SIMD3<Float>(0, 0, 1))
        let right = simd_act(quat, SIMD3<Float>(-1, 0, 0))

        let vF = simd_dot(vel, fwd)
        let speedv = simd_length(vel)

        // Steering
        let aLim = trim.mu * 0.9 * (1 + fanLevel) * G
        let maxSteer = min(0.6, atan(2.65 * aLim / max(speedv * speedv, 1)) + 0.08)
        let target = -(input["steer"] ?? 0) * maxSteer
        let rate: Float = 3.2 / (1 + speedv * 0.05)
        steer += min(max(target - steer, -rate * dt), rate * dt)

        // Aero (basic)
        let q = 0.5 * RHO * speedv * speedv
        let downforce = min(q * trim.clA, 4700 * G - fanLevel * m * G)
        let drag = q * trim.cdA
        if speedv > 0.01 { force += (vel / speedv) * (-drag) }

        // Thrusters
        let thrustOn = (input["thrust"] ?? 0) > 0.5 && trim.rearThrust > 0 && tank > 0
        thrustLevel += ((thrustOn ? 1 : 0) - thrustLevel) * min(1, dt * 18)
        let liftOn = (input["lift"] ?? 0) > 0.5 && trim.liftThrust > 0 && tank > 0
        var liftTarget = liftOn ? 1.0 : 0.0
        liftLevel += (liftTarget - liftLevel) * min(1, dt * 20)
        if thrustLevel > 0.01 { force += fwd * (trim.rearThrust * thrustLevel * min(1, max(0, (trim.vmax - vF) / 6))) }
        if liftLevel > 0.01 {
            let v = up + SIMD3<Float>(0, 1, 0)
            let vn = simd_normalize(v)
            force += vn * (trim.liftThrust * liftLevel)
        }

        // Air tank drain
        let impulse = (thrustLevel * trim.rearThrust + liftLevel * trim.liftThrust) * dt
        if impulse > 1 { tank = max(0, tank - impulse) }
        else if trim.tank > 0 { tank = min(trim.tank, tank + trim.refill * dt) }

        // Drive
        let throttle = input["throttle"] ?? 0
        var driveTotal: Float = 0
        if throttle > 0 {
            let vAbs = max(abs(vF), 2.0)
            let powerLimited = trim.power / vAbs
            let limiter = min(1, max(0, (trim.vmax - vF) / 4))
            driveTotal = throttle * min(powerLimited, m * G * trim.maxDriveG) * limiter
        }
        let brake = input["brake"] ?? 0
        let brakeForce = brake * m * G * 2.6
        let handbrake = (input["handbrake"] ?? 0) > 0.5

        // Wheels (simplified: apply drive/brake along fwd at CG)
        groundedWheels = 4
        if abs(driveTotal) > 0 { force += fwd * driveTotal }
        if brakeForce > 0 { force -= fwd * (vF > 0 ? brakeForce : -brakeForce) }

        // Integrate
        vel += force * (dt / m)
        pos += vel * dt
        let qi = quat.conjugate
        var tLocal = simd_act(qi, torque)
        tLocal = SIMD3<Float>(tLocal.x / inertia.x, tLocal.y / inertia.y, tLocal.z / inertia.z)
        let tWorld = simd_act(quat, tLocal)
        angVel += tWorld * dt
        let wl = simd_length(angVel)
        if wl > 1e-6 {
            let dq = simd_quatf(angle: wl * dt, axis: angVel / wl)
            quat = dq * quat
            quat = simd_normalize(quat)
        }
    }
}
