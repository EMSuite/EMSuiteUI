//
//  CrystalScene.swift
//  Role: what the crystal view draws, as plain data: atoms in Å in the crystal's Cartesian frame, bonds as pairs of those atoms, and
//        the cell. No kit is imported (the target stands alone): the app maps DiffractoKit's structure and its bonds (row K8) into
//        `CrystalSite` and `CrystalBondInput`, and `CrystalScene.unitCell` lays them out the way VESTA draws one cell: atoms repeated
//        on the faces, edges and corners they touch (diamond Si draws 18 atoms, fcc Al 14), and each bond drawn where both ends are.
//

import simd

/// One atom as drawn.
public nonisolated struct CrystalAtom: Equatable, Sendable {
    /// Position in Å, Cartesian, crystal frame.
    public var position: SIMD3<Double>
    public var atomicNumber: Int
    /// Site occupancy; below 1 the atom is drawn as a part-filled ball (2.5). 1 for a fully occupied site.
    public var occupancy: Double
    /// The index of the site (in the input list) this atom is an image of; the hover chip and the legend count by it.
    public var site: Int

    public init(position: SIMD3<Double>, atomicNumber: Int, occupancy: Double = 1, site: Int = 0) {
        self.position = position; self.atomicNumber = atomicNumber; self.occupancy = occupancy; self.site = site
    }
}

/// One drawn bond: two indices into `CrystalScene.atoms`.
public nonisolated struct CrystalBond: Equatable, Hashable, Sendable {
    public var a: Int
    public var b: Int
    public init(_ a: Int, _ b: Int) { self.a = min(a, b); self.b = max(a, b) }
}

/// A site of the structure, as the app hands it over: fractional coordinates in the cell.
public nonisolated struct CrystalSite: Equatable, Sendable {
    public var fractional: SIMD3<Double>
    public var atomicNumber: Int
    public var occupancy: Double
    public init(fractional: SIMD3<Double>, atomicNumber: Int, occupancy: Double = 1) {
        self.fractional = fractional; self.atomicNumber = atomicNumber; self.occupancy = occupancy
    }
}

/// A bond as DiffractoKit reports it (pymatgen's convention): from site `from` in the home cell to site `to` in the cell shifted
/// by `image` lattice vectors.
public nonisolated struct CrystalBondInput: Equatable, Sendable {
    public var from: Int
    public var to: Int
    public var image: SIMD3<Int>
    public init(from: Int, to: Int, image: SIMD3<Int> = .zero) { self.from = from; self.to = to; self.image = image }
}

