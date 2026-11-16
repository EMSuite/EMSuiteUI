//
//  ScrollWheelModeTests.swift
//  Settings > Scroll wheel: Zoom · Pan (control-placement §6): Zoom is the default, ⌥ gives the other action in either mode, and the
//  choice is kept under one key both apps read. Red before: no setting; the wheel always zoomed and ⌥ always panned.
//

import XCTest
@testable import ShellControls

nonisolated final class ScrollWheelModeTests: XCTestCase {
    func testZoomIsTheDefaultAndOptionGivesTheOther() {
        XCTAssertEqual(ScrollWheelMode.default, .zoom, "the field's convention (Velox, GMS, ImageJ)")
        XCTAssertEqual(ScrollWheelMode.zoom.action(optionHeld: false), .zoom)
        XCTAssertEqual(ScrollWheelMode.zoom.action(optionHeld: true), .pan, "⌥-scroll pans, as before")
        XCTAssertEqual(ScrollWheelMode.pan.action(optionHeld: false), .pan, "the Mac's convention")
        XCTAssertEqual(ScrollWheelMode.pan.action(optionHeld: true), .zoom)
    }

    /// One key and two stored words for both apps: a choice made in one is the other's.
    func testTheChoiceIsKeptUnderOneKey() {
        XCTAssertEqual(ScrollWheelMode.key, "view.scrollWheel")
        XCTAssertEqual(ScrollWheelMode.allCases.map(\.rawValue), ["zoom", "pan"])
        XCTAssertEqual(ScrollWheelMode.allCases.map(\.title), ["Zoom", "Pan"])
    }
}
