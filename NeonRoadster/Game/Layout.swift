import Foundation
import simd

struct LOT { static let xMin: Float = -235; static let xMax: Float = 235; static let zMin: Float = -185; static let zMax: Float = 152 }
struct STALL { static let w: Float = 2.7; static let d: Float = 5.5 }
struct LAUNCH { static let z: Float = -165; static let xStart: Float = -215; static let length: Float = 402.336 }

struct Box { var kind: String; var x: Float; var z: Float; var y: Float; var w: Float; var h: Float; var d: Float; var yaw: Float; var c: Float = 1; var s: Float = 0; var r: Float = 0; var color: Float = 0 }

var BOXES: [Box] = []
var POLES: [(Float, Float, Float)] = []
var LIGHTS: [(Float, Float, Float)] = []
var TREES: [(Float, Float, Float)] = []
var STALLS: [(Float, Float, Float)] = []
var CONES: [(Float, Float)] = []
let SPAWN = (x: Float(0), z: Float(-110), yaw: Float(0))

struct RampSpec {
    var x0: Float = -100
    var z0: Float = -60
    var R1: Float = 6.5
    var Lv: Float = 0.3
    var R2: Float = 5.8
    var end: Float = 160 * .pi / 180
    var width: Float = 3.2
    var depth: Float = 1.8
    var phiMin: Float = 0.08
    var s1: Float = 0, s2: Float = 0, s3: Float = 0, length: Float = 0
    var cy: Float = 0, cu: Float = 0, lipY: Float = 0, lipU: Float = 0
}
var RAMP = RampSpec()

func initLayout() {
    // Semi demo
    BOXES.append(Box(kind: "semi", x: 60, z: -60, y: 0, w: 2.6, h: 4.1, d: 7.4, yaw: .pi / 2))
    BOXES.append(Box(kind: "building", x: 0, z: 192, y: 0, w: 250, h: 13, d: 76, yaw: 0))
    // ramp params
    RAMP.s1 = RAMP.R1 * .pi / 2
    RAMP.s2 = RAMP.Lv
    RAMP.s3 = RAMP.R2 * (RAMP.end - .pi / 2)
    RAMP.length = RAMP.s1 + RAMP.s2 + RAMP.s3
    RAMP.cy = RAMP.R1 + RAMP.Lv
    RAMP.cu = RAMP.R1 - RAMP.R2
    RAMP.lipY = RAMP.cy - RAMP.R2 * cos(RAMP.end)
    RAMP.lipU = RAMP.cu + RAMP.R2 * sin(RAMP.end)
    // truss feet
    POLES.append((RAMP.x0 - (RAMP.width / 2 + 0.25), RAMP.z0 + RAMP.R1 + RAMP.depth + 1.6, 0.3))
    POLES.append((RAMP.x0 + (RAMP.width / 2 + 0.25), RAMP.z0 + RAMP.R1 + RAMP.depth + 1.6, 0.3))
    POLES.append((RAMP.x0 - 13, RAMP.z0 - 5, 0.9))
    for b in BOXES.indices {
        BOXES[b].c = cos(BOXES[b].yaw)
        BOXES[b].s = sin(BOXES[b].yaw)
        BOXES[b].r = hypot(BOXES[b].w, BOXES[b].d) / 2
    }
    CONES = (0..<12).map { i in (Float(-120 + i * 18), Float(-110 + (i % 2 == 0 ? -2.5 : 2.5))) }
}

func boxesNear(x: Float, z: Float) -> [Box] {
    return BOXES.filter { b in
        let dx = x - b.x, dz = z - b.z
        return dx * dx + dz * dz <= (b.r + 2.5) * (b.r + 2.5)
    }
}

func groundAt(x: Float, z: Float, maxY: Float = .infinity) -> (h: Float, nx: Float, ny: Float, nz: Float) {
    var h: Float = 0
    for b in boxesNear(x: x, z: z) {
        let top = b.y + b.h
        if top <= h || top > maxY + 0.3 { continue }
        let dx = x - b.x, dz = z - b.z
        if dx * dx + dz * dz > (b.r) * (b.r) { continue }
        let lx = b.c * dx - b.s * dz
        let lz = b.s * dx + b.c * dz
        if abs(lx) < b.w / 2 && abs(lz) < b.d / 2 { h = top }
    }
    return (h, 0, 1, 0)
}

func insideBox(b: Box, x: Float, z: Float, pad: Float) -> Bool {
    let dx = x - b.x, dz = z - b.z
    if dx * dx + dz * dz > (b.r + pad) * (b.r + pad) { return false }
    let lx = b.c * dx - b.s * dz
    let lz = b.s * dx + b.c * dz
    return abs(lx) < b.w / 2 + pad && abs(lz) < b.d / 2 + pad
}
EOF
echo done