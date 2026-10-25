import Foundation
import RealityKit
import simd

/// Accumulates axis-aligned (or rotated) boxes into one mesh so an entire
/// city block can be drawn with a single draw call. `generateBox(cornerRadius:)`
/// is deliberately avoided: it costs ~13k triangles per box.
struct BoxBatch {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { positions.isEmpty }

    mutating func addBox(
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        orientation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    ) {
        let half = size * 0.5
        if abs(center.x) < 2, abs(center.z) < 2, center.y > 43, center.y < 46 {
            NSLog("BOX: car-adjacent center=%@ size=%@", String(describing: center), String(describing: size))
        }
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            ([ 1, 0, 0], [0, 1, 0], [0, 0,  1]),
            ([-1, 0, 0], [0, 1, 0], [0, 0, -1]),
            ([0,  1, 0], [0, 0, 1], [ 1, 0, 0]),
            ([0, -1, 0], [0, 0,-1], [ 1, 0, 0]),
            ([0, 0,  1], [ 1, 0, 0], [0, 1, 0]),
            ([0, 0, -1], [-1, 0, 0], [0, 1, 0]),
        ]

        for (localNormal, localU, localV) in faces {
            let n = orientation.act(localNormal)

            let localCenter = localNormal * simd_dot(simd_abs(localNormal), half)
            let localDu = localU * simd_dot(simd_abs(localU), half)
            let localDv = localV * simd_dot(simd_abs(localV), half)

            let c = center + orientation.act(localCenter)
            let du = orientation.act(localDu)
            let dv = orientation.act(localDv)

            let base = UInt32(positions.count)
            positions.append(contentsOf: [
                c - du - dv,
                c + du - dv,
                c + du + dv,
                c - du + dv
            ])
            for _ in 0..<4 { normals.append(n) }
            let uScale = max(0.5, simd_length(du) * 2 / 12)
            let vScale = max(0.5, simd_length(dv) * 2 / 12)
            uvs.append(contentsOf: [
                [0, 0],
                [uScale, 0],
                [uScale, vScale],
                [0, vScale]
            ])
            indices.append(contentsOf: [
                base, base + 1, base + 2,
                base, base + 2, base + 3
            ])
        }
    }

    mutating func addBox(
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        yaw: Float
    ) {
        addBox(
            center: center,
            size: size,
            orientation: simd_quatf(angle: yaw, axis: [0, 1, 0])
        )
    }

    @MainActor
    func makeMesh(name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

/// A textured quad used for the lit window facade of a building. One mesh can
/// hold every facade in a color family, keeping the city at a handful of draws.
struct FacadeBatch {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { positions.isEmpty }

    mutating func addFacade(
        center: SIMD3<Float>,
        width: Float,
        height: Float,
        orientation: simd_quatf,
        normalSign: Float,
        uvScale: SIMD2<Float> = [1, 1]
    ) {
        let halfWidth = width * 0.5
        let halfHeight = height * 0.5
        let normal = orientation.act([normalSign, 0, 0])
        let uAxis = orientation.act([0, 0, 1])
        let vAxis = orientation.act([0, 1, 0])

        let base = UInt32(positions.count)
        positions.append(contentsOf: [
            center - uAxis * halfWidth - vAxis * halfHeight,
            center + uAxis * halfWidth - vAxis * halfHeight,
            center + uAxis * halfWidth + vAxis * halfHeight,
            center - uAxis * halfWidth + vAxis * halfHeight
        ])
        normals.append(contentsOf: [normal, normal, normal, normal])
        uvs.append(contentsOf: [
            [0, uvScale.y],
            [uvScale.x, uvScale.y],
            [uvScale.x, 0],
            [0, 0]
        ])

        if normalSign >= 0 {
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        } else {
            indices.append(contentsOf: [base, base + 2, base + 1, base, base + 3, base + 2])
        }
    }

    @MainActor
    func makeMesh(name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

enum MeshFactory {
    /// A low-poly torus whose hole faces +Z. One mesh can be shared by every
    /// ring in the course.
    @MainActor
    static func makeTorus(
        majorRadius: Float,
        minorRadius: Float,
        majorSegments: Int = 24,
        minorSegments: Int = 8
    ) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for i in 0...majorSegments {
            let u = Float(i) / Float(majorSegments) * 2 * .pi
            let cosU = cos(u)
            let sinU = sin(u)
            for j in 0...minorSegments {
                let v = Float(j) / Float(minorSegments) * 2 * .pi
                let cosV = cos(v)
                let sinV = sin(v)
                let normal = SIMD3<Float>(cosV * cosU, cosV * sinU, sinV)
                positions.append(
                    SIMD3<Float>(
                        (majorRadius + minorRadius * cosV) * cosU,
                        (majorRadius + minorRadius * cosV) * sinU,
                        minorRadius * sinV
                    )
                )
                normals.append(normal)
            }
        }

        let stride = minorSegments + 1
        for i in 0..<majorSegments {
            for j in 0..<minorSegments {
                let a = UInt32(i * stride + j)
                let b = UInt32((i + 1) * stride + j)
                let c = UInt32((i + 1) * stride + j + 1)
                let d = UInt32(i * stride + j + 1)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "Torus")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// A simple tapered box used for traffic cars and the roadster body.
    @MainActor
    static func makeWedge(
        width: Float,
        length: Float,
        height: Float,
        noseHeight: Float
    ) throws -> MeshResource {
        let w = width * 0.5
        let l = length * 0.5
        let h = height * 0.5
        let n = noseHeight * 0.5

        // 8 corners: front (z = +l) is lower than rear (z = -l).
        let p: [SIMD3<Float>] = [
            [-w, -h,  l], [ w, -h,  l], [ w,  n,  l], [-w,  n,  l],
            [-w, -h, -l], [ w, -h, -l], [ w,  h, -l], [-w,  h, -l]
        ]
        let faces: [[UInt32]] = [
            [0, 1, 2], [0, 2, 3],       // front
            [5, 4, 7], [5, 7, 6],       // back
            [4, 0, 3], [4, 3, 7],       // left
            [1, 5, 6], [1, 6, 2],       // right
            [3, 2, 6], [3, 6, 7],       // top
            [4, 5, 1], [4, 1, 0]        // bottom
        ]

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for face in faces {
            let a = p[Int(face[0])]
            let b = p[Int(face[1])]
            let c = p[Int(face[2])]
            let normal = simd_normalize(simd_cross(b - a, c - a))
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        var descriptor = MeshDescriptor(name: "Wedge")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
