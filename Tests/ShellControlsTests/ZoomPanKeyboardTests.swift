//
//  ZoomPanKeyboardTests.swift
//  View > Pan Left, Right, Up and Down (EMSuiteUI#126): the keyboard's drag on the pane View > Zoom acts on.
//

import SwiftUI
import XCTest
@testable import ShellControls

nonisolated final class ZoomPanKeyboardTests: XCTestCase {
    private let box = CGSize(width: 400, height: 300)

    /// Red before: the model had no pan, so the keyboard could zoom a picture but never move it.
    @MainActor func testThePanCommandsMoveAZoomedPictureAFifthOfThePaneAndStopAtItsEdge() {
        let model = PaneZoomModel()
        model.box = box
        model.zoomIn()                                                  // 2×: the overhang is 200 by 150 points a side
        XCTAssertTrue(model.canPan)

        model.pan(.left)
        XCTAssertEqual(model.state.offset, CGSize(width: 80, height: 0), "the view moves left, so the picture moves right")
        model.pan(.up)
        XCTAssertEqual(model.state.offset, CGSize(width: 80, height: 60))
        model.pan(.right); model.pan(.down)
        XCTAssertEqual(model.state.offset, .zero, "each step undoes its opposite")

        for _ in 0..<10 { model.pan(.right); model.pan(.down) }
        XCTAssertEqual(model.state.offset, CGSize(width: -200, height: -150), "never past the picture's edge")
    }

    @MainActor func testAtTheFitThereIsNothingToPanAndTheItemsAreOff() {
        let model = PaneZoomModel()
        model.box = box
        XCTAssertFalse(model.canPan)
        model.pan(.left)
        XCTAssertEqual(model.state, ZoomPan(), "a pan at the fit changes nothing")

        model.zoomIn(); model.pan(.left)
        model.fit()
        XCTAssertFalse(model.canPan, "back at the fit, the items turn off again")
    }

    /// The menu's four items: their order, their titles, and ⌃⌘ and an arrow, which neither app's panes nor a text field take.
    func testTheMenuItemsAreTheFourArrowsWithControlCommand() {
        XCTAssertEqual(PanCommand.allCases.map(\.title), ["Pan Left", "Pan Right", "Pan Up", "Pan Down"])
        XCTAssertEqual(PanCommand.allCases.map(\.key), [.leftArrow, .rightArrow, .upArrow, .downArrow])
        XCTAssertEqual(PanCommand.allCases.map(\.direction), [.left, .right, .up, .down])
        XCTAssertEqual(PanCommand.modifiers, [.control, .command])
    }
}
