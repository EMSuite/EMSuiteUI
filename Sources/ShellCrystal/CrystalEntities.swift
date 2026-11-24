//
//  CrystalEntities.swift
//  Role: the RealityKit entity tree of a CrystalScene. One sphere mesh instanced per element (MeshInstancesComponent with
//        LowLevelInstanceData, macOS 26), one cylinder mesh instanced per element for half-bonds (each bond is drawn as two halves in
//        the colours of its two atoms, as VESTA does), twelve unlit edges for the cell. Scene units: 1 Å = 1 cm, so lights and
//        shadows behave at a table-top scale. Lights hang on the root, not on the pivot: they stay with the camera while the
//        crystal turns, so the light always comes from the upper left as the user sees it.
//

import AppKit
import RealityKit
import simd

/// The built tree: `root` goes into the content, `pivot` takes the orientation.
struct CrystalEntities {
    let root: Entity
    let pivot: Entity
    /// The radius in scene units that holds everything drawn; the camera frames it.
    let radius: Float

    /// Metres per Å in the scene.
    static let unit: Float = 0.01
    /// Bond radius in Å.
    static let bondRadius: Float = 0.16
    /// Cell edge radius in Å; heavier under Increase Contrast.
    static func edgeRadius(increasedContrast: Bool) -> Float { increasedContrast ? 0.06 : 0.035 }

