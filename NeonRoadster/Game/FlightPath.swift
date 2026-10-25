import Foundation
import simd

struct PathFrame {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float>

    func offset(lateral: Float, vertical: Float) -> SIMD3<Float> {
        position + right * lateral + up * vertical
    }
}

/// The flight lane is an analytic, gently curving path. The city is built
/// around it, so there is always a readable corridor ahead.
enum FlightPath {
    static let length: Float = 6_000
    static let corridorHalfWidth: Float = 24
    static let corridorHalfHeight: Float = 18

    static func point(at distance: Float) -> SIMD3<Float> {
        let s = max(0, distance)
        let x0 = sinf(1.4) * 35
        let x = sinf(s * 0.0045) * 60 + sinf(s * 0.0017 + 1.4) * 35 - x0
        let y = 44 + (sinf(s * 0.0032 + 0.7) - sinf(0.7)) * 16 + sinf(s * 0.0011) * 7
        return [x, y, s]
    }

    static func frame(at distance: Float) -> PathFrame {
        let s = max(0, distance)
        let ahead = point(at: s + 0.75)
        let behind = point(at: s - 0.75)
        var forward = simd_normalize(ahead - behind)
        if simd_length(forward) < 0.001 { forward = [0, 0, 1] }

        let worldUp = SIMD3<Float>(0, 1, 0)
        var right = simd_cross(worldUp, forward)
        if simd_length(right) < 0.001 {
            right = [1, 0, 0]
        } else {
            right = simd_normalize(right)
        }
        let up = simd_normalize(simd_cross(forward, right))
        return PathFrame(position: point(at: s), forward: forward, right: right, up: up)
    }

    static func worldPoint(
        at distance: Float,
        lateral: Float,
        vertical: Float
    ) -> SIMD3<Float> {
        frame(at: distance).offset(lateral: lateral, vertical: vertical)
    }
}
