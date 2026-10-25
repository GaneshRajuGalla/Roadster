import Metal
import RealityKit
import UIKit
import simd

struct Ring {
    let entity: Entity
    let distance: Float
    let lateral: Float
    let vertical: Float
    let radius: Float
    var collected = false
}

struct Traffic {
    let entity: Entity
    let initialDistance: Float
    var distance: Float
    let speed: Float
    let lateral: Float
    let vertical: Float
    let radius: Float
    var nearMissed = false
}

struct AmbientTraffic {
    let entity: Entity
    var distance: Float
    let speed: Float
    let lateral: Float
    let vertical: Float
}

struct City {
    let root: Entity
    let neonRoot: Entity
    var rings: [Ring]
    var traffic: [Traffic]
    var ambientTraffic: [AmbientTraffic]
    let sky: EnvironmentResource?
    let sun: Entity
    let haze: Entity
}

/// A sunset, New York-inspired flight canyon. Buildings, streets, the river,
/// the bridge and the skyline are all generated from code and merged into a
/// small number of PBR batches.
@MainActor
enum CityBuilder {
    static let finishDistance = FlightPath.length - 60
    static let sunDirection = simd_normalize(SIMD3<Float>(-0.46, 0.19, 0.87))

    private enum Palette {
        static let road = UIColor(red: 0.055, green: 0.058, blue: 0.065, alpha: 1)
        static let sidewalk = UIColor(red: 0.22, green: 0.215, blue: 0.205, alpha: 1)
        static let park = UIColor(red: 0.075, green: 0.14, blue: 0.075, alpha: 1)
        static let stone = UIColor(red: 0.40, green: 0.37, blue: 0.32, alpha: 1)
        static let metal = UIColor(red: 0.13, green: 0.145, blue: 0.16, alpha: 1)
        static let roof = UIColor(red: 0.10, green: 0.105, blue: 0.11, alpha: 1)
        static let wood = UIColor(red: 0.28, green: 0.19, blue: 0.12, alpha: 1)
        static let water = UIColor(red: 0.045, green: 0.075, blue: 0.085, alpha: 1)
        static let ringCyan = UIColor(red: 0.40, green: 0.91, blue: 1.0, alpha: 1)
        static let ringAmber = UIColor(red: 1.0, green: 0.70, blue: 0.32, alpha: 1)
        static let warm = UIColor(red: 1.0, green: 0.66, blue: 0.34, alpha: 1)
        static let cool = UIColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 1)
        static let distant = UIColor(red: 0.33, green: 0.30, blue: 0.34, alpha: 1)
    }

    private struct BuildingSpec {
        let center: SIMD3<Float>
        let width: Float
        let depth: Float
        let height: Float
        let orientation: simd_quatf
        let styleIndex: Int
        let seed: UInt64
        let side: Float
        let hasCrown: Bool
        let hasSpire: Bool
        let hasWaterTower: Bool
        let hasBillboard: Bool
    }

    static func build() -> City {
        let root = Entity()
        root.name = "City"
        let neonRoot = Entity()
        neonRoot.name = "Neon"

        waterTowerHost = Entity()
        waterTowerHost.name = "WaterTowers"
        signHost = Entity()
        signHost.name = "Billboards"
        rngForSigns = SeededGenerator(seed: 0xB111B0A2D)

        let sky = TextureFactory.skyEnvironment()
        let facadeTextures = TextureFactory.facades()
        let asphaltTexture = TextureFactory.asphalt()
        let concreteTexture = TextureFactory.concrete()
        let waterNormal = TextureFactory.waterNormal()
        let glowTexture = TextureFactory.glow()
        let hazeTexture = TextureFactory.haze()
        let carbonTexture = TextureFactory.carbon()

        var bodyBatches = Array(repeating: BoxBatch(), count: TextureFactory.styles.count)
        var baseBatches = Array(repeating: FacadeBatch(), count: TextureFactory.styles.count)
        var litBatches = Array(repeating: FacadeBatch(), count: TextureFactory.styles.count)
        var roofBatch = BoxBatch()
        var metalBatch = BoxBatch()
        var stoneBatch = BoxBatch()
        var roadBatch = BoxBatch()
        var sidewalkBatch = BoxBatch()
        var laneBatch = BoxBatch()
        var parkBatch = BoxBatch()
        var treeTrunkBatch = BoxBatch()
        var streetCarBatch = BoxBatch()
        var streetCarLightBatch = BoxBatch()
        var distantBatch = BoxBatch()
        var lightBatch = BoxBatch()
        var signBatch = BoxBatch()

        addGround(
            road: &roadBatch,
            sidewalks: &sidewalkBatch,
            lanes: &laneBatch,
            park: &parkBatch
        )
        addRiverAndBridge(
            waterNormal: waterNormal,
            stone: &stoneBatch,
            metal: &metalBatch,
            road: &roadBatch,
            light: &lightBatch,
            to: root
        )
        addParkTrees(trunks: &treeTrunkBatch, to: root)
        addStreetDetails(
            cars: &streetCarBatch,
            carLights: &streetCarLightBatch,
            poles: &metalBatch,
            lamps: &lightBatch
        )
        addBuildings(
            bodies: &bodyBatches,
            bases: &baseBatches,
            lits: &litBatches,
            roofs: &roofBatch,
            metal: &metalBatch,
            stone: &stoneBatch,
            light: &lightBatch,
            sign: &signBatch,
            facades: facadeTextures
        )
        addLandmarks(
            bodies: &bodyBatches,
            bases: &baseBatches,
            lits: &litBatches,
            roofs: &roofBatch,
            metal: &metalBatch,
            stone: &stoneBatch,
            light: &lightBatch,
            facades: facadeTextures
        )
        addDistantSkyline(to: &distantBatch)

        root.addChild(waterTowerHost)
        neonRoot.addChild(signHost)

        // MARK: Materials

        let bodyMaterials = TextureFactory.styles.map { style in
            MaterialFactory.pbr(
                color: style.body,
                roughness: style.roughness,
                metallic: style.metalness
            )
        }

        let facadeMaterials = facadeTextures.map { textures in
            var material = MaterialFactory.pbr(
                color: .white,
                roughness: 1,
                metallic: 1,
                texture: textures.base,
                metallicTexture: textures.metallic,
                roughnessTexture: textures.roughness
            )
            // Facade quads are generated for both sides of a building face.
            // Disabling culling keeps every visible wall textured regardless
            // of which way the chase camera is looking.
            material.faceCulling = .none
            return material
        }

        let litMaterials = facadeTextures.map { textures in
            var material = MaterialFactory.unlit(
                color: .white,
                texture: textures.lit,
                transparent: true
            )
            material.faceCulling = .none
            return material
        }

        // MARK: Add batches

        for index in bodyBatches.indices {
            addBatch(
                bodyBatches[index],
                name: "BuildingBody\(index)",
                material: bodyMaterials[index],
                to: root
            )
            addFacadeBatch(
                baseBatches[index],
                name: "FacadeBase\(index)",
                material: facadeMaterials[index],
                to: neonRoot
            )
            addFacadeBatch(
                litBatches[index],
                name: "FacadeLit\(index)",
                material: litMaterials[index],
                to: neonRoot
            )
        }

        addBatch(
            roofBatch,
            name: "Roofs",
            material: MaterialFactory.pbr(
                color: Palette.roof,
                roughness: 0.9,
                metallic: 0.05
            ),
            to: root
        )
        addBatch(
            metalBatch,
            name: "Metal",
            material: MaterialFactory.pbr(
                color: Palette.metal,
                roughness: 0.42,
                metallic: 0.8
            ),
            to: root
        )
        addBatch(
            stoneBatch,
            name: "Stone",
            material: MaterialFactory.pbr(
                color: Palette.stone,
                roughness: 0.86,
                metallic: 0
            ),
            to: root
        )
        addBatch(
            roadBatch,
            name: "Roads",
            material: MaterialFactory.pbr(
                color: Palette.road,
                roughness: 0.92,
                metallic: 0.05,
                texture: asphaltTexture
            ),
            to: root
        )
        addBatch(
            sidewalkBatch,
            name: "Sidewalks",
            material: MaterialFactory.pbr(
                color: Palette.sidewalk,
                roughness: 0.88,
                metallic: 0,
                texture: concreteTexture
            ),
            to: root
        )
        addBatch(
            parkBatch,
            name: "Park",
            material: MaterialFactory.pbr(
                color: Palette.park,
                roughness: 0.95,
                metallic: 0
            ),
            to: root
        )
        addBatch(
            treeTrunkBatch,
            name: "TreeTrunks",
            material: MaterialFactory.pbr(
                color: Palette.wood,
                roughness: 0.95,
                metallic: 0
            ),
            to: root
        )
        addBatch(
            streetCarBatch,
            name: "StreetCars",
            material: MaterialFactory.pbr(
                color: UIColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1),
                roughness: 0.4,
                metallic: 0.5
            ),
            to: root
        )
        addBatch(
            distantBatch,
            name: "DistantSkyline",
            material: MaterialFactory.unlit(color: Palette.distant),
            to: root
        )

        addBatch(
            laneBatch,
            name: "LaneMarkings",
            material: MaterialFactory.unlit(color: UIColor(white: 0.92, alpha: 1)),
            to: neonRoot
        )
        addBatch(
            streetCarLightBatch,
            name: "StreetCarLights",
            material: MaterialFactory.unlit(color: Palette.warm),
            to: neonRoot
        )
        addBatch(
            lightBatch,
            name: "CityLights",
            material: MaterialFactory.unlit(color: Palette.warm),
            to: neonRoot
        )
        addBatch(
            signBatch,
            name: "Signage",
            material: MaterialFactory.unlit(color: Palette.cool),
            to: neonRoot
        )

        // MARK: Rings

        let ringMesh = try? MeshFactory.makeTorus(
            majorRadius: 5.4,
            minorRadius: 0.20,
            majorSegments: 32,
            minorSegments: 8
        )
        var rings: [Ring] = []
        if let ringMesh {
            let cyan = MaterialFactory.unlit(color: Palette.ringCyan)
            let amber = MaterialFactory.unlit(color: Palette.ringAmber)
            for index in 0..<30 {
                let distance = 140 + Float(index) * 190
                let lateral = sinf(Float(index) * 0.9) * 13
                let vertical = sinf(Float(index) * 0.55) * 8
                let frame = FlightPath.frame(at: distance)
                let entity = ModelEntity(
                    mesh: ringMesh,
                    materials: [index.isMultiple(of: 2) ? cyan : amber]
                )
                entity.name = "Ring\(index)"
                entity.position = frame.offset(lateral: lateral, vertical: vertical)
                entity.orientation = simd_quatf(from: [0, 0, 1], to: frame.forward)
                neonRoot.addChild(entity)
                rings.append(
                    Ring(
                        entity: entity,
                        distance: distance,
                        lateral: lateral,
                        vertical: vertical,
                        radius: 5.4
                    )
                )
            }
        }

        // MARK: Traffic

        var traffic: [Traffic] = []
        let trafficNames = ["CAB 1006", "POLICE 7C5", "RDST 02", "DRONE 12", "CAB 2210", "POLICE 0F9B"]
        let trafficColors: [UIColor] = [
            UIColor(red: 0.92, green: 0.66, blue: 0.08, alpha: 1),
            UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1),
            UIColor(red: 0.42, green: 0.08, blue: 0.09, alpha: 1),
            UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1),
            UIColor(red: 0.20, green: 0.35, blue: 0.55, alpha: 1),
            UIColor(red: 0.62, green: 0.63, blue: 0.64, alpha: 1)
        ]
        var rng = SeededGenerator(seed: 808)
        if let trafficMesh = try? MeshFactory.makeWedge(
            width: 2.3,
            length: 4.6,
            height: 1.0,
            noseHeight: 0.42
        ) {
            for index in 0..<14 {
                let distance = 380 + Float(index) * 380 + Float.random(in: -70...70, using: &rng)
                let lateral = Float.random(in: -19...19, using: &rng)
                let vertical = Float.random(in: -11...11, using: &rng)
                let speed: Float = index.isMultiple(of: 4)
                    ? -Float.random(in: 12...22, using: &rng)
                    : Float.random(in: 10...28, using: &rng)
                let entity = makeTrafficCar(
                    mesh: trafficMesh,
                    color: trafficColors[index % trafficColors.count],
                    name: trafficNames[index % trafficNames.count],
                    accent: index.isMultiple(of: 2) ? Palette.ringCyan : Palette.ringAmber,
                    glowTexture: glowTexture
                )
                entity.name = "Traffic\(index)"
                neonRoot.addChild(entity)
                traffic.append(
                    Traffic(
                        entity: entity,
                        initialDistance: distance,
                        distance: distance,
                        speed: speed,
                        lateral: lateral,
                        vertical: vertical,
                        radius: 3.1
                    )
                )
            }
        }

        // Background traffic streams make the lanes feel alive without adding
        // collision checks.
        var ambientTraffic: [AmbientTraffic] = []
        let ambientColors: [UIColor] = [
            UIColor(white: 0.90, alpha: 1),
            UIColor(red: 0.95, green: 0.72, blue: 0.20, alpha: 1),
            UIColor(red: 0.16, green: 0.30, blue: 0.48, alpha: 1),
            UIColor(red: 0.45, green: 0.08, blue: 0.08, alpha: 1)
        ]
        for index in 0..<60 {
            let distance = Float.random(in: 60...FlightPath.length, using: &rng)
            let lateral = Float.random(in: -22...22, using: &rng)
            let vertical = Float.random(in: -14...14, using: &rng)
            let speed = Float.random(in: 8...34, using: &rng)
            let entity = Entity()
            entity.name = "AmbientTraffic\(index)"
            if let mesh = try? MeshFactory.makeWedge(
                width: 1.3,
                length: 2.6,
                height: 0.62,
                noseHeight: 0.24
            ) {
                let body = ModelEntity(
                    mesh: mesh,
                    materials: [
                        MaterialFactory.pbr(
                            color: ambientColors[index % ambientColors.count],
                            roughness: 0.38,
                            metallic: 0.5
                        )
                    ]
                )
                entity.addChild(body)
                let tail = ModelEntity(
                    mesh: .generateBox(size: [0.85, 0.055, 0.06]),
                    materials: [MaterialFactory.unlit(color: UIColor(red: 1.0, green: 0.12, blue: 0.08, alpha: 1))]
                )
                tail.position = [0, 0.14, -1.31]
                entity.addChild(tail)
                let head = ModelEntity(
                    mesh: .generateBox(size: [0.7, 0.04, 0.04]),
                    materials: [MaterialFactory.unlit(color: Palette.cool)]
                )
                head.position = [0, 0.12, 1.31]
                entity.addChild(head)
            }
            neonRoot.addChild(entity)
            ambientTraffic.append(
                AmbientTraffic(
                    entity: entity,
                    distance: distance,
                    speed: speed,
                    lateral: lateral,
                    vertical: vertical
                )
            )
        }

        addFinishGate(to: root, neonRoot: neonRoot)
        let sun = addSun(glowTexture: glowTexture, to: neonRoot)
        let haze = addHaze(hazeTexture: hazeTexture, to: root)

        root.addChild(neonRoot)

        if #available(iOS 27.0, *) {
            neonRoot.components.set(BloomComponent(scope: .hierarchical))
            var options = BloomOptionsComponent()
            options.strength = 0.82
            options.threshold = 0.72
            options.blurRadius = 9
            neonRoot.components.set(options)
            root.components.set(ToneMappingComponent())
        }

        _ = carbonTexture
        return City(
            root: root,
            neonRoot: neonRoot,
            rings: rings,
            traffic: traffic,
            ambientTraffic: ambientTraffic,
            sky: sky,
            sun: sun,
            haze: haze
        )
    }

    // MARK: - Ground, streets, park

    private static func addGround(
        road: inout BoxBatch,
        sidewalks: inout BoxBatch,
        lanes: inout BoxBatch,
        park: inout BoxBatch
    ) {
        // A large dark base under everything.
        road.addBox(
            center: [0, -0.6, FlightPath.length * 0.5],
            size: [8_000, 1.2, FlightPath.length + 1_200]
        )

        var z: Float = -80
        while z < FlightPath.length + 80 {
            let frame = FlightPath.frame(at: max(0, z))
            let yaw = atan2f(frame.forward.x, frame.forward.z)
            let orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

            // Avenue asphalt under the flight lane.
            road.addBox(
                center: frame.position + SIMD3<Float>(0, -0.04, 0),
                size: [62, 0.12, 72],
                orientation: orientation
            )

            // Sidewalks.
            for side in [-1.0 as Float, 1.0] {
                sidewalks.addBox(
                    center: frame.position + frame.right * (side * 34) + SIMD3<Float>(0, 0.10, 0),
                    size: [8, 0.24, 72],
                    orientation: orientation
                )
            }

            // Lane markings: a double amber center and white edge lines.
            lanes.addBox(
                center: frame.position + SIMD3<Float>(0, 0.035, 0),
                size: [0.16, 0.02, 60],
                orientation: orientation
            )
            for side in [-1.0 as Float, 1.0] {
                lanes.addBox(
                    center: frame.position + frame.right * (side * 24) + SIMD3<Float>(0, 0.035, 0),
                    size: [0.10, 0.02, 60],
                    orientation: orientation
                )
            }

            // Cross street every block.
            if Int(z) % 144 < 4 {
                let crossOrientation = orientation * simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                road.addBox(
                    center: frame.position + SIMD3<Float>(0, -0.035, 0),
                    size: [620, 0.10, 26],
                    orientation: crossOrientation
                )
                sidewalks.addBox(
                    center: frame.position + frame.forward * 17 + SIMD3<Float>(0, 0.10, 0),
                    size: [600, 0.22, 5],
                    orientation: crossOrientation
                )
            }

            z += 12
        }

        // A green park on the right side of the course.
        let parkFrame = FlightPath.frame(at: 2_200)
        park.addBox(
            center: parkFrame.position + parkFrame.right * 285 + SIMD3<Float>(0, 0.08, 0),
            size: [230, 0.2, 900],
            orientation: simd_quatf(
                angle: atan2f(parkFrame.forward.x, parkFrame.forward.z),
                axis: [0, 1, 0]
            )
        )

        // Park paths.
        var parkZ: Float = 1_800
        while parkZ < 2_600 {
            let frame = FlightPath.frame(at: parkZ)
            lanes.addBox(
                center: frame.position + frame.right * 285 + SIMD3<Float>(0, 0.20, 0),
                size: [5, 0.03, 44],
                orientation: simd_quatf(
                    angle: atan2f(frame.forward.x, frame.forward.z),
                    axis: [0, 1, 0]
                )
            )
            parkZ += 46
        }
    }

    private static func addRiverAndBridge(
        waterNormal: TextureResource?,
        stone: inout BoxBatch,
        metal: inout BoxBatch,
        road: inout BoxBatch,
        light: inout BoxBatch,
        to root: Entity
    ) {
        // River plane.
        let riverMesh = MeshResource.generatePlane(width: 260, depth: FlightPath.length + 1_400)
        var waterMaterial = MaterialFactory.pbr(
            color: Palette.water,
            roughness: 0.13,
            metallic: 0.55,
            normal: waterNormal
        )
        waterMaterial.faceCulling = .none
        let river = ModelEntity(mesh: riverMesh, materials: [waterMaterial])
        river.name = "River"
        river.position = [
            -390,
            -0.28,
            FlightPath.length * 0.5
        ]
        river.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(river)

        // River walls.
        for x in [-520.0 as Float, -260.0] {
            stone.addBox(
                center: [x, 1.8, FlightPath.length * 0.5],
                size: [5, 4.2, FlightPath.length + 1_400]
            )
        }

        // Suspension bridge across the river at z = 3000.
        let bridgeZ: Float = 3_000
        let deckY: Float = 9
        road.addBox(
            center: [-390, deckY, bridgeZ],
            size: [280, 1.4, 26]
        )
        // Bridge approach ramps.
        road.addBox(
            center: [-220, deckY * 0.5, bridgeZ],
            size: [80, 0.9, 24],
            orientation: simd_quatf(angle: 0.09, axis: [0, 0, 1])
        )
        road.addBox(
            center: [-560, deckY * 0.5, bridgeZ],
            size: [80, 0.9, 24],
            orientation: simd_quatf(angle: -0.09, axis: [0, 0, 1])
        )

        for x in [-500.0 as Float, -280.0] {
            for zOffset in [-11.0 as Float, 11.0] {
                stone.addBox(
                    center: [x, 34, bridgeZ + zOffset],
                    size: [11, 64, 9]
                )
            }
            metal.addBox(
                center: [x, 68, bridgeZ],
                size: [15, 3, 30]
            )
        }

        // Catenary main cables and vertical suspenders.
        for side in [-1.0 as Float, 1.0] {
            let x = -390 + side * 0
            var previous: SIMD3<Float>?
            for index in 0...24 {
                let t = Float(index) / 24
                let z = bridgeZ - 120 + t * 240
                let y = 67 - sin(t * .pi) * 26
                let point = SIMD3<Float>(x + side * 100, y, z)
                if let previous {
                    let mid = (previous + point) * 0.5
                    let delta = point - previous
                    let length = simd_length(delta)
                    let orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(delta))
                    metal.addBox(
                        center: mid,
                        size: [0.32, 0.32, length],
                        orientation: orientation
                    )
                }
                previous = point
            }
            for index in 0...16 {
                let t = Float(index) / 16
                let z = bridgeZ - 110 + t * 220
                let y = 66 - sin(t * .pi) * 25
                metal.addBox(
                    center: [x + side * 100, y * 0.5 + deckY * 0.5, z],
                    size: [0.12, max(0.2, y - deckY), 0.12]
                )
            }
        }

        // Bridge lamps.
        for index in 0...16 {
            let t = Float(index) / 16
            light.addBox(
                center: [-390, deckY + 2.2, bridgeZ - 110 + t * 220],
                size: [0.35, 0.35, 0.35]
            )
        }
    }

    private static func addParkTrees(trunks: inout BoxBatch, to root: Entity) {
        var rng = SeededGenerator(seed: 0x7EE5)
        var foliageMaterials: [PhysicallyBasedMaterial] = [
            MaterialFactory.pbr(
                color: UIColor(red: 0.10, green: 0.24, blue: 0.10, alpha: 1),
                roughness: 0.92,
                metallic: 0
            ),
            MaterialFactory.pbr(
                color: UIColor(red: 0.16, green: 0.30, blue: 0.12, alpha: 1),
                roughness: 0.92,
                metallic: 0
            ),
            MaterialFactory.pbr(
                color: UIColor(red: 0.26, green: 0.32, blue: 0.12, alpha: 1),
                roughness: 0.92,
                metallic: 0
            )
        ]
        let sphere = MeshResource.generateSphere(radius: 4.2)
        for index in 0..<90 {
            let distance = Float.random(in: 1_820...2_580, using: &rng)
            let lateral = Float.random(in: 210...390, using: &rng)
            let frame = FlightPath.frame(at: distance)
            let base = frame.offset(lateral: lateral, vertical: -40)
            let height = Float.random(in: 8...16, using: &rng)
            trunks.addBox(
                center: SIMD3<Float>(base.x, height * 0.5, base.z),
                size: [0.8, height, 0.8]
            )
            let crown = ModelEntity(
                mesh: sphere,
                materials: [foliageMaterials[index % foliageMaterials.count]]
            )
            crown.name = "TreeCrown\(index)"
            crown.position = SIMD3<Float>(
                base.x,
                height + 2.4,
                base.z
            )
            crown.scale = [
                Float.random(in: 0.55...1.0, using: &rng),
                Float.random(in: 0.7...1.2, using: &rng),
                Float.random(in: 0.55...1.0, using: &rng)
            ]
            root.addChild(crown)
        }
    }

    private static func addStreetDetails(
        cars: inout BoxBatch,
        carLights: inout BoxBatch,
        poles: inout BoxBatch,
        lamps: inout BoxBatch
    ) {
        var rng = SeededGenerator(seed: 0x5EED)
        var z: Float = 20
        while z < FlightPath.length - 20 {
            let frame = FlightPath.frame(at: z)
            let yaw = atan2f(frame.forward.x, frame.forward.z)
            let orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

            // Street lamps along both sidewalks.
            for side in [-1.0 as Float, 1.0] {
                let base = frame.position + frame.right * (side * 38)
                poles.addBox(
                    center: base + SIMD3<Float>(0, 4.2, 0),
                    size: [0.24, 8.4, 0.24]
                )
                lamps.addBox(
                    center: base + SIMD3<Float>(0, 8.5, 0),
                    size: [0.55, 0.35, 0.55]
                )
            }

            // A few parked / moving cars on the avenue.
            if Int(z) % 48 < 8 {
                for _ in 0..<2 {
                    let lane = Float.random(in: -18...18, using: &rng)
                    let length = Float.random(in: 3.6...4.8, using: &rng)
                    let center = frame.position + frame.right * lane + SIMD3<Float>(0, 0.42, 0)
                    cars.addBox(
                        center: center,
                        size: [1.8, 0.75, length],
                        orientation: orientation
                    )
                    carLights.addBox(
                        center: center + orientation.act([0, 0.12, -length * 0.5]),
                        size: [1.35, 0.07, 0.06],
                        orientation: orientation
                    )
                }
            }
            z += 28
        }
    }

    // MARK: - Buildings

    private static func addBuildings(
        bodies: inout [BoxBatch],
        bases: inout [FacadeBatch],
        lits: inout [FacadeBatch],
        roofs: inout BoxBatch,
        metal: inout BoxBatch,
        stone: inout BoxBatch,
        light: inout BoxBatch,
        sign: inout BoxBatch,
        facades: [FacadeTextures]
    ) {
        var rng = SeededGenerator(seed: 2_026)
        var z: Float = 24
        while z < FlightPath.length - 40 {
            let frame = FlightPath.frame(at: z)
            let yaw = atan2f(frame.forward.x, frame.forward.z)
            let orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

            for side in [-1.0 as Float, 1.0] {
                // Keep the river side clear of towers beyond the water.
                let count = Int.random(in: 3...5, using: &rng)
                for index in 0..<count {
                    let lateralBase: Float = side < 0 ? 42 : 42
                    let lateral = side * (
                        lateralBase
                        + Float(index) * 34
                        + Float.random(in: 0...18, using: &rng)
                    )
                    if side < 0 && lateral < -250 { continue }
                    if side > 0 && lateral > 235 && z > 1_700 && z < 2_750 { continue }

                    let localZ = Float.random(in: -24...24, using: &rng)
                    let world = frame.position + frame.right * lateral + frame.forward * localZ
                    let width = Float.random(in: 15...32, using: &rng)
                    let depth = Float.random(in: 15...34, using: &rng)
                    let height = Float.random(in: 36...210, using: &rng)
                    let styleIndex = pickStyle(
                        height: height,
                        lateral: lateral,
                        rng: &rng
                    )
                    let spec = BuildingSpec(
                        center: SIMD3<Float>(world.x, 0, world.z),
                        width: width,
                        depth: depth,
                        height: height,
                        orientation: orientation,
                        styleIndex: styleIndex,
                        seed: UInt64.random(in: 0...UInt64.max, using: &rng),
                        side: side,
                        hasCrown: Bool.random(using: &rng),
                        hasSpire: height > 120 && Bool.random(using: &rng),
                        hasWaterTower: height < 90 && Bool.random(using: &rng),
                        hasBillboard: Bool.random(using: &rng)
                    )
                    addBuilding(
                        spec,
                        bodies: &bodies,
                        bases: &bases,
                        lits: &lits,
                        roofs: &roofs,
                        metal: &metal,
                        stone: &stone,
                        light: &light,
                        sign: &sign,
                        facades: facades
                    )
                }
            }
            z += 72
        }
    }

    private static func pickStyle(
        height: Float,
        lateral: Float,
        rng: inout SeededGenerator
    ) -> Int {
        let roll = Int.random(in: 0..<100, using: &rng)
        if height > 140 { return roll < 70 ? 0 : 3 }
        if abs(lateral) > 120 { return roll < 50 ? 0 : (roll < 80 ? 3 : 1) }
        if roll < 32 { return 0 }
        if roll < 62 { return 1 }
        if roll < 82 { return 2 }
        return 3
    }

    private static func addBuilding(
        _ spec: BuildingSpec,
        bodies: inout [BoxBatch],
        bases: inout [FacadeBatch],
        lits: inout [FacadeBatch],
        roofs: inout BoxBatch,
        metal: inout BoxBatch,
        stone: inout BoxBatch,
        light: inout BoxBatch,
        sign: inout BoxBatch,
        facades: [FacadeTextures]
    ) {
        let style = TextureFactory.styles[spec.styleIndex]
        let orientation = spec.orientation
        let baseY = spec.center.y
        let fullHeight = spec.height

        // One to three stacked masses create the classic New York setback.
        let massCount = fullHeight > 120 ? 3 : (fullHeight > 65 ? 2 : 1)
        var currentHeight: Float = 0
        var currentWidth = spec.width
        var currentDepth = spec.depth
        var remaining = fullHeight

        for mass in 0..<massCount {
            let fraction: Float
            switch mass {
            case 0: fraction = massCount == 1 ? 1.0 : (massCount == 2 ? 0.74 : 0.58)
            case 1: fraction = massCount == 2 ? 0.26 : 0.26
            default: fraction = 0.16
            }
            let massHeight = max(10, remaining * fraction)
            let center = spec.center + SIMD3<Float>(0, currentHeight + massHeight * 0.5, 0)
            let massOrientation = orientation

            bodies[spec.styleIndex].addBox(
                center: center,
                size: [currentWidth, massHeight, currentDepth],
                orientation: massOrientation
            )

            let inset: Float = mass == 0 ? 0.12 : 0.28
            addFacadePair(
                center: center + orientation.act([0, 0, 0]),
                width: currentWidth,
                depth: currentDepth,
                height: massHeight,
                orientation: orientation,
                styleIndex: spec.styleIndex,
                bases: &bases,
                lits: &lits,
                inset: inset
            )

            // Roof cap on every mass gives the setbacks a readable edge.
            roofs.addBox(
                center: center + SIMD3<Float>(0, massHeight * 0.5 + 0.25, 0),
                size: [currentWidth + 0.35, 0.5, currentDepth + 0.35],
                orientation: orientation
            )

            // Ground-floor storefront glow on the avenue-facing side.
            if mass == 0 {
                let faceX = spec.side > 0 ? -currentWidth * 0.5 - 0.15 : currentWidth * 0.5 + 0.15
                light.addBox(
                    center: center + orientation.act([faceX, -massHeight * 0.5 + 3.0, 0]),
                    size: [0.20, 2.2, currentDepth * 0.78],
                    orientation: orientation
                )
            }

            currentHeight += massHeight
            remaining -= massHeight
            currentWidth *= 0.78
            currentDepth *= 0.78
            if remaining <= 6 { break }
        }

        let topY = spec.center.y + currentHeight
        let topWidth = currentWidth / 0.78
        let topDepth = currentDepth / 0.78

        // Art-deco crown / mechanical penthouse.
        if spec.hasCrown {
            let crownHeight = min(16, max(4, fullHeight * 0.045))
            roofs.addBox(
                center: SIMD3<Float>(spec.center.x, topY + crownHeight * 0.5, spec.center.z),
                size: [max(6, topWidth * 0.45), crownHeight, max(6, topDepth * 0.45)],
                orientation: orientation
            )
            let crownGlow = max(0.12, fullHeight * 0.002)
            light.addBox(
                center: SIMD3<Float>(spec.center.x, topY + crownHeight + 0.5, spec.center.z),
                size: [max(6, topWidth * 0.47), 0.5, max(6, topDepth * 0.47)],
                orientation: orientation
            )
            _ = crownGlow
        }

        // Spire / antenna / beacon.
        if spec.hasSpire {
            let spireHeight = min(54, max(12, fullHeight * 0.22))
            metal.addBox(
                center: SIMD3<Float>(spec.center.x, topY + spireHeight * 0.5, spec.center.z),
                size: [1.2, spireHeight, 1.2]
            )
            light.addBox(
                center: SIMD3<Float>(spec.center.x, topY + spireHeight + 0.6, spec.center.z),
                size: [1.0, 1.0, 1.0]
            )
        } else if spec.hasCrown {
            metal.addBox(
                center: SIMD3<Float>(spec.center.x, topY + 8, spec.center.z),
                size: [0.5, 16, 0.5]
            )
        }

        // Rooftop water tower for the older low-rise blocks.
        if spec.hasWaterTower {
            let towerHeight = Float.random(in: 5...9)
            let radius = Float.random(in: 2.2...3.4)
            let base = SIMD3<Float>(spec.center.x, topY + 1.2, spec.center.z)
            for dx in [-1.0 as Float, 1.0] {
                for dz in [-1.0 as Float, 1.0] {
                    metal.addBox(
                        center: base + SIMD3<Float>(dx * radius * 0.6, 1.5, dz * radius * 0.6),
                        size: [0.28, 3, 0.28]
                    )
                }
            }
            let tank = ModelEntity(
                mesh: .generateCylinder(height: towerHeight, radius: radius),
                materials: [
                    MaterialFactory.pbr(
                        color: Palette.wood,
                        roughness: 0.94,
                        metallic: 0
                    )
                ]
            )
            tank.position = base + SIMD3<Float>(0, towerHeight * 0.5 + 3, 0)
            // The tank is added to the batch root later via a temporary entity;
            // use a shared static parent instead.
            waterTowerHost.addChild(tank)
            let cone = ModelEntity(
                mesh: .generateCone(height: 2.2, radius: radius * 1.08),
                materials: [
                    MaterialFactory.pbr(
                        color: UIColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1),
                        roughness: 0.9,
                        metallic: 0
                    )
                ]
            )
            cone.position = base + SIMD3<Float>(0, towerHeight + 4.1, 0)
            waterTowerHost.addChild(cone)
        }

        // A rooftop billboard.
        if spec.hasBillboard && fullHeight < 150 {
            let names = ["NOVA", "AERO", "2028", "SKYLINE", "RDST", "VELOCITY"]
            let name = names[Int.random(in: 0..<names.count, using: &rngForSigns)]
            if let texture = TextureFactory.billboard(
                text: name,
                accent: Bool.random(using: &rngForSigns) ? Palette.ringAmber : Palette.cool,
                background: UIColor(red: 0.035, green: 0.04, blue: 0.055, alpha: 1)
            ) {
                let plane = ModelEntity(
                    mesh: .generatePlane(width: 14, height: 7),
                    materials: [MaterialFactory.unlit(color: .white, texture: texture)]
                )
                plane.position = SIMD3<Float>(
                    spec.center.x + orientation.act([0, 0, -topDepth * 0.5 - 0.2]).x,
                    topY + 10,
                    spec.center.z + orientation.act([0, 0, -topDepth * 0.5 - 0.2]).z
                )
                plane.orientation = orientation * simd_quatf(angle: .pi, axis: [0, 1, 0])
                signHost.addChild(plane)
            }
        }

        // Add a thin stone base at street level for the older styles.
        if spec.styleIndex == 1 || spec.styleIndex == 2 {
            stone.addBox(
                center: SIMD3<Float>(spec.center.x, 2.0, spec.center.z),
                size: [spec.width * 1.02, 4, spec.depth * 1.02],
                orientation: orientation
            )
        }
    }

    private static var waterTowerHost = Entity()
    private static var signHost = Entity()
    private static var rngForSigns = SeededGenerator(seed: 0xB111B0A2D)

    private static func addFacadePair(
        center: SIMD3<Float>,
        width: Float,
        depth: Float,
        height: Float,
        orientation: simd_quatf,
        styleIndex: Int,
        bases: inout [FacadeBatch],
        lits: inout [FacadeBatch],
        inset: Float
    ) {
        let uvScale = SIMD2<Float>(
            max(1, width / 18),
            max(1, height / 30)
        )

        // Four sides, so the skyline holds up when the chase camera swings.
        let sideFaces: [(normalSign: Float, faceX: Float, faceWidth: Float)] = [
            (1, width * 0.5 + inset, depth),
            (-1, -width * 0.5 - inset, depth)
        ]
        for face in sideFaces {
            let normal = orientation.act([face.normalSign, 0, 0])
            let faceCenter = center + orientation.act([face.faceX, 0, 0])
            bases[styleIndex].addFacade(
                center: faceCenter + normal * 0.045,
                width: face.faceWidth,
                height: height,
                orientation: orientation,
                normalSign: face.normalSign,
                uvScale: uvScale
            )
            lits[styleIndex].addFacade(
                center: faceCenter + normal * 0.075,
                width: face.faceWidth,
                height: height,
                orientation: orientation,
                normalSign: face.normalSign,
                uvScale: uvScale
            )
        }

        let frontOrientation = orientation * simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        for zSign in [-1.0 as Float, 1.0] {
            let normal = orientation.act([0, 0, zSign])
            let faceCenter = center + orientation.act([0, 0, zSign * depth * 0.5 + zSign * inset])
            let faceOrientation = zSign > 0 ? frontOrientation * simd_quatf(angle: .pi, axis: [0, 1, 0]) : frontOrientation
            bases[styleIndex].addFacade(
                center: faceCenter + normal * 0.045,
                width: width,
                height: height,
                orientation: faceOrientation,
                normalSign: 1,
                uvScale: SIMD2<Float>(max(1, width / 18), max(1, height / 30))
            )
            lits[styleIndex].addFacade(
                center: faceCenter + normal * 0.075,
                width: width,
                height: height,
                orientation: faceOrientation,
                normalSign: 1,
                uvScale: SIMD2<Float>(max(1, width / 18), max(1, height / 30))
            )
        }
    }

    // MARK: - Landmarks

    private static func addLandmarks(
        bodies: inout [BoxBatch],
        bases: inout [FacadeBatch],
        lits: inout [FacadeBatch],
        roofs: inout BoxBatch,
        metal: inout BoxBatch,
        stone: inout BoxBatch,
        light: inout BoxBatch,
        facades: [FacadeTextures]
    ) {
        // Art-deco tower.
        let decoFrame = FlightPath.frame(at: 1_200)
        let decoCenter = decoFrame.position + decoFrame.right * -96
        addLandmarkTower(
            center: SIMD3<Float>(decoCenter.x, 0, decoCenter.z),
            orientation: simd_quatf(
                angle: atan2f(decoFrame.forward.x, decoFrame.forward.z),
                axis: [0, 1, 0]
            ),
            baseWidth: 44,
            baseDepth: 44,
            height: 238,
            styleIndex: 1,
            spire: true,
            crown: true,
            bases: &bases,
            lits: &lits,
            bodies: &bodies,
            metal: &metal,
            light: &light
        )

        // Glass supertall near the finish.
        let tallFrame = FlightPath.frame(at: finishDistance - 40)
        let tallCenter = tallFrame.position + tallFrame.right * 92
        addLandmarkTower(
            center: SIMD3<Float>(tallCenter.x, 0, tallCenter.z),
            orientation: simd_quatf(
                angle: atan2f(tallFrame.forward.x, tallFrame.forward.z),
                axis: [0, 1, 0]
            ),
            baseWidth: 48,
            baseDepth: 48,
            height: 318,
            styleIndex: 0,
            spire: true,
            crown: true,
            bases: &bases,
            lits: &lits,
            bodies: &bodies,
            metal: &metal,
            light: &light
        )

        // A second glass crown mid-course.
        let midFrame = FlightPath.frame(at: 4_050)
        let midCenter = midFrame.position + midFrame.right * -108
        addLandmarkTower(
            center: SIMD3<Float>(midCenter.x, 0, midCenter.z),
            orientation: simd_quatf(
                angle: atan2f(midFrame.forward.x, midFrame.forward.z),
                axis: [0, 1, 0]
            ),
            baseWidth: 40,
            baseDepth: 40,
            height: 252,
            styleIndex: 3,
            spire: false,
            crown: true,
            bases: &bases,
            lits: &lits,
            bodies: &bodies,
            metal: &metal,
            light: &light
        )

        // The finish gate is a huge holographic hoop.
        _ = stone
    }

    private static func addLandmarkTower(
        center: SIMD3<Float>,
        orientation: simd_quatf,
        baseWidth: Float,
        baseDepth: Float,
        height: Float,
        styleIndex: Int,
        spire: Bool,
        crown: Bool,
        bases: inout [FacadeBatch],
        lits: inout [FacadeBatch],
        bodies: inout [BoxBatch],
        metal: inout BoxBatch,
        light: inout BoxBatch
    ) {
        let levels: [(width: Float, depth: Float, height: Float)] = [
            (baseWidth, baseDepth, height * 0.52),
            (baseWidth * 0.76, baseDepth * 0.76, height * 0.22),
            (baseWidth * 0.52, baseDepth * 0.52, height * 0.16),
            (baseWidth * 0.30, baseDepth * 0.30, height * 0.10)
        ]
        var y: Float = 0
        for level in levels {
            let massCenter = center + SIMD3<Float>(0, y + level.height * 0.5, 0)
            bodies[styleIndex].addBox(
                center: massCenter,
                size: [level.width, level.height, level.depth],
                orientation: orientation
            )
            addFacadePair(
                center: massCenter,
                width: level.width,
                depth: level.depth,
                height: level.height,
                orientation: orientation,
                styleIndex: styleIndex,
                bases: &bases,
                lits: &lits,
                inset: 0.1
            )
            // Emissive crown bands.
            light.addBox(
                center: massCenter + SIMD3<Float>(0, level.height * 0.5, 0),
                size: [level.width * 1.02, 0.55, level.depth * 1.02],
                orientation: orientation
            )
            y += level.height
        }

        if crown {
            let crownHeight: Float = 12
            metal.addBox(
                center: center + SIMD3<Float>(0, y + crownHeight * 0.5, 0),
                size: [baseWidth * 0.24, crownHeight, baseDepth * 0.24],
                orientation: orientation
            )
            light.addBox(
                center: center + SIMD3<Float>(0, y + crownHeight + 0.7, 0),
                size: [baseWidth * 0.28, 0.8, baseDepth * 0.28],
                orientation: orientation
            )
            y += crownHeight
        }

        if spire {
            let spireHeight: Float = height * 0.22
            metal.addBox(
                center: center + SIMD3<Float>(0, y + spireHeight * 0.5, 0),
                size: [1.2, spireHeight, 1.2]
            )
            light.addBox(
                center: center + SIMD3<Float>(0, y + spireHeight + 0.6, 0),
                size: [1.2, 1.2, 1.2]
            )
        }
    }

    private static func addDistantSkyline(to batch: inout BoxBatch) {
        var rng = SeededGenerator(seed: 0xD157A)
        for index in 0..<220 {
            let z = Float.random(in: -200...FlightPath.length + 400, using: &rng)
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let x = side * Float.random(in: 560...1_050, using: &rng)
            let width = Float.random(in: 30...90, using: &rng)
            let depth = Float.random(in: 30...90, using: &rng)
            let height = Float.random(in: 70...320, using: &rng)
            batch.addBox(
                center: [x, height * 0.5, z],
                size: [width, height, depth]
            )
            _ = index
        }
    }

    // MARK: - Finish gate / sun / haze

    private static func addFinishGate(to root: Entity, neonRoot: Entity) {
        let frame = FlightPath.frame(at: finishDistance)
        let orientation = simd_quatf(from: [0, 0, 1], to: frame.forward)

        if let gateMesh = try? MeshFactory.makeTorus(
            majorRadius: 28,
            minorRadius: 0.9,
            majorSegments: 40,
            minorSegments: 8
        ) {
            let gate = ModelEntity(
                mesh: gateMesh,
                materials: [MaterialFactory.unlit(color: Palette.ringAmber)]
            )
            gate.name = "FinishGate"
            gate.position = frame.position
            gate.orientation = orientation
            neonRoot.addChild(gate)
        }

        let bannerText = "FINISH // 2028"
        if let texture = TextureFactory.label(text: bannerText, accent: Palette.ringAmber, wide: true) {
            let plane = ModelEntity(
                mesh: .generatePlane(width: 34, height: 7),
                materials: [MaterialFactory.unlit(color: .white, texture: texture, transparent: true)]
            )
            plane.name = "FinishBanner"
            plane.position = frame.position + frame.up * 28
            plane.orientation = simd_quatf(from: [0, 0, 1], to: -frame.forward)
            root.addChild(plane)
        }

        for side in [-1.0 as Float, 1.0] {
            let pillar = ModelEntity(
                mesh: .generateBox(size: [1.4, 22, 1.4]),
                materials: [
                    MaterialFactory.pbr(
                        color: Palette.metal,
                        roughness: 0.35,
                        metallic: 0.85
                    )
                ]
            )
            pillar.position = frame.position
                + frame.right * side * 31
                + SIMD3<Float>(0, -frame.position.y + 11, 0)
            neonRoot.addChild(pillar)
        }
    }

    private static func addSun(glowTexture: TextureResource?, to parent: Entity) -> Entity {
        let sun = Entity()
        sun.name = "Sun"
        if let glowTexture {
            let plane = ModelEntity(
                mesh: .generatePlane(width: 210, height: 210),
                materials: [
                    MaterialFactory.unlit(
                        color: UIColor(red: 1.0, green: 0.74, blue: 0.46, alpha: 1),
                        texture: glowTexture,
                        transparent: true
                    )
                ]
            )
            plane.name = "SunDisk"
            plane.components.set(BillboardComponent())
            sun.addChild(plane)
        }
        parent.addChild(sun)
        return sun
    }

    private static func addHaze(hazeTexture: TextureResource?, to parent: Entity) -> Entity {
        let haze = Entity()
        haze.name = "Haze"
        if let hazeTexture {
            let plane = ModelEntity(
                mesh: .generatePlane(width: 5_200, height: 1_600),
                materials: [
                    MaterialFactory.unlit(
                        color: .white,
                        texture: hazeTexture,
                        transparent: true
                    )
                ]
            )
            plane.name = "HazePlane"
            plane.components.set(BillboardComponent())
            haze.addChild(plane)
        }
        parent.addChild(haze)
        return haze
    }

    // MARK: - Traffic car

    private static func makeTrafficCar(
        mesh: MeshResource,
        color: UIColor,
        name: String,
        accent: UIColor,
        glowTexture: TextureResource?
    ) -> Entity {
        let entity = Entity()
        let body = ModelEntity(
            mesh: mesh,
            materials: [
                MaterialFactory.pbr(
                    color: color,
                    roughness: 0.26,
                    metallic: 0.6
                )
            ]
        )
        entity.addChild(body)

        let cabin = ModelEntity(
            mesh: .generateBox(size: [1.25, 0.34, 1.75], cornerRadius: 0.08),
            materials: [
                MaterialFactory.pbr(
                    color: UIColor(red: 0.02, green: 0.03, blue: 0.045, alpha: 1),
                    roughness: 0.04,
                    metallic: 0.2,
                    clearcoat: 1,
                    clearcoatRoughness: 0.02
                )
            ]
        )
        cabin.position = [0, 0.46, -0.15]
        entity.addChild(cabin)

        let tail = ModelEntity(
            mesh: .generateBox(size: [1.55, 0.075, 0.08]),
            materials: [MaterialFactory.unlit(color: UIColor(red: 1.0, green: 0.10, blue: 0.08, alpha: 1))]
        )
        tail.position = [0, 0.25, -2.28]
        entity.addChild(tail)

        let head = ModelEntity(
            mesh: .generateBox(size: [1.45, 0.05, 0.05]),
            materials: [MaterialFactory.unlit(color: Palette.cool)]
        )
        head.position = [0, 0.22, 2.26]
        entity.addChild(head)

        for x in [-0.45, 0.45] as [Float] {
            let thruster = ModelEntity(
                mesh: .generateCylinder(height: 0.12, radius: 0.12),
                materials: [MaterialFactory.unlit(color: accent)]
            )
            thruster.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            thruster.position = [x, 0.22, -2.36]
            entity.addChild(thruster)
        }

        if let glowTexture,
           let labelTexture = TextureFactory.label(
               text: name,
               accent: accent
           ) {
            let label = ModelEntity(
                mesh: .generatePlane(width: 6.4, height: 1.6),
                materials: [
                    MaterialFactory.unlit(
                        color: .white,
                        texture: labelTexture,
                        transparent: true
                    )
                ]
            )
            label.name = "Label"
            label.position = [0, 2.1, 0]
            label.components.set(BillboardComponent())
            entity.addChild(label)
            _ = glowTexture
        }
        return entity
    }

    // MARK: - Batch helpers

    private static func addBatch(
        _ batch: BoxBatch,
        name: String,
        material: PhysicallyBasedMaterial,
        to parent: Entity
    ) {
        guard !batch.isEmpty, let mesh = try? batch.makeMesh(name: name) else { return }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        parent.addChild(entity)
    }

    private static func addBatch(
        _ batch: BoxBatch,
        name: String,
        material: UnlitMaterial,
        to parent: Entity
    ) {
        guard !batch.isEmpty, let mesh = try? batch.makeMesh(name: name) else { return }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        parent.addChild(entity)
    }

    private static func addFacadeBatch(
        _ batch: FacadeBatch,
        name: String,
        material: PhysicallyBasedMaterial,
        to parent: Entity
    ) {
        guard !batch.isEmpty, let mesh = try? batch.makeMesh(name: name) else { return }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        parent.addChild(entity)
    }

    private static func addFacadeBatch(
        _ batch: FacadeBatch,
        name: String,
        material: UnlitMaterial,
        to parent: Entity
    ) {
        guard !batch.isEmpty, let mesh = try? batch.makeMesh(name: name) else { return }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        parent.addChild(entity)
    }
}