/// Everything the crystal view draws.
public nonisolated struct CrystalScene: Equatable, Sendable {
    public var atoms: [CrystalAtom]
    public var bonds: [CrystalBond]
    /// Columns a, b, c in Å: the unit cell box and the a, b, c triad. Nil for a model without a cell.
    public var cell: simd_double3x3?
    /// A slab's box in Å (2.5), drawn in place of the cell. Nil for a unit cell.
    public var outline: SIMD3<Double>?

    public init(atoms: [CrystalAtom], bonds: [CrystalBond] = [], cell: simd_double3x3? = nil, outline: SIMD3<Double>? = nil) {
        self.atoms = atoms; self.bonds = bonds; self.cell = cell; self.outline = outline
    }

    /// An empty scene: the view shows only the stage.
    public static let empty = CrystalScene(atoms: [])

    /// How close (in fractional units) a coordinate must be to 0 or 1 to count as on a face.
    public static let faceTolerance = 1e-4

    /// One unit cell drawn as VESTA draws it, repeated `repeats` times along a, b and c (1, 1, 1 for one cell). Sites are wrapped
    /// into [0, 1); a site on a face, edge or corner of the block appears on every face it touches. A bond is drawn wherever both
    /// of its ends are drawn atoms.
    public static func unitCell(cell: simd_double3x3, sites: [CrystalSite], bonds: [CrystalBondInput] = [],
                                repeats: SIMD3<Int> = .one) -> CrystalScene {
        let n = SIMD3<Int>(max(1, repeats.x), max(1, repeats.y), max(1, repeats.z))
        let tol = faceTolerance
        var atoms: [CrystalAtom] = []
        // The drawn images of each site, keyed by their integer cell offset, for the bond lookup.
        var imageIndex: [ImageKey: Int] = [:]
        for (s, site) in sites.enumerated() {
            let f = wrapped(site.fractional)
            // Per axis, the integer shifts that keep this site inside [0, n] (a site at 0 also appears at n).
            func shifts(_ x: Double, _ count: Int) -> [Int] {
                var out = Array(0..<count)
                if x < tol { out.append(count) }
                return out
            }
            for i in shifts(f.x, n.x) { for j in shifts(f.y, n.y) { for k in shifts(f.z, n.z) {
                let shift = SIMD3<Int>(i, j, k)
                let frac = f + SIMD3<Double>(shift)
                imageIndex[ImageKey(site: s, shift: shift)] = atoms.count
                atoms.append(CrystalAtom(position: cell * frac, atomicNumber: site.atomicNumber, occupancy: site.occupancy, site: s))
            }}}
        }
        // A bond (from, to, image) joins site `from` drawn at shift t with site `to` drawn at shift t + image - w(from) + w(to),
        // where w is the integer shift `wrapped` took off each site's input coordinates.
        var drawn = Set<CrystalBond>()
        let wraps = sites.map { wrapShift($0.fractional) }
        for bond in bonds where sites.indices.contains(bond.from) && sites.indices.contains(bond.to) {
            let delta = bond.image &- wraps[bond.from] &+ wraps[bond.to]
            for (key, a) in imageIndex where key.site == bond.from {
                if let b = imageIndex[ImageKey(site: bond.to, shift: key.shift &+ delta)], a != b {
                    drawn.insert(CrystalBond(a, b))
                }
            }
        }
        let sorted = drawn.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
        return CrystalScene(atoms: atoms, bonds: sorted, cell: cell)
    }

    /// The centre of what is drawn: the middle of the outline, else of the cell block spanned by the atoms' cell, else of the atoms.
    public var centre: SIMD3<Double> {
        if let o = outline { return o / 2 }
        if atoms.isEmpty { return cell.map { ($0.columns.0 + $0.columns.1 + $0.columns.2) / 2 } ?? .zero }
        var lo = atoms[0].position, hi = lo
        for a in atoms { lo = simd_min(lo, a.position); hi = simd_max(hi, a.position) }
        if let c = cell {
            for corner in Self.unitCorners { let p = c * corner; lo = simd_min(lo, p); hi = simd_max(hi, p) }
        }
        return (lo + hi) / 2
    }

    /// The box drawn as twelve edges: a slab's outline (from the origin to `outline`, drawn in place of the cell), else the unit cell;
    /// nil when there is neither. Columns are the box's three edge vectors in Å.
    public var box: simd_double3x3? {
        if let o = outline { return simd_double3x3(diagonal: o) }
        return cell
    }

    /// The radius of the sphere around `centre` that holds every atom's ball and the cell: the view frames this, so the crystal
    /// never leaves the pane as it turns.
    public var boundingRadius: Double {
        let c = centre
        var r = 0.0
        for a in atoms { r = max(r, simd_length(a.position - c) + CrystalElements.ballRadius(z: a.atomicNumber)) }
        if let cell { for corner in Self.unitCorners { r = max(r, simd_length(cell * corner - c)) } }
        if let o = outline { r = max(r, simd_length(o) / 2) }
        return max(r, 1)
    }

    /// Atom counts per element, heaviest first by count then by atomic number: the legend's rows and VoiceOver's value.
    public var elementCounts: [(atomicNumber: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for a in atoms { counts[a.atomicNumber, default: 0] += 1 }
        return counts.map { (atomicNumber: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.atomicNumber < $1.atomicNumber }
    }

    /// The eight corners of the unit cube, in the order the cell edges use.
    static let unitCorners: [SIMD3<Double>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [1, 0, 1], [0, 1, 1], [1, 1, 1]]
    /// The twelve edges of the unit cube, as pairs of `unitCorners`.
    static let unitEdges: [(Int, Int)] = [(0, 1), (0, 2), (0, 3), (1, 4), (1, 5), (2, 4), (2, 6), (3, 5), (3, 6), (4, 7), (5, 7), (6, 7)]

    private struct ImageKey: Hashable { let site: Int; let shift: SIMD3<Int> }

    /// Fractional coordinates wrapped into [0, 1), with values within `faceTolerance` of 1 snapped to 0.
    static func wrapped(_ f: SIMD3<Double>) -> SIMD3<Double> {
        func w(_ x: Double) -> Double {
            var y = x - x.rounded(.down)
            if y > 1 - faceTolerance || y < faceTolerance { y = 0 }
            return y
        }
        return SIMD3(w(f.x), w(f.y), w(f.z))
    }

    /// The integer shift that `wrapped` applied to each coordinate (wrapped = f - shift, up to the snap).
    static func wrapShift(_ f: SIMD3<Double>) -> SIMD3<Int> {
        func s(_ x: Double) -> Int { Int((x + faceTolerance).rounded(.down)) }
        return SIMD3(s(f.x), s(f.y), s(f.z))
    }
}
