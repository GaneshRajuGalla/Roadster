import Foundation
import RealityKit

final class World {
    let root = Entity()
    init() {
        initLayout()
        // Minimal: ground plane
        let ground = ModelEntity(mesh: .generatePlane(width: 500, depth: 500), materials: [SimpleMaterial(color: .darkGray, isMetallic: false)])
        ground.position = .zero
        root.addChild(ground)
    }
}
EOF