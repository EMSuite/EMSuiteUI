//
//  CrystalSummary.swift
//  Role: the crystal view's state as plain data, with no window: what the agent door's get_crystal_view reads back (app #846),
//        beside `CrystalSnapshot.image` for the picture. The phase and the zone axis are the app's to add; this holds what the view
//        draws and how it is turned.
//

import simd

/// What the crystal view shows, as Codable data.
public nonisolated struct CrystalSummary: Codable, Equatable, Sendable {
    /// One element drawn and how many of its atoms.
    public struct Element: Codable, Equatable, Sendable {
        public var atomicNumber: Int
        public var symbol: String
        public var atoms: Int
    }

    public var atoms: Int
    public var bonds: Int
    public var elements: [Element]
    public var showsUnitCell: Bool
    /// Cell lengths a, b, c in Å, when the scene has a cell.
    public var cellLengths: [Double]?
    /// The orientation matrix row by row (py4DSTEM's convention: columns are the view x, y, z axes in the crystal frame).
    public var orientationRows: [[Double]]
    /// The direction towards the viewer (the beam reversed) in the crystal's Cartesian frame, unit length.
    public var viewDirection: [Double]

    public init(scene: CrystalScene, orientation: simd_double3x3, showsUnitCell: Bool) {
        atoms = scene.atoms.count
        bonds = scene.bonds.count
        elements = scene.elementCounts.map {
            Element(atomicNumber: $0.atomicNumber, symbol: CrystalElements.symbol(z: $0.atomicNumber), atoms: $0.count)
        }
        self.showsUnitCell = showsUnitCell && scene.cell != nil
        cellLengths = scene.cell.map { [simd_length($0.columns.0), simd_length($0.columns.1), simd_length($0.columns.2)] }
        let t = orientation.transpose
        orientationRows = [t.columns.0, t.columns.1, t.columns.2].map { [$0.x, $0.y, $0.z] }
        let z = orientation.columns.2
        viewDirection = [z.x, z.y, z.z]
    }
}
