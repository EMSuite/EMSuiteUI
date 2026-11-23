import CoreGraphics
import Foundation
import simd
import XCTest
@testable import ShellCrystal

/// The view's own projection (hover chip, symbols under Differentiate Without Color) and how outside changes are shown.
nonisolated final class CrystalProjectionTests: XCTestCase {

    static let size = CGSize(width: 400, height: 300)

    /// The bounding sphere fills the shorter side with the camera's margin, and the centre lands in the middle of the pane.
    func testProjectionFramesLikeTheCamera() {
        let scene = CrystalGeometryTests.silicon()
        let m = CrystalTurn.lookingDown([0, 0, 1], up: [0, 1, 0])
        let p = CrystalProjection(scene: scene, orientation: m, size: Self.size)
        XCTAssertEqual(p.scale, 150 / (scene.boundingRadius * CrystalProjection.margin), accuracy: 1e-9)
        let c = p.project(scene.centre)
        XCTAssertEqual(Double(c.point.x), 200, accuracy: 1e-9); XCTAssertEqual(Double(c.point.y), 150, accuracy: 1e-9)
        // b is up on screen: a point further along b has a smaller y
        let up = p.project(scene.centre + [0, 1, 0])
        XCTAssertLessThan(up.point.y, c.point.y)
        // a tall pane frames on the width
        let tall = CrystalProjection(scene: scene, orientation: m, size: CGSize(width: 200, height: 400))
        XCTAssertEqual(tall.scale, 100 / (scene.boundingRadius * CrystalProjection.margin), accuracy: 1e-9)
    }

    /// Hovering a column picks the atom nearest the viewer; empty stage picks nothing.
    func testHoverPicksTheFrontMostAtom() {
        let scene = CrystalScene(atoms: [CrystalAtom(position: [0, 0, 0], atomicNumber: 14),
                                         CrystalAtom(position: [0, 0, 4], atomicNumber: 8),
                                         CrystalAtom(position: [0, 0, -4], atomicNumber: 26)])
        let m = CrystalTurn.lookingDown([0, 0, 1], up: [0, 1, 0])
        let p = CrystalProjection(scene: scene, orientation: m, size: Self.size)
        let middle = p.project([0, 0, 0]).point
        XCTAssertEqual(p.atom(at: middle, in: scene), 1, "oxygen at z = +4 is nearest the viewer")
        // turned 180° about y, iron is in front
        let flipped = CrystalTurn.turned(m, by: CrystalTurn.rotation(angle: .pi, axis: [0, 1, 0]))
        let q = CrystalProjection(scene: scene, orientation: flipped, size: Self.size)
        XCTAssertEqual(q.atom(at: q.project([0, 0, 0]).point, in: scene), 2)
        XCTAssertNil(p.atom(at: CGPoint(x: 5, y: 5), in: scene))
    }

    /// Symbols go only on atoms not hidden behind a nearer one: down [001] a column of three shows one label.
    func testSymbolsSkipHiddenAtoms() {
        let scene = CrystalScene(atoms: [CrystalAtom(position: [0, 0, 0], atomicNumber: 14),
                                         CrystalAtom(position: [0, 0, 4], atomicNumber: 8),
                                         CrystalAtom(position: [3, 0, 0], atomicNumber: 26)])
        let p = CrystalProjection(scene: scene, orientation: CrystalTurn.lookingDown([0, 0, 1], up: [0, 1, 0]), size: Self.size)
        let labels = p.labelledAtoms(in: scene)
        XCTAssertEqual(Set(labels.map(\.index)), [1, 2])
        XCTAssertEqual(p.labelledAtoms(in: scene, limit: 1).count, 1)
    }

    /// Outside changes spin, or crossfade under Reduce Motion; drags and key steps are set at once.
    func testMotionRule() {
        let a = CrystalTurn.lookingDown([0, 0, 1], up: [0, 1, 0])
        let b = CrystalTurn.lookingDown([1, 1, 0], up: [0, 0, 1])
        XCTAssertEqual(CrystalMotion.transition(from: a, to: b, dragging: false, reduceMotion: false), .spin)
        XCTAssertEqual(CrystalMotion.transition(from: a, to: b, dragging: false, reduceMotion: true), .crossfade)
        XCTAssertEqual(CrystalMotion.transition(from: a, to: b, dragging: true, reduceMotion: false), .none)
        let step = CrystalTurn.turned(a, by: CrystalTurn.step(.tiltLeft))
        XCTAssertEqual(CrystalMotion.transition(from: a, to: step, dragging: false, reduceMotion: true), .none)
    }
}

/// The state the agent door reads back (app #846).
nonisolated final class CrystalSummaryTests: XCTestCase {
    func testSummaryRoundTripsAndNamesTheView() throws {
        let scene = CrystalGeometryTests.silicon()
        let m = CrystalTurn.lookingDown(scene.cell! * [1, 1, 0], up: scene.cell! * [0, 0, 1])
        let summary = CrystalSummary(scene: scene, orientation: m, showsUnitCell: true)
        XCTAssertEqual(summary.atoms, 18)
        XCTAssertEqual(summary.bonds, 16)
        XCTAssertEqual(summary.elements, [CrystalSummary.Element(atomicNumber: 14, symbol: "Si", atoms: 18)])
        XCTAssertEqual(summary.cellLengths?[0] ?? 0, 5.4309, accuracy: 1e-12)
        XCTAssertEqual(summary.viewDirection[0], 1 / 2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(summary.viewDirection[1], 1 / 2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(summary.orientationRows[0][0], m.columns.0.x, accuracy: 0)
        XCTAssertEqual(summary.orientationRows[0][2], m.columns.2.x, accuracy: 0)
        let data = try JSONEncoder().encode(summary)
        XCTAssertEqual(try JSONDecoder().decode(CrystalSummary.self, from: data), summary)
        XCTAssertFalse(CrystalSummary(scene: .empty, orientation: m, showsUnitCell: true).showsUnitCell)
    }
}
