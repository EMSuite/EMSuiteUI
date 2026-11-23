//
//  CrystalMesh.swift
//  Role: the atom's mesh and the instance batching, sized by what the MU0 spike measured (#192). RealityKit's generateSphere has
//        8 064 triangles, which makes a 20 000-atom slab triangle-bound; an icosphere of 1 280 triangles looks as round at pane size.
//        And one MeshInstancesComponent silently draws nothing past roughly 2 to 4 million triangles, so instances go out in
//        batches of at most `maxTrianglesPerBatch`.
//

import simd

/// Geometry of the crystal view's meshes, independent of RealityKit so it is tested without a GPU.
public nonisolated enum CrystalMesh {
    /// The most triangles one instanced entity draws (well under the 2 to 4 million at which RealityKit stops drawing).
    public static let maxTrianglesPerBatch = 1_000_000

    /// Subdivisions of the icosahedron for an atom: 3 gives 1 280 triangles and 642 vertices.
    public static let atomSubdivisions = 3

    /// A unit icosphere: vertices (which are also the normals) and triangles wound counter-clockwise seen from outside.
    public static func icosphere(subdivisions: Int) -> (vertices: [SIMD3<Float>], triangles: [UInt32]) {
        let t = Float((1 + 5.0.squareRoot()) / 2)
        var vertices: [SIMD3<Float>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ].map { simd_normalize($0) }
        var faces: [SIMD3<UInt32>] = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ]
        for _ in 0..<max(0, subdivisions) {
            var midpoints: [UInt64: UInt32] = [:]
            func midpoint(_ a: UInt32, _ b: UInt32) -> UInt32 {
                let key = (UInt64(min(a, b)) << 32) | UInt64(max(a, b))
                if let m = midpoints[key] { return m }
                vertices.append(simd_normalize((vertices[Int(a)] + vertices[Int(b)]) / 2))
                let m = UInt32(vertices.count - 1)
                midpoints[key] = m
                return m
            }
            var next: [SIMD3<UInt32>] = []
            next.reserveCapacity(faces.count * 4)
            for f in faces {
                let ab = midpoint(f.x, f.y), bc = midpoint(f.y, f.z), ca = midpoint(f.z, f.x)
                next += [[f.x, ab, ca], [f.y, bc, ab], [f.z, ca, bc], [ab, bc, ca]]
            }
            faces = next
        }
        return (vertices, faces.flatMap { [$0.x, $0.y, $0.z] })
    }

    /// Splits `count` instances of a mesh with `trianglesPerInstance` triangles into batches under `maxTrianglesPerBatch`.
    public static func batches(count: Int, trianglesPerInstance: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let per = max(1, maxTrianglesPerBatch / max(1, trianglesPerInstance))
        return stride(from: 0, to: count, by: per).map { $0..<min($0 + per, count) }
    }
}
