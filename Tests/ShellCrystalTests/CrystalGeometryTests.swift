import simd
import XCTest
@testable import ShellCrystal

/// The crystal view's data, without a screen: palette, element data, the unit-cell layout and the orientation convention.
nonisolated final class CrystalGeometryTests: XCTestCase {

    // MARK: - Fixtures

    static let siA = 5.4309
    static let diamond: [SIMD3<Double>] = [[0, 0, 0], [0, 0.5, 0.5], [0.5, 0, 0.5], [0.5, 0.5, 0],
                                           [0.25, 0.25, 0.25], [0.25, 0.75, 0.75], [0.75, 0.25, 0.75], [0.75, 0.75, 0.25]]

    /// Every Si-Si bond below 2.6 Å as (from, to, image), the way DiffractoKit reports bonds (pymatgen's convention).
    static func bonds(_ sites: [SIMD3<Double>], a: Double, cutoff: Double, reach: Int = 1) -> [CrystalBondInput] {
        var out: [CrystalBondInput] = []
        for (i, fi) in sites.enumerated() { for (j, fj) in sites.enumerated() {
            for x in -reach...reach { for y in -reach...reach { for z in -reach...reach {
                let image = SIMD3<Int>(x, y, z)
                let d = simd_length((fj + SIMD3<Double>(image) - fi) * a)
                if d > 0.01, d < cutoff { out.append(CrystalBondInput(from: i, to: j, image: image)) }
            }}}
        }}
        return out
    }

    static func silicon(shift: SIMD3<Double> = .zero, repeats: SIMD3<Int> = .one) -> CrystalScene {
        let sites = diamond.map { CrystalSite(fractional: $0 + shift, atomicNumber: 14) }
        let cell = simd_double3x3(diagonal: SIMD3(repeating: siA))
        let reach = shift == .zero ? 1 : 2
        return CrystalScene.unitCell(cell: cell, sites: sites, bonds: bonds(diamond.map { $0 + shift }, a: siA, cutoff: 2.6, reach: reach),
                                     repeats: repeats)
    }

    // MARK: - Palette

    /// Every element reads at 3:1 or better against the dark stage, the bar the plan sets (and the stage stays dark in light mode).
    func testEveryElementReadsAtThreeToOneOnTheStage() {
        XCTAssertEqual(CrystalPalette.table.count, 118)
        for z in 1...118 {
            let c = CrystalPalette.contrast(CrystalPalette.color(z: z), CrystalPalette.stage)
            XCTAssertGreaterThanOrEqual(c, 3.0, "\(CrystalElements.symbol(z: z)) reads at \(c):1")
        }
        XCTAssertGreaterThanOrEqual(CrystalPalette.contrast(CrystalPalette.unknown, CrystalPalette.stage), 3.0)
        XCTAssertGreaterThanOrEqual(CrystalPalette.contrast(CrystalPalette.cellEdge, CrystalPalette.stage), 3.0)
    }

    /// The hues a chemist expects: oxygen red, nitrogen blue, sulfur yellow, carbon and hydrogen without hue.
    func testFamiliarHues() {
        let o = CrystalPalette.color(z: 8), n = CrystalPalette.color(z: 7), s = CrystalPalette.color(z: 16)
        let c = CrystalPalette.color(z: 6), h = CrystalPalette.color(z: 1)
        XCTAssertTrue(o.x > o.y + 0.3 && o.x > o.z + 0.3, "oxygen is red")
        XCTAssertTrue(n.z > n.x + 0.3 && n.z > n.y, "nitrogen is blue")
        XCTAssertTrue(s.x > 0.8 && s.y > 0.7 && s.z < 0.4, "sulfur is yellow")
        XCTAssertEqual(c.x, c.y, accuracy: 0.01); XCTAssertEqual(c.y, c.z, accuracy: 0.01)
        XCTAssertEqual(h.x, h.z, accuracy: 0.01)
        XCTAssertGreaterThan(CrystalPalette.luminance(h), CrystalPalette.luminance(c), "hydrogen lighter than carbon")
    }

    func testOutOfRangeElementsNeverTrap() {
        XCTAssertEqual(CrystalPalette.color(z: 0), CrystalPalette.unknown)
        XCTAssertEqual(CrystalPalette.color(z: 119), CrystalPalette.unknown)
        XCTAssertEqual(CrystalElements.symbol(z: 0), "Z=0")
        XCTAssertEqual(CrystalElements.name(z: 200), "element 200")
        XCTAssertEqual(CrystalElements.covalentRadius(z: 120), CrystalElements.fallbackRadius)
    }

    // MARK: - Element data

    func testElementTablesLineUp() {
        XCTAssertEqual(CrystalElements.symbols.count, 118)
        XCTAssertEqual(CrystalElements.names.count, 118)
        XCTAssertEqual(CrystalElements.covalentRadii.count, 96, "H to Cm")
        XCTAssertEqual(CrystalElements.symbol(z: 14), "Si"); XCTAssertEqual(CrystalElements.name(z: 14), "Silicon")
        XCTAssertEqual(CrystalElements.symbol(z: 96), "Cm"); XCTAssertEqual(CrystalElements.name(z: 96), "Curium")
        XCTAssertEqual(CrystalElements.symbol(z: 118), "Og"); XCTAssertEqual(CrystalElements.name(z: 118), "Oganesson")
        // Cordero 2008 spot checks
        XCTAssertEqual(CrystalElements.covalentRadius(z: 1), 0.31)
        XCTAssertEqual(CrystalElements.covalentRadius(z: 8), 0.66)
        XCTAssertEqual(CrystalElements.covalentRadius(z: 14), 1.11)
        XCTAssertEqual(CrystalElements.covalentRadius(z: 26), 1.32)
        XCTAssertEqual(CrystalElements.covalentRadius(z: 55), 2.44)
        XCTAssertEqual(CrystalElements.covalentRadius(z: 79), 1.36)
        XCTAssertEqual(CrystalElements.covalentRadius(z: 92), 1.96)
    }

    // MARK: - One unit cell, as VESTA draws it

    /// Diamond Si draws 18 atoms (8 corners, 6 faces, 4 inside) and the 16 bonds of its 4 inner atoms, all 2.3516 Å long.
    func testDiamondSiliconDrawsEighteenAtomsAndSixteenBonds() {
        let scene = Self.silicon()
        XCTAssertEqual(scene.atoms.count, 18)
        XCTAssertEqual(scene.bonds.count, 16)
        for bond in scene.bonds {
            XCTAssertEqual(simd_length(scene.atoms[bond.a].position - scene.atoms[bond.b].position), Self.siA * sqrt(3) / 4, accuracy: 1e-9)
        }
        XCTAssertEqual(Set(scene.bonds).count, scene.bonds.count, "no bond drawn twice")
    }

    /// The same structure given with sites outside [0, 1) (and bonds to match) draws the same cell.
    func testSitesOutsideTheCellWrapIn() {
        let home = Self.silicon(), moved = Self.silicon(shift: [1, 0, -1])
        XCTAssertEqual(moved.atoms.count, home.atoms.count)
        XCTAssertEqual(moved.bonds.count, home.bonds.count)
        let a = Set(home.atoms.map { SIMD3<Int>(($0.position * 1000).rounded(.toNearestOrEven)) })
        let b = Set(moved.atoms.map { SIMD3<Int>(($0.position * 1000).rounded(.toNearestOrEven)) })
        XCTAssertEqual(a, b)
    }

    /// fcc Al draws 14 atoms and no bonds (a metal: DiffractoKit's VESTA rule gives none).
    func testFccAluminiumDrawsFourteen() {
        let sites: [SIMD3<Double>] = [[0, 0, 0], [0, 0.5, 0.5], [0.5, 0, 0.5], [0.5, 0.5, 0]]
        let scene = CrystalScene.unitCell(cell: simd_double3x3(diagonal: SIMD3(repeating: 4.0495)),
                                          sites: sites.map { CrystalSite(fractional: $0, atomicNumber: 13) })
        XCTAssertEqual(scene.atoms.count, 14)
        XCTAssertTrue(scene.bonds.isEmpty)
    }

    /// A coordinate a hair under 1 counts as on the face (CIF rounding), not as an atom just inside it.
    func testNearlyOneSnapsToTheFace() {
        let scene = CrystalScene.unitCell(cell: simd_double3x3(diagonal: [4, 4, 4]),
                                          sites: [CrystalSite(fractional: [0.99999, 0.5, 0.5], atomicNumber: 29)])
        XCTAssertEqual(scene.atoms.count, 2)
        XCTAssertEqual(Set(scene.atoms.map { $0.position.x }), [0, 4])
    }

    /// Repeating 2 x 2 x 2 completes the block: 95 atoms and 128 bonds for diamond Si.
    func testRepeatsCompleteTheBlock() {
        let scene = Self.silicon(repeats: [2, 2, 2])
        XCTAssertEqual(scene.atoms.count, 95)
        XCTAssertEqual(scene.bonds.count, 128)
    }

    func testFramingHoldsEveryBall() {
        let scene = Self.silicon()
        XCTAssertEqual(scene.centre.x, Self.siA / 2, accuracy: 1e-9)
        for atom in scene.atoms {
            XCTAssertLessThanOrEqual(simd_length(atom.position - scene.centre) + CrystalElements.ballRadius(z: 14), scene.boundingRadius + 1e-9)
        }
    }

    // MARK: - Orientation convention

    /// [001] looks down c: c points at the viewer, out of the screen.
    func testLookingDown001PutsCOutOfTheScreen() {
        let cell = simd_double3x3(diagonal: [4, 4, 4])
        let m = CrystalTurn.lookingDown(cell * [0, 0, 1], up: cell * [0, 1, 0])
        let c = CrystalTurn.viewRotation(m) * cell.columns.2
        XCTAssertEqual(c.x, 0, accuracy: 1e-12); XCTAssertEqual(c.y, 0, accuracy: 1e-12); XCTAssertEqual(c.z, 4, accuracy: 1e-12)
        let b = CrystalTurn.viewRotation(m) * cell.columns.1
        XCTAssertEqual(b.y, 4, accuracy: 1e-12, "b is up")
        let a = CrystalTurn.viewRotation(m) * cell.columns.0
        XCTAssertEqual(a.x, 4, accuracy: 1e-12, "a is right: a right-handed frame")
        XCTAssertEqual(simd_determinant(m), 1, accuracy: 1e-12)
    }

    /// Si down [110]: the atoms project onto the dumbbell columns. Pairs of atoms 1.36 Å apart along [001] on screen (a/4),
    /// and every atom of a column shares its screen position with the atom a [110] translation further on.
    func testSiliconDown110ShowsTheDumbbells() {
        let scene = Self.silicon()
        let cell = scene.cell!
        let m = CrystalTurn.lookingDown(cell * [1, 1, 0], up: cell * [0, 0, 1])
        let r = CrystalTurn.viewRotation(m)
        let screen = scene.atoms.map { r * $0.position }
        // the dumbbell: atoms at (0,0,0) and (1/4,1/4,1/4) are a/4 apart vertically and coincide horizontally
        let p0 = r * (cell * SIMD3<Double>(0, 0, 0)), p1 = r * (cell * SIMD3<Double>(0.25, 0.25, 0.25))
        XCTAssertEqual(p1.x - p0.x, 0, accuracy: 1e-9)
        XCTAssertEqual(p1.y - p0.y, Self.siA / 4, accuracy: 1e-9)
        // projected columns: distinct x positions are multiples of a√2/4
        let step = Self.siA * sqrt(2) / 4
        for s in screen {
            let k = (s.x / step).rounded()
            XCTAssertEqual(s.x, k * step, accuracy: 1e-9)
        }
    }

    /// A drag to the right turns the near side of the crystal to the right; down, down; ⌥ right, clockwise.
    func testDragDirections() {
        let toward: SIMD3<Double> = [0, 0, 1]
        let right = CrystalTurn.drag(translation: [40, 0], rotatesInPlane: false) * toward
        XCTAssertGreaterThan(right.x, 0)
        let down = CrystalTurn.drag(translation: [0, 40], rotatesInPlane: false) * toward
        XCTAssertLessThan(down.y, 0)
        let up: SIMD3<Double> = [0, 1, 0]
        let clockwise = CrystalTurn.drag(translation: [40, 0], rotatesInPlane: true) * up
        XCTAssertGreaterThan(clockwise.x, 0, "the top moves right: clockwise")
        XCTAssertEqual(CrystalTurn.angle(from: matrix_identity_double3x3,
                                         to: CrystalTurn.drag(translation: [400, 0], rotatesInPlane: false)), .pi, accuracy: 1e-9)
    }

    /// The keys tilt by 1°, opposite keys undo each other, and a turn acts in view axes whatever the orientation.
    func testKeyStepsAreOneDegreeAndInViewAxes() {
        let m = CrystalTurn.lookingDown([1, 1, 1], up: [0, 0, 1])
        for d in CrystalTurnDirection.allCases {
            let after = CrystalTurn.turned(m, by: CrystalTurn.step(d))
            XCTAssertEqual(CrystalTurn.angle(from: m, to: after), .pi / 180, accuracy: 1e-9, d.rawValue)
        }
        let back = CrystalTurn.turned(CrystalTurn.turned(m, by: CrystalTurn.step(.tiltLeft)), by: CrystalTurn.step(.tiltRight))
        XCTAssertEqual(CrystalTurn.angle(from: m, to: back), 0, accuracy: 1e-9)
        // In-plane rotation keeps the beam direction: the zone axis stays out of the screen.
        let rotated = CrystalTurn.turned(m, by: CrystalTurn.step(.rotateClockwise, angle: 0.3))
        let axis = CrystalTurn.viewRotation(rotated) * simd_normalize(SIMD3<Double>(1, 1, 1))
        XCTAssertEqual(axis.z, 1, accuracy: 1e-12)
        // A tilt moves it off the beam by exactly the step.
        let tilted = CrystalTurn.turned(m, by: CrystalTurn.step(.tiltUp))
        XCTAssertEqual(acos((CrystalTurn.viewRotation(tilted) * simd_normalize(SIMD3<Double>(1, 1, 1))).z), .pi / 180, accuracy: 1e-9)
    }

    func testManySmallTurnsStayARotation() {
        var m = CrystalTurn.lookingDown([1, 2, 3], up: [0, 0, 1])
        for i in 0..<5000 { m = CrystalTurn.turned(m, by: CrystalTurn.drag(translation: [Double(i % 7), 3], rotatesInPlane: i % 3 == 0)) }
        m = CrystalTurn.orthonormalized(m)
        XCTAssertEqual(simd_determinant(m), 1, accuracy: 1e-12)
        let i3 = m.transpose * m
        XCTAssertEqual(i3.columns.0.x, 1, accuracy: 1e-12); XCTAssertEqual(i3.columns.0.y, 0, accuracy: 1e-12)
    }

    // MARK: - Words

    func testVoiceOverValueAndLegend() {
        let scene = Self.silicon()
        XCTAssertEqual(CrystalDescription.value(scene, showsUnitCell: true), "18 atoms: 18 silicon, 16 bonds, unit cell shown")
        XCTAssertEqual(CrystalDescription.value(.empty, showsUnitCell: true), "No atoms")
        let perovskite = CrystalScene(atoms: [CrystalAtom(position: .zero, atomicNumber: 38), CrystalAtom(position: .one, atomicNumber: 22),
                                              CrystalAtom(position: [1, 0, 0], atomicNumber: 8), CrystalAtom(position: [0, 1, 0], atomicNumber: 8),
                                              CrystalAtom(position: [0, 0, 1], atomicNumber: 8)])
        XCTAssertEqual(CrystalDescription.value(perovskite, showsUnitCell: false), "5 atoms: 3 oxygen, 1 titanium, 1 strontium")
        XCTAssertEqual(CrystalDescription.legend(perovskite).map(\.symbol), ["O", "Ti", "Sr"])
    }
}
