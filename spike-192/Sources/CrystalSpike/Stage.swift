import AppKit
import RealityKit
import simd

/// Builds the RealityKit entity tree for a SpikeScene. 1 Å = 1 cm in scene units, so lights and shadows work at a
/// table-top scale. The returned `pivot` is the entity the drag turns; the camera never moves.
@MainActor
enum SpikeStage {
    static let unit: Float = 0.01      // metres per Å

    enum Mode: String { case instanced, entities }
    enum Lighting: String { case studio, plain }

    struct Built { let root: Entity; let pivot: Entity; let extent: Float; let drawn: Int }

    // Our own colour for Si for the spike (the real palette is MU1's one file).
    static let siliconColor = NSColor(srgbRed: 0.86, green: 0.74, blue: 0.58, alpha: 1)
    static let bondColor = NSColor(srgbRed: 0.62, green: 0.53, blue: 0.43, alpha: 1)

    static func material(_ color: NSColor) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: 0.38)
        m.metallic = .init(floatLiteral: 0.0)
        m.clearcoat = .init(floatLiteral: 0.35)
        m.clearcoatRoughness = .init(floatLiteral: 0.2)
        return m
    }

    static func build(_ scene: SpikeScene, mode: Mode, lighting: Lighting) throws -> Built {
        let root = Entity()
        let pivot = Entity()
        root.addChild(pivot)
        let content = Entity()
        pivot.addChild(content)
        // centre the block on the pivot
        let o = scene.outline
        let centre = (o.columns.0 + o.columns.1 + o.columns.2) * 0.5
        content.position = SIMD3<Float>(-centre) * unit

        let atomRadius: Float = 0.62 * unit
        let bondRadius: Float = 0.17 * unit
        let sphere = MeshResource.generateSphere(radius: 1)
        let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
        let atomMat = material(siliconColor)
        let bondMat = material(bondColor)

        let positions = scene.atoms.map { SIMD3<Float>($0.position) * unit }
        func bondTransform(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> float4x4 {
            let d = b - a
            let len = simd_length(d)
            let q = simd_quatf(from: [0, 1, 0], to: d / len)
            return Transform(scale: [bondRadius, len, bondRadius], rotation: q, translation: (a + b) * 0.5).matrix
        }

        switch mode {
        case .instanced:
            // One MeshInstancesComponent silently draws nothing past roughly 2-4 M triangles (measured on macOS 27.0.1:
            // 95 spheres of 8064 triangles draw, 621 do not; 8192 cylinders of 256 draw, 16000 do not), so the
            // instances go out in chunks of at most 1 M triangles each.
            func addInstanced(_ mesh: MeshResource, _ mat: RealityKit.Material, _ transforms: [float4x4]) throws {
                let tris = max(1, mesh.contents.models.reduce(0) { $0 + $1.parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 } })
                let per = max(1, 1_000_000 / tris)
                var i = 0
                while i < transforms.count {
                    let chunk = transforms[i..<min(i + per, transforms.count)]
                    let e = ModelEntity(mesh: mesh, materials: [mat])
                    let data = try LowLevelInstanceData(instanceCount: chunk.count)
                    data.withMutableTransforms { t in for (k, m) in chunk.enumerated() { t[k] = m } }
                    e.components.set(try MeshInstancesComponent(mesh: mesh, modelID: nil, instances: data, bounds: nil))
                    content.addChild(e)
                    i += per
                }
            }
            // simd_quatf() is the zero quaternion, not the identity; written out here.
            try addInstanced(sphere, atomMat, positions.map {
                Transform(scale: SIMD3(repeating: atomRadius), rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), translation: $0).matrix })
            try addInstanced(cylinder, bondMat, scene.bonds.map { bondTransform(positions[$0.0], positions[$0.1]) })
        case .entities:
            for p in positions {
                let e = ModelEntity(mesh: sphere, materials: [atomMat])
                e.transform = Transform(scale: SIMD3(repeating: atomRadius), rotation: simd_quatf(), translation: p)
                content.addChild(e)
            }
            for pair in scene.bonds {
                let e = ModelEntity(mesh: cylinder, materials: [bondMat])
                e.transform = Transform(matrix: bondTransform(positions[pair.0], positions[pair.1]))
                content.addChild(e)
            }
        }

        // The unit cell: 12 thin unlit edges.
        var edgeMat = UnlitMaterial(color: NSColor(white: 0.92, alpha: 1))
        edgeMat.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        let c = scene.cell
        let unitCorners: [SIMD3<Double>] = [[0,0,0],[1,0,0],[0,1,0],[0,0,1],[1,1,0],[1,0,1],[0,1,1],[1,1,1]]
        let corners = unitCorners.map { c * $0 }
        let edges = [(0,1),(0,2),(0,3),(1,4),(1,5),(2,4),(2,6),(3,5),(3,6),(4,7),(5,7),(6,7)]
        for (i, j) in edges {
            let a = SIMD3<Float>(corners[i]) * unit, b = SIMD3<Float>(corners[j]) * unit
            let d = b - a, len = simd_length(d)
            let e = ModelEntity(mesh: cylinder, materials: [edgeMat])
            e.transform = Transform(scale: [0.035 * unit, len, 0.035 * unit], rotation: simd_quatf(from: [0, 1, 0], to: d / len), translation: (a + b) * 0.5)
            content.addChild(e)
        }

        // Lights ride on the root, not the pivot: they stay with the camera while the crystal turns.
        if lighting == .studio {
            let key = DirectionalLight()
            key.light.intensity = 2600
            key.light.color = NSColor(white: 1, alpha: 1)
            key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 1.0, depthBias: 2)
            key.look(at: .zero, from: [-0.6, 0.8, 1.0], relativeTo: nil)
            root.addChild(key)
            let fill = DirectionalLight()
            fill.light.intensity = 900
            fill.look(at: .zero, from: [0.8, -0.3, 0.6], relativeTo: nil)
            root.addChild(fill)
        }

        let ext = SIMD3<Float>(o.columns.0 + o.columns.1 + o.columns.2) * unit
        return Built(root: root, pivot: pivot, extent: simd_length(ext), drawn: positions.count)
    }

    static func camera(scale: Float, perspective: Bool = false) -> Entity {
        let cam = Entity()
        if perspective {
            var p = PerspectiveCameraComponent()
            p.fieldOfViewInDegrees = 30
            cam.components.set(p)
        } else {
            var oc = OrthographicCameraComponent()
            oc.scale = scale
            oc.near = 0.001
            oc.far = 10
            cam.components.set(oc)
        }
        cam.look(at: .zero, from: [0, 0, 2], relativeTo: nil)
        return cam
    }
}
