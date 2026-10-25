import RealityKit
import UIKit
import simd

struct RoadsterModel {
    let root: Entity
    let plume: Entity
    let fanGlow: Entity
    let tailBar: Entity
}

// MARK: - Lofted body

private struct CarSection {
    let z: Float
    let floor: Float
    let floorWidth: Float
    let rocker: Float
    let rockerWidth: Float
    let shoulder: Float
    let shoulderWidth: Float
    let belt: Float
    let beltWidth: Float
    let top: Float
    let topWidth: Float
}

private struct CanopySection {
    let z: Float
    let bottom: Float
    let bottomWidth: Float
    let side: Float
    let sideWidth: Float
    let top: Float
    let topWidth: Float
}

private enum CarLoft {
    static func bodyProfile(_ s: CarSection) -> [SIMD2<Float>] {
        let right: [SIMD2<Float>] = [
            [0, s.floor],
            [s.floorWidth, s.floor],
            [s.rockerWidth, s.rocker],
            [s.shoulderWidth, s.shoulder],
            [s.beltWidth, s.belt],
            [s.topWidth, s.top],
            [0, s.top]
        ]
        var loop = right
        for index in stride(from: 5, through: 1, by: -1) {
            loop.append([-right[index].x, right[index].y])
        }
        return loop
    }

    static func canopyProfile(_ s: CanopySection) -> [SIMD2<Float>] {
        let right: [SIMD2<Float>] = [
            [0, s.bottom],
            [s.bottomWidth, s.bottom],
            [s.sideWidth, s.side],
            [s.topWidth, s.top],
            [0, s.top]
        ]
        var loop = right
        for index in stride(from: 3, through: 1, by: -1) {
            loop.append([-right[index].x, right[index].y])
        }
        return loop
    }

    static func make(
        sections: [CarSection],
        name: String
    ) throws -> MeshResource {
        let profile = bodyProfile(sections[0])
        return try loft(
            sections: sections.map { section in
                (z: section.z, points: bodyProfile(section))
            },
            profileCount: profile.count,
            name: name
        )
    }

    static func make(
        canopy sections: [CanopySection],
        name: String
    ) throws -> MeshResource {
        let profile = canopyProfile(sections[0])
        return try loft(
            sections: sections.map { section in
                (z: section.z, points: canopyProfile(section))
            },
            profileCount: profile.count,
            name: name
        )
    }

