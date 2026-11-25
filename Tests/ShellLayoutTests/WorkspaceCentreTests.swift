// The shared centre of every room (EMSuiteUI#261): the divider's arithmetic in CentreSplitModel and the arrangement
// WorkspaceCentre is built with.

import CoreGraphics
import SwiftUI
import XCTest
@testable import ShellLayout

nonisolated final class WorkspaceCentreTests: XCTestCase {

    // MARK: - Clamping

    /// Dragged past either end, the divider stops where the panel beyond it keeps its floor.
    func testTheFractionIsClampedAtBothEnds() {
        let model = CentreSplitModel(minimumLeading: 180, minimumTrailing: 240)
        let usable: CGFloat = 1000
        XCTAssertEqual(model.clamped(0, usable: usable), 0.18, accuracy: 1e-12, "the leading panel keeps 180 pt")
        XCTAssertEqual(model.clamped(-3, usable: usable), 0.18, accuracy: 1e-12)
        XCTAssertEqual(model.clamped(1, usable: usable), 0.76, accuracy: 1e-12, "the trailing panel keeps 240 pt")
        XCTAssertEqual(model.clamped(7, usable: usable), 0.76, accuracy: 1e-12)
        XCTAssertEqual(model.clamped(0.4, usable: usable), 0.4, "inside the bounds a fraction is left alone")
        XCTAssertEqual(model.clamped(.nan, usable: usable), 0.5, "a fraction that is not a number becomes the default")
    }

    /// Below the two floors together there is no arrangement that honours both, so the centre is halved.
    func testBelowBothFloorsTheCentreIsHalved() {
        let model = CentreSplitModel(minimumLeading: 180, minimumTrailing: 180)
        XCTAssertEqual(model.bounds(usable: 300), 0.5...0.5)
        XCTAssertEqual(model.clamped(0.1, usable: 300), 0.5)
        XCTAssertEqual(model.clamped(0.9, usable: 0), 0.5)
    }

    /// With equal floors the clamp is PaneSplit's own, which is what WorkspaceCentre draws through.
    func testEqualFloorsClampAsPaneSplitDoes() {
        let model = CentreSplitModel(minimumLeading: 180, minimumTrailing: 180)
        for usable: CGFloat in [100, 300, 360, 361, 900, 2400] {
            let smallest = Double(PaneSplit<EmptyView, EmptyView>.smallestFraction(minimumPane: 180, usable: usable))
            XCTAssertEqual(model.bounds(usable: usable).lowerBound, smallest, accuracy: 1e-12, "usable \(usable)")
            XCTAssertEqual(model.bounds(usable: usable).upperBound, 1 - smallest, accuracy: 1e-12, "usable \(usable)")
        }
    }

    /// The widths add up to the centre less the divider's line, and the leading one is a whole point.
    func testTheTwoWidthsFillTheCentre() {
        let model = CentreSplitModel()
        let total: CGFloat = 901
        let widths = model.widths(fraction: 0.5, total: total)
        XCTAssertEqual(widths.leading, 450)
        XCTAssertEqual(widths.leading + widths.trailing, total - LayoutPolicy.sciencePaneDividerWidth)
        let dragged = model.widths(fraction: 0.01, total: total)
        XCTAssertEqual(dragged.leading, LayoutPolicy.imagePaneMinimum, "a drag to the edge leaves the floor")
    }

    // MARK: - Default, reset and the stored fraction

    func testNothingStoredStartsAtTheDefault() {
        XCTAssertEqual(CentreSplitModel().restored(nil), 0.5, "the default default is the middle")
        let model = CentreSplitModel(defaultFraction: 0.62)
        XCTAssertEqual(model.restored(nil), 0.62)
        XCTAssertEqual(model.restored(.nan), 0.62, "nothing usable stored is nothing stored")
        XCTAssertEqual(model.restored(1.5), 0.62)
        XCTAssertEqual(CentreSplitModel(defaultFraction: .infinity).defaultFraction, 0.5)
        XCTAssertEqual(CentreSplitModel(defaultFraction: 2).defaultFraction, 1)
    }

    func testResetReturnsTheDefault() {
        XCTAssertEqual(CentreSplitModel(defaultFraction: 0.35).resetFraction, 0.35)
        XCTAssertEqual(CentreSplitModel().resetFraction, 0.5)
    }

    func testAStoredFractionRoundTrips() {
        let model = CentreSplitModel(defaultFraction: 0.3)
        for stored in [0.0, 0.25, 0.5, 0.731, 1.0] {
            XCTAssertEqual(model.restored(stored), stored)
        }
        // Each room has its own slot, and the key is stable (a saved window keeps its split across releases).
        XCTAssertEqual(CentreSplitModel.storageKey(room: "edx"), "workspace.centre.edx.fraction")
        XCTAssertNotEqual(CentreSplitModel.storageKey(room: "edx"), CentreSplitModel.storageKey(room: "eels"))
        XCTAssertNotEqual(CentreSplitModel.storageKey(room: "edx"), ShellStorageKeys.paneSplitFraction)
    }

    // MARK: - One panel or two

    func testASinglePanelHasNoDivider() {
        let single = CentreSplitModel(arrangement: .single)
        XCTAssertFalse(single.hasDivider)
        let widths = single.widths(fraction: 0.3, total: 800)
        XCTAssertEqual(widths.leading, 800, "one panel takes the whole centre")
        XCTAssertEqual(widths.trailing, 0)
        XCTAssertTrue(CentreSplitModel(arrangement: .split).hasDivider)
    }

    @MainActor
    func testTheCentreViewsAreBuiltWithTheirArrangement() {
        let one = WorkspaceCentre { EmptyView() }
        XCTAssertEqual(one.model.arrangement, .single)
        XCTAssertFalse(one.model.hasDivider)

        let two = WorkspaceCentre(storageKey: CentreSplitModel.storageKey(room: "test"), defaultFraction: 0.4) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
        XCTAssertEqual(two.model.arrangement, .split)
        XCTAssertTrue(two.model.hasDivider)
        XCTAssertEqual(two.model.defaultFraction, 0.4)
        XCTAssertEqual(two.model.minimumLeading, LayoutPolicy.imagePaneMinimum)
    }
}