    static func material(_ c: SIMD3<Double>) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: 1))
        m.roughness = .init(floatLiteral: 0.38)
        m.metallic = .init(floatLiteral: 0)
        m.clearcoat = .init(floatLiteral: 0.35)
        m.clearcoatRoughness = .init(floatLiteral: 0.2)
        return m
    }

    @MainActor
    static func build(_ scene: CrystalScene, showsUnitCell: Bool, increasedContrast: Bool) throws -> CrystalEntities {
        let unit = Self.unit
        let root = Entity(), pivot = Entity(), content = Entity()
        root.addChild(pivot)
        pivot.addChild(content)
        content.position = SIMD3<Float>(-scene.centre) * unit

        let (sphere, sphereTriangles) = try atomMesh()
        let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
        let positions = scene.atoms.map { SIMD3<Float>($0.position) * unit }

        // Atoms, instanced per element.
        var byElement: [Int: [Int]] = [:]
        for (i, a) in scene.atoms.enumerated() { byElement[a.atomicNumber, default: []].append(i) }
        for (z, indices) in byElement.sorted(by: { $0.key < $1.key }) {
            let r = Float(CrystalElements.ballRadius(z: z)) * unit
            let transforms = indices.map { Transform(scale: SIMD3(repeating: r), rotation: identity, translation: positions[$0]).matrix }
            try addInstances(of: sphere, triangles: sphereTriangles, material: material(CrystalPalette.color(z: z)),
                             transforms: transforms, name: "atoms-\(z)", to: content)
        }

        // Half-bonds, instanced per element of the atom each half leaves.
        var halves: [Int: [float4x4]] = [:]
        let br = bondRadius * unit
        for bond in scene.bonds where scene.atoms.indices.contains(bond.a) && scene.atoms.indices.contains(bond.b) {
            let pa = positions[bond.a], pb = positions[bond.b], mid = (pa + pb) / 2
            halves[scene.atoms[bond.a].atomicNumber, default: []].append(segment(from: pa, to: mid, radius: br))
            halves[scene.atoms[bond.b].atomicNumber, default: []].append(segment(from: pb, to: mid, radius: br))
        }
        let cylinderTriangles = triangleCount(cylinder)
        for (z, transforms) in halves.sorted(by: { $0.key < $1.key }) {
            try addInstances(of: cylinder, triangles: cylinderTriangles,
                             material: material(CrystalPalette.color(z: z) * CrystalPalette.bondShade),
                             transforms: transforms, name: "bonds-\(z)", to: content)
        }

        // The unit cell, or a slab's outline in its place (#232).
        if showsUnitCell, let cell = scene.box {
            let e = CrystalPalette.cellEdge
            var edgeMaterial = UnlitMaterial(color: NSColor(srgbRed: e.x, green: e.y, blue: e.z, alpha: 1))
            edgeMaterial.blending = .transparent(opacity: .init(floatLiteral: increasedContrast ? 1.0 : 0.75))
            let corners = CrystalScene.unitCorners.map { SIMD3<Float>(cell * $0) * unit }
            let er = edgeRadius(increasedContrast: increasedContrast) * unit
            let transforms = CrystalScene.unitEdges.map { segment(from: corners[$0.0], to: corners[$0.1], radius: er) }
            try addInstances(of: cylinder, triangles: triangleCount(cylinder), material: edgeMaterial, transforms: transforms,
                             name: "cell", to: content)
        }

        // Light from the upper left and in front, with a soft fill from the lower right.
        let key = DirectionalLight()
        key.light.intensity = 2600
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 1.0, depthBias: 2)
        key.look(at: .zero, from: [-0.6, 0.8, 1.0], relativeTo: nil)
        root.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [0.8, -0.3, 0.6], relativeTo: nil)
        root.addChild(fill)

        return CrystalEntities(root: root, pivot: pivot, radius: Float(scene.boundingRadius) * unit)
    }

    /// The identity rotation. (`simd_quatf()` is the zero quaternion, not the identity: MU0.)
    static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// The atom's unit icosphere as a RealityKit mesh, and its triangle count.
    @MainActor
    static func atomMesh() throws -> (MeshResource, Int) {
        let sphere = CrystalMesh.icosphere(subdivisions: CrystalMesh.atomSubdivisions)
        var descriptor = MeshDescriptor(name: "atom")
        descriptor.positions = MeshBuffers.Positions(sphere.vertices)
        descriptor.normals = MeshBuffers.Normals(sphere.vertices)
        descriptor.primitives = .triangles(sphere.triangles)
        return (try MeshResource.generate(from: [descriptor]), sphere.triangles.count / 3)
    }

    /// The triangles of a generated mesh (for batching).
    @MainActor
    static func triangleCount(_ mesh: MeshResource) -> Int {
        mesh.contents.models.reduce(0) { sum, model in sum + model.parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 } }
    }

    /// Adds `transforms` as instances of `mesh`, in batches RealityKit draws (MU0: one component stops drawing past 2 to 4 M
    /// triangles), each with its own bounds.
    @MainActor
    static func addInstances(of mesh: MeshResource, triangles: Int, material: RealityKit.Material, transforms: [float4x4],
                             name: String, to parent: Entity) throws {
        let extent = mesh.bounds.extents.max() / 2
        for range in CrystalMesh.batches(count: transforms.count, trianglesPerInstance: max(1, triangles)) {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            let data = try LowLevelInstanceData(instanceCount: range.count)
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            data.withMutableTransforms { t in
                for (k, i) in range.enumerated() {
                    let m = transforms[i]
                    t[k] = m
                    let centre = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                    let reach = extent * max(simd_length(m.columns.0), simd_length(m.columns.1), simd_length(m.columns.2))
                    lo = simd_min(lo, centre - reach); hi = simd_max(hi, centre + reach)
                }
            }
            entity.components.set(try MeshInstancesComponent(mesh: mesh, modelID: nil, instances: data,
                                                             bounds: BoundingBox(min: lo, max: hi)))
            entity.name = name
            parent.addChild(entity)
        }
    }

    /// The transform that stretches the unit cylinder (height 1 along y, radius 1) from `a` to `b`.
    static func segment(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float) -> float4x4 {
        let d = b - a
        let length = simd_length(d)
        guard length > 0 else { return Transform(scale: .zero, rotation: identity, translation: a).matrix }
        return Transform(scale: [radius, length, radius], rotation: simd_quatf(from: [0, 1, 0], to: d / length),
                         translation: (a + b) / 2).matrix
    }

    /// The fixed camera: on the beam, looking into the screen, parallel projection framing a sphere of `radius`.
    @MainActor
    static func camera(radius: Float, aspect: Float) -> Entity {
        let camera = Entity()
        var ortho = OrthographicCameraComponent()
        ortho.scale = orthographicScale(radius: radius, aspect: aspect)
        let depth = depth(radius: radius)
        ortho.near = 0.001
        ortho.far = depth.far
        camera.components.set(ortho)
        camera.look(at: .zero, from: [0, 0, depth.distance], relativeTo: nil)
        camera.name = "camera"
        return camera
    }

    /// The camera's distance from the centre and its far plane for a sphere of `radius` (scene units): the whole sphere lies between
    /// the near and far planes whatever the turn, so a long `repeats:` block or a 40 nm slab keeps its front and back (#232). A small
    /// cell keeps the distance 2 and far plane 10 it always had; the picture is parallel, so the distance changes only the clipping.
    nonisolated static func depth(radius: Float) -> (distance: Float, far: Float) {
        let distance = max(2, 2 * radius + 0.1)
        return (distance, max(10, distance + 2 * radius + 1))
    }

    /// The orthographic camera's `scale` for a sphere of `radius` with a margin, so it fits the shorter side of the pane.
    /// RealityKit's scale is the half-height of the view volume (vertical scale direction), measured in MU0.
    nonisolated static func orthographicScale(radius: Float, aspect: Float) -> Float {
        let margin: Float = 1.08
        let halfHeight = radius * margin
        return aspect >= 1 ? halfHeight : halfHeight / max(aspect, 0.1)
    }
}
