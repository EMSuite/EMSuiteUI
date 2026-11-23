import simd

/// Plain crystal data, as the real component will take it: atoms in Å (Cartesian, crystal frame), bonds as index pairs,
/// the cell as three column vectors.
struct SpikeAtom { var position: SIMD3<Double>; var z: Int }
struct SpikeScene {
    var atoms: [SpikeAtom]
    var bonds: [(Int, Int)]
    var cell: simd_double3x3          // one conventional cell, drawn as the box
    var outline: simd_double3x3       // the whole block, for framing
}

enum SpikeGeometry {
    /// Diamond silicon, a = 5.4309 Å, repeated n1 x n2 x n3 and completed on the far faces, bonds below 2.6 Å.
    static func silicon(_ n1: Int, _ n2: Int, _ n3: Int) -> SpikeScene {
        let a = 5.4309
        let basis: [SIMD3<Double>] = [
            [0, 0, 0], [0, 0.5, 0.5], [0.5, 0, 0.5], [0.5, 0.5, 0],
            [0.25, 0.25, 0.25], [0.25, 0.75, 0.75], [0.75, 0.25, 0.75], [0.75, 0.75, 0.25],
        ]
        var atoms: [SpikeAtom] = []
        let eps = 1e-6
        for i in 0...n1 { for j in 0...n2 { for k in 0...n3 {
            for f in basis {
                let fr = f + SIMD3(Double(i), Double(j), Double(k))
                // complete the block: keep atoms with fractional coordinates within [0, n] inclusive
                if fr.x > Double(n1) + eps || fr.y > Double(n2) + eps || fr.z > Double(n3) + eps { continue }
                atoms.append(SpikeAtom(position: fr * a, z: 14))
            }
        }}}
        let bonds = bondsByDistance(atoms, cutoff: 2.6)
        let cell = simd_double3x3(diagonal: [a, a, a])
        let outline = simd_double3x3(diagonal: [a * Double(n1), a * Double(n2), a * Double(n3)])
        return SpikeScene(atoms: atoms, bonds: bonds, cell: cell, outline: outline)
    }

    /// Bonds by distance with a bin grid (the real component gets bonds from DiffractoKit; this only feeds the spike).
    static func bondsByDistance(_ atoms: [SpikeAtom], cutoff: Double) -> [(Int, Int)] {
        var bins: [SIMD3<Int>: [Int]] = [:]
        func key(_ p: SIMD3<Double>) -> SIMD3<Int> { SIMD3(Int((p.x / cutoff).rounded(.down)), Int((p.y / cutoff).rounded(.down)), Int((p.z / cutoff).rounded(.down))) }
        for (i, a) in atoms.enumerated() { bins[key(a.position), default: []].append(i) }
        var out: [(Int, Int)] = []
        let c2 = cutoff * cutoff
        for (i, a) in atoms.enumerated() {
            let k = key(a.position)
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                guard let list = bins[k &+ SIMD3(dx, dy, dz)] else { continue }
                for j in list where j > i {
                    let d = atoms[j].position - a.position
                    let r2 = simd_dot(d, d)
                    if r2 < c2 && r2 > 0.01 { out.append((i, j)) }
                }
            }}}
        }
        return out
    }

    /// The rotation that puts the zone axis [uvw] along +z (towards the viewer; the beam runs into the screen) with
    /// `up` (a crystal direction) as close to +y as it can be.
    static func zoneAxisRotation(_ uvw: SIMD3<Double>, up: SIMD3<Double>) -> simd_quatd {
        let z = simd_normalize(uvw)
        var y = up - simd_dot(up, z) * z
        if simd_length(y) < 1e-9 { y = simd_cross(z, [1, 0, 0]) }
        y = simd_normalize(y)
        let x = simd_cross(y, z)
        // rows of the crystal->view matrix are the view axes in the crystal frame
        let m = simd_double3x3(rows: [x, y, z])
        return simd_quatd(m)
    }
}
