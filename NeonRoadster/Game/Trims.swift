import Foundation

struct TrimSpec {
    let name: String
    let mass: Float
    let mu: Float
    let power: Float
    let vmax: Float
    let maxDriveG: Float
    let clA: Float
    let cdA: Float
    let wing: Bool
    let rearThrust: Float
    let liftThrust: Float
    let tank: Float
    let refill: Float
    let perimeter: Bool
    let assistThrust: Float
    let airControl: Float
}

enum Trims {
    static let performance = TrimSpec(name: "Performance", mass: 1800, mu: 1.1, power: 450000, vmax: 60, maxDriveG: 1.4, clA: 1.2, cdA: 0.32, wing: true, rearThrust: 0, liftThrust: 0, tank: 0, refill: 0, perimeter: false, assistThrust: 0, airControl: 0.4)
    static let thrust = TrimSpec(name: "Thrust", mass: 1900, mu: 1.1, power: 700000, vmax: 70, maxDriveG: 1.6, clA: 1.4, cdA: 0.34, wing: true, rearThrust: 12000, liftThrust: 0, tank: 50000, refill: 2000, perimeter: false, assistThrust: 0, airControl: 0.5)
    static let rocket = TrimSpec(name: "Rocket", mass: 2000, mu: 1.15, power: 900000, vmax: 80, maxDriveG: 1.8, clA: 1.6, cdA: 0.36, wing: true, rearThrust: 15000, liftThrust: 22000, tank: 80000, refill: 3000, perimeter: true, assistThrust: 18000, airControl: 1.0)
    static let all: [TrimSpec] = [performance, thrust, rocket]
}