    private static func loft(
        sections: [(z: Float, points: [SIMD2<Float>])],
        profileCount: Int,
        name: String
    ) throws -> MeshResource {
        guard sections.count >= 2 else {
            throw NSError(domain: "CarLoft", code: 1)
        }

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for section in sections {
            for point in section.points {
                positions.append([point.x, point.y, section.z])
            }
        }

        for i in 0..<(sections.count - 1) {
            for j in 0..<profileCount {
                let j2 = (j + 1) % profileCount
                let a = UInt32(i * profileCount + j)
                let b = UInt32(i * profileCount + j2)
                let c = UInt32((i + 1) * profileCount + j2)
                let d = UInt32((i + 1) * profileCount + j)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        // Caps use their own vertices so the nose and tail keep a crisp edge.
        let last = sections[sections.count - 1]
        let first = sections[0]
        let frontBase = UInt32(positions.count)
        for point in last.points {
            positions.append([point.x, point.y, last.z])
        }
        let rearBase = UInt32(positions.count)
        for point in first.points {
            positions.append([point.x, point.y, first.z])
        }
        for j in 1..<(profileCount - 1) {
            indices.append(contentsOf: [
                frontBase,
                frontBase + UInt32(j),
                frontBase + UInt32(j + 1)
            ])
            indices.append(contentsOf: [
                rearBase,
                rearBase + UInt32(j + 1),
                rearBase + UInt32(j)
            ])
        }

        var normals = Array(repeating: SIMD3<Float>.zero, count: positions.count)
        var index = 0
        while index < indices.count {
            let ia = Int(indices[index])
            let ib = Int(indices[index + 1])
            let ic = Int(indices[index + 2])
            let normal = simd_cross(
                positions[ib] - positions[ia],
                positions[ic] - positions[ia]
            )
            normals[ia] += normal
            normals[ib] += normal
            normals[ic] += normal
            index += 3
        }
        for i in normals.indices {
            let length = simd_length(normals[i])
            normals[i] = length > 0.0001 ? normals[i] / length : [0, 1, 0]
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

// MARK: - Factory

@MainActor
enum RoadsterFactory {
    /// Original fan-fiction hypercar inspired by the 2026 Roadster silhouette.
    /// Procedural geometry and materials only; no manufacturer badges or assets.
    static func make() -> RoadsterModel {
        let root = Entity()
        root.name = "Roadster"
        root.scale = [1.15, 1.15, 1.15]

        // MARK: Materials
        var paint = MaterialFactory.pbr(
            color: UIColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1),
            roughness: 0.26,
            metallic: 0.25,
            clearcoat: 0.85,
            clearcoatRoughness: 0.06
        )
        paint.faceCulling = .none

        var glass = MaterialFactory.pbr(
            color: UIColor(red: 0.050, green: 0.045, blue: 0.036, alpha: 1),
            roughness: 0.08,
            metallic: 0.10,
            clearcoat: 1.0,
            clearcoatRoughness: 0.03
        )
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.82))
        glass.readsDepth = true
        glass.writesDepth = false
        glass.faceCulling = .none

        let carbonTexture = TextureFactory.carbon()
        var carbon = MaterialFactory.pbr(
            color: .white,
            roughness: 0.38,
            metallic: 0.55,
            texture: carbonTexture,
            clearcoat: 0.4,
            clearcoatRoughness: 0.2
        )
        carbon.faceCulling = .none

        var gold = MaterialFactory.pbr(
            color: UIColor(red: 0.93, green: 0.68, blue: 0.26, alpha: 1),
            roughness: 0.20,
            metallic: 1.0,
            clearcoat: 0.5,
            clearcoatRoughness: 0.08
        )
        gold.faceCulling = .none

        var metal = MaterialFactory.pbr(
            color: UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1),
            roughness: 0.30,
            metallic: 0.90
        )
        metal.faceCulling = .none

        var rim = MaterialFactory.pbr(
            color: UIColor(red: 0.38, green: 0.40, blue: 0.43, alpha: 1),
            roughness: 0.25,
            metallic: 1.0,
            clearcoat: 0.5
        )
        rim.faceCulling = .none

        let rubber = MaterialFactory.pbr(
            color: UIColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1),
            roughness: 0.85,
            metallic: 0.0
        )

        let interior = MaterialFactory.pbr(
            color: UIColor(red: 0.055, green: 0.055, blue: 0.065, alpha: 1),
            roughness: 0.70,
            metallic: 0.05
        )

        let seat = MaterialFactory.pbr(
            color: UIColor(red: 0.72, green: 0.66, blue: 0.55, alpha: 1),
            roughness: 0.75,
            metallic: 0.0
        )

        var headlight = MaterialFactory.unlit(
            color: UIColor(red: 0.86, green: 0.95, blue: 1.0, alpha: 1)
        )
        headlight.faceCulling = .none

        var tail = MaterialFactory.unlit(
            color: UIColor(red: 1.0, green: 0.06, blue: 0.10, alpha: 1)
        )
        tail.faceCulling = .none

        var cyan = MaterialFactory.unlit(
            color: UIColor(red: 0.35, green: 0.92, blue: 1.0, alpha: 1)
        )
        cyan.faceCulling = .none

        var plumeMaterial = MaterialFactory.unlit(
            color: UIColor(red: 0.55, green: 0.95, blue: 1.0, alpha: 0.9),
            transparent: true
        )
        plumeMaterial.faceCulling = .none

        var coreMaterial = MaterialFactory.unlit(
            color: UIColor(red: 0.92, green: 1.0, blue: 1.0, alpha: 0.95),
            transparent: true
        )
        coreMaterial.faceCulling = .none

        let underglow = MaterialFactory.unlit(
            color: UIColor(red: 0.10, green: 0.55, blue: 0.80, alpha: 0.32),
            transparent: true
        )

        var fanMaterial = MaterialFactory.unlit(
            color: UIColor(red: 0.25, green: 0.90, blue: 1.0, alpha: 1)
        )
        fanMaterial.faceCulling = .none

        // MARK: Body
        let bodySections: [CarSection] = [
            .init(z: -2.135, floor: 0.19, floorWidth: 0.66, rocker: 0.19, rockerWidth: 0.90,
                  shoulder: 0.45, shoulderWidth: 0.92, belt: 0.89, beltWidth: 0.95,
                  top: 0.90, topWidth: 0.80),
            .init(z: -1.820, floor: 0.13, floorWidth: 0.66, rocker: 0.13, rockerWidth: 0.96,
                  shoulder: 0.60, shoulderWidth: 1.00, belt: 0.91, beltWidth: 1.00,
                  top: 0.91, topWidth: 0.86),
            .init(z: -1.438, floor: 0.10, floorWidth: 0.62, rocker: 0.10, rockerWidth: 0.96,
                  shoulder: 0.50, shoulderWidth: 1.00, belt: 0.91, beltWidth: 1.00,
                  top: 0.91, topWidth: 0.86),
            .init(z: -1.165, floor: 0.085, floorWidth: 0.60, rocker: 0.085, rockerWidth: 0.94,
                  shoulder: 0.42, shoulderWidth: 1.00, belt: 0.90, beltWidth: 1.00,
                  top: 0.90, topWidth: 0.86),
            .init(z: -0.580, floor: 0.085, floorWidth: 0.60, rocker: 0.085, rockerWidth: 0.94,
                  shoulder: 0.34, shoulderWidth: 0.96, belt: 0.85, beltWidth: 0.96,
                  top: 0.86, topWidth: 0.86),
            .init(z: 0.000, floor: 0.085, floorWidth: 0.60, rocker: 0.085, rockerWidth: 0.92,
                  shoulder: 0.31, shoulderWidth: 0.93, belt: 0.80, beltWidth: 0.94,
                  top: 0.82, topWidth: 0.86),
            .init(z: 1.000, floor: 0.09, floorWidth: 0.60, rocker: 0.09, rockerWidth: 0.90,
                  shoulder: 0.28, shoulderWidth: 0.94, belt: 0.76, beltWidth: 0.95,
                  top: 0.80, topWidth: 0.86),
            .init(z: 1.438, floor: 0.10, floorWidth: 0.60, rocker: 0.10, rockerWidth: 0.88,
                  shoulder: 0.29, shoulderWidth: 0.95, belt: 0.72, beltWidth: 0.96,
                  top: 0.73, topWidth: 0.86),
            .init(z: 1.800, floor: 0.11, floorWidth: 0.58, rocker: 0.12, rockerWidth: 0.86,
                  shoulder: 0.29, shoulderWidth: 0.92, belt: 0.68, beltWidth: 0.93,
                  top: 0.70, topWidth: 0.86),
            .init(z: 2.050, floor: 0.135, floorWidth: 0.55, rocker: 0.15, rockerWidth: 0.78,
                  shoulder: 0.30, shoulderWidth: 0.86, belt: 0.56, beltWidth: 0.88,
                  top: 0.58, topWidth: 0.82),
            .init(z: 2.255, floor: 0.15, floorWidth: 0.50, rocker: 0.18, rockerWidth: 0.60,
                  shoulder: 0.32, shoulderWidth: 0.64, belt: 0.46, beltWidth: 0.66,
                  top: 0.50, topWidth: 0.58)
        ]

        do {
            let bodyMesh = MeshResource.generateBox(size: [2.0, 0.825, 4.39], cornerRadius: 0.25)
            let body = ModelEntity(mesh: bodyMesh, materials: [MaterialFactory.unlit(color: .red)])
            body.name = "Body"
            body.position = [0, 0.50, 0]
            root.addChild(body)
            NSLog("ROADSTER: body mesh OK bounds=%@ mesh=%@", String(describing: body.visualBounds(relativeTo: root)), String(describing: bodyMesh.bounds))
        } catch {
            NSLog("ROADSTER: body mesh FAILED %@", String(describing: error))
        }

        // MARK: Glass canopy
        let canopySections: [CanopySection] = [
            .init(z: -1.750, bottom: 0.91, bottomWidth: 0.48, side: 0.93, sideWidth: 0.50,
                  top: 0.93, topWidth: 0.30),
            .init(z: -1.350, bottom: 0.90, bottomWidth: 0.60, side: 0.98, sideWidth: 0.62,
                  top: 1.00, topWidth: 0.44),
            .init(z: -0.900, bottom: 0.87, bottomWidth: 0.66, side: 1.06, sideWidth: 0.68,
                  top: 1.10, topWidth: 0.52),
            .init(z: -0.450, bottom: 0.84, bottomWidth: 0.68, side: 1.12, sideWidth: 0.72,
                  top: 1.17, topWidth: 0.58),
            .init(z: 0.000, bottom: 0.82, bottomWidth: 0.70, side: 1.13, sideWidth: 0.74,
                  top: 1.18, topWidth: 0.62),
            .init(z: 0.450, bottom: 0.81, bottomWidth: 0.70, side: 1.10, sideWidth: 0.76,
                  top: 1.16, topWidth: 0.66),
            .init(z: 0.850, bottom: 0.80, bottomWidth: 0.68, side: 1.02, sideWidth: 0.78,
                  top: 1.10, topWidth: 0.70),
            .init(z: 1.200, bottom: 0.77, bottomWidth: 0.66, side: 0.92, sideWidth: 0.78,
                  top: 0.96, topWidth: 0.72),
            .init(z: 1.500, bottom: 0.73, bottomWidth: 0.62, side: 0.78, sideWidth: 0.76,
                  top: 0.80, topWidth: 0.70)
        ]

        if let canopyMesh = try? CarLoft.make(canopy: canopySections, name: "Canopy") {
            let canopy = ModelEntity(mesh: canopyMesh, materials: [glass])
            canopy.name = "Canopy"
            canopy.isEnabled = true
            root.addChild(canopy)
        }

        // Cockpit, visible through the glass.
        box("Cockpit", size: [1.16, 0.10, 1.55], position: [0, 0.80, -0.10],
            material: interior, in: root)
        box("Dashboard", size: [1.05, 0.14, 0.28], position: [0, 0.88, 0.38],
            material: interior, cornerRadius: 0.03, in: root)
        for x in [-0.28, 0.28] as [Float] {
            box("Seat", size: [0.40, 0.14, 0.48], position: [x, 0.90, -0.32],
                material: seat, cornerRadius: 0.05, in: root)
            box("Headrest", size: [0.24, 0.16, 0.10], position: [x, 1.00, -0.56],
                material: seat, cornerRadius: 0.04, in: root)
        }

        // Gold canopy sill and A-pillar trim.
        for x in [-0.72, 0.72] as [Float] {
            box("CanopyTrim", size: [0.025, 0.025, 1.85], position: [x, 0.835, -0.15],
                material: gold, in: root)
        }
        box("CanopyTrimFront", size: [1.42, 0.025, 0.025], position: [0, 0.75, 1.50],
            material: gold, in: root)

        // MARK: Fenders and aero
        for z in [-1.438, 1.438] as [Float] {
            for x in [-0.92, 0.92] as [Float] {
                box("FenderFlare", size: [0.18, 0.34, 0.98], position: [x, 0.54, z],
                    material: paint, cornerRadius: 0.08, in: root)
            }
        }

        for x in [-0.86, 0.86] as [Float] {
            box("SideSkirt", size: [0.10, 0.12, 2.55], position: [x, 0.16, 0],
                material: carbon, cornerRadius: 0.02, in: root)
            box("GoldSill", size: [0.018, 0.028, 2.10], position: [x * 1.01, 0.30, 0],
                material: gold, in: root)
            box("SideIntake", size: [0.03, 0.16, 0.52], position: [x * 1.04, 0.56, -0.82],
                material: carbon, cornerRadius: 0.015, in: root)
            box("MirrorStalk", size: [0.09, 0.025, 0.03], position: [x * 1.01, 0.86, 0.54],
                material: gold, in: root)
            box("Mirror", size: [0.17, 0.07, 0.11], position: [x * 1.09, 0.88, 0.54],
                material: paint, cornerRadius: 0.03, in: root)
        }

        box("Splitter", size: [1.55, 0.05, 0.36], position: [0, 0.12, 2.10],
            material: carbon, cornerRadius: 0.02, in: root)
        box("FrontIntake", size: [1.02, 0.13, 0.08], position: [0, 0.30, 2.24],
            material: carbon, cornerRadius: 0.02, in: root)
        for x in [-0.28, 0.28] as [Float] {
            box("HoodVent", size: [0.20, 0.015, 0.40], position: [x, 0.735, 1.22],
                material: carbon, in: root)
        }
        box("Badge", size: [0.07, 0.07, 0.02], position: [0, 0.47, 2.27],
            material: gold,
            orientation: simd_quatf(angle: .pi / 4, axis: [0, 0, 1]),
            in: root)

        // Rear wing and diffuser.
        box("Wing", size: [1.56, 0.045, 0.30], position: [0, 0.99, -1.95],
            material: carbon, cornerRadius: 0.02, in: root)
        for x in [-0.78, 0.78] as [Float] {
            box("WingEndplate", size: [0.025, 0.16, 0.32], position: [x, 0.99, -1.95],
                material: gold, in: root)
        }
        for x in [-0.52, 0.52] as [Float] {
            box("WingSupport", size: [0.05, 0.22, 0.12], position: [x, 0.88, -1.95],
                material: carbon, in: root)
        }
        box("Diffuser", size: [1.30, 0.12, 0.32], position: [0, 0.15, -2.02],
            material: carbon, cornerRadius: 0.02, in: root)
        for x in [-0.48, -0.24, 0, 0.24, 0.48] as [Float] {
            box("DiffuserFin", size: [0.025, 0.14, 0.30], position: [x, 0.13, -2.04],
                material: carbon, in: root)
        }
        box("RearBumper", size: [1.25, 0.16, 0.10], position: [0, 0.28, -2.10],
            material: carbon, cornerRadius: 0.02, in: root)

        // Signature full-width tail bar with a gold surround.
        box("TailSurround", size: [1.62, 0.10, 0.03], position: [0, 0.68, -2.14],
            material: gold, in: root)
        let tailBar = box("TailBar", size: [1.55, 0.06, 0.05], position: [0, 0.68, -2.16],
                          material: tail, in: root)
        for x in [-0.72, 0.72] as [Float] {
            box("TailCap", size: [0.05, 0.16, 0.05], position: [x, 0.62, -2.16],
                material: tail, in: root)
        }

        // Headlights.
        for x in [-0.48, 0.48] as [Float] {
            box("Headlight", size: [0.34, 0.04, 0.03], position: [x, 0.52, 2.25],
                material: headlight, in: root)
        }

        // MARK: Wheels
        for axle in [(z: Float(1.438), track: Float(0.83), width: Float(0.27)),
                     (z: Float(-1.438), track: Float(0.875), width: Float(0.33))] {
            for side in [Float(-1), Float(1)] {
                let x = side * axle.track
                let faceX = side * (axle.track + axle.width * 0.5 + 0.01)

                let tire = ModelEntity(
                    mesh: .generateCylinder(height: axle.width, radius: 0.345),
                    materials: [rubber]
                )
                tire.name = "Tire"
                tire.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                tire.position = [x, 0.345, axle.z]
                root.addChild(tire)

                let rimEntity = ModelEntity(
                    mesh: .generateCylinder(height: axle.width + 0.01, radius: 0.235),
                    materials: [rim]
                )
                rimEntity.name = "Rim"
                rimEntity.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                rimEntity.position = [x, 0.345, axle.z]
                root.addChild(rimEntity)

                let disc = ModelEntity(
                    mesh: .generateCylinder(height: 0.02, radius: 0.19),
                    materials: [metal]
                )
                disc.name = "BrakeDisc"
                disc.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                disc.position = [faceX, 0.345, axle.z]
                root.addChild(disc)

                for spokeIndex in 0..<5 {
                    let angle = Float(spokeIndex) * .pi * 2 / 5
                    box("Spoke", size: [0.022, 0.34, 0.042],
                        position: [faceX + side * 0.008, 0.345, axle.z],
                        material: gold,
                        orientation: simd_quatf(angle: angle, axis: [1, 0, 0]),
                        in: root)
                }

                box("Caliper", size: [0.03, 0.12, 0.08],
                    position: [faceX + side * 0.006, 0.465, axle.z + 0.10],
                    material: gold, cornerRadius: 0.01, in: root)
            }
        }

        // MARK: Thrusters and plume
        for x in [-0.60, -0.22, 0.22, 0.60] as [Float] {
            let nozzle = ModelEntity(
                mesh: .generateCylinder(height: 0.16, radius: 0.10),
                materials: [metal]
            )
            nozzle.name = "Thruster"
            nozzle.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            nozzle.position = [x, 0.40, -2.10]
            root.addChild(nozzle)

            let glow = ModelEntity(
                mesh: .generateCylinder(height: 0.02, radius: 0.07),
                materials: [cyan]
            )
            glow.name = "ThrusterGlow"
            glow.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            glow.position = [x, 0.40, -2.19]
            root.addChild(glow)
        }

        let plume = Entity()
        plume.name = "Plume"
        plume.position = [0, 0.40, -2.18]
        plume.scale = .init(repeating: 0.35)
        for x in [-0.60, -0.22, 0.22, 0.60] as [Float] {
            let outer = ModelEntity(
                mesh: .generateCone(height: 1.0, radius: 0.13),
                materials: [plumeMaterial]
            )
            outer.name = "PlumeCone"
            outer.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            outer.position = [x, 0, -0.25]
            plume.addChild(outer)

            let inner = ModelEntity(
                mesh: .generateCone(height: 0.78, radius: 0.055),
                materials: [coreMaterial]
            )
            inner.name = "PlumeCore"
            inner.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            inner.position = [x, 0, -0.22]
            plume.addChild(inner)
        }
        root.addChild(plume)

        // MARK: Fan and underglow
        let fanGlow = Entity()
        fanGlow.name = "FanGlow"
        if let torus = try? MeshFactory.makeTorus(
            majorRadius: 0.62,
            minorRadius: 0.030,
            majorSegments: 32,
            minorSegments: 6
        ) {
            let ring = ModelEntity(mesh: torus, materials: [fanMaterial])
            ring.name = "FanRing"
            ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            ring.position = [0, 0.055, 0]
            fanGlow.addChild(ring)
        }
        root.addChild(fanGlow)

        box("Underglow", size: [1.30, 0.008, 2.70], position: [0, 0.045, 0],
            material: underglow, in: root)

        // MARK: Lights and bloom
        let cabinLight = PointLight()
        cabinLight.light.color = UIColor(red: 0.75, green: 0.90, blue: 1.0, alpha: 1)
        cabinLight.light.intensity = 6_000
        cabinLight.light.attenuationRadius = 16
        cabinLight.position = [0, 0.70, 0]
        root.addChild(cabinLight)

        let headlightLight = PointLight()
        headlightLight.light.color = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
        headlightLight.light.intensity = 5_000
        headlightLight.light.attenuationRadius = 22
        headlightLight.position = [0, 0.50, 2.10]
        root.addChild(headlightLight)

        let tailLight = PointLight()
        tailLight.light.color = UIColor(red: 1.0, green: 0.12, blue: 0.18, alpha: 1)
        tailLight.light.intensity = 2_400
        tailLight.light.attenuationRadius = 8
        tailLight.position = [0, 0.62, -2.25]
        root.addChild(tailLight)

        if #available(iOS 27.0, *) {
            root.components.set(BloomComponent(scope: .hierarchical))
            var bloom = BloomOptionsComponent()
            bloom.strength = 0.35
            bloom.threshold = 0.78
            bloom.blurRadius = 6
            root.components.set(bloom)
        }

        if let body = root.children.first(where: { $0.name == "Body" }) {
            NSLog("ROADSTER: body enabled=%@ pos=%@ scale=%@ parent=%@ children=%@",
                  String(describing: body.isEnabled),
                  String(describing: body.position),
                  String(describing: body.scale),
                  String(describing: body.parent?.name),
                  String(describing: root.children.map(\.name)))
        }

        return RoadsterModel(
            root: root,
            plume: plume,
            fanGlow: fanGlow,
            tailBar: tailBar
        )
    }

    // MARK: - Helpers

    @discardableResult
    private static func box(
        _ name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: any RealityKit.Material,
        cornerRadius: Float = 0,
        orientation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
        in parent: Entity
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: cornerRadius),
            materials: [material]
        )
        entity.name = name
        entity.position = position
        entity.orientation = orientation
        parent.addChild(entity)
        return entity
    }
}
