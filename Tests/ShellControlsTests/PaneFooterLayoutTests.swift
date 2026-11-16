//
//  PaneFooterLayoutTests.swift
//  The pane footer's one layout (MacEMUI#158): the scale bar and the legend side by side while both fit, else the legend stacked above
//  the bar. One layout over the same two views keeps the legend chip's popover open when a zoom flips the arrangement; these pin where
//  each view goes, as the `ViewThatFits` of a row and a column placed them.
//

import XCTest
@testable import ShellControls

nonisolated final class PaneFooterLayoutTests: XCTestCase {
    private let bar = CGSize(width: 90, height: 20)
    private let legend = CGSize(width: 146, height: 34)

    /// Wide: bottoms aligned, the bar at the left, the legend at the right edge.
    @MainActor func testSideBySideWhileBothFit() {
        let p = PaneFooterLayout.placement(width: 400, leading: bar, trailing: legend)
        XCTAssertFalse(p.stacked)
        XCTAssertEqual(p.size, CGSize(width: 400, height: 34))
        XCTAssertEqual(p.leading, CGPoint(x: 0, y: 14))
        XCTAssertEqual(p.trailing, CGPoint(x: 254, y: 0))
    }

    /// Exactly the two ideal widths and the 8 pt gap still fit side by side; one point less stacks.
    @MainActor func testTheThresholdIsBothIdealWidthsAndTheGap() {
        XCTAssertFalse(PaneFooterLayout.placement(width: 244, leading: bar, trailing: legend).stacked)
        XCTAssertTrue(PaneFooterLayout.placement(width: 243, leading: bar, trailing: legend).stacked)
    }

    /// Narrow: the legend above at the right, 6 pt over the bar at the bottom left.
    @MainActor func testStackedWhenNarrow() {
        let p = PaneFooterLayout.placement(width: 200, leading: bar, trailing: legend)
        XCTAssertTrue(p.stacked)
        XCTAssertEqual(p.size, CGSize(width: 200, height: 60))
        XCTAssertEqual(p.trailing, CGPoint(x: 54, y: 0))
        XCTAssertEqual(p.leading, CGPoint(x: 0, y: 40))
    }

    /// No width offered: the views' own row.
    @MainActor func testUnspecifiedWidthIsTheIdealRow() {
        let p = PaneFooterLayout.placement(width: nil, leading: bar, trailing: legend)
        XCTAssertFalse(p.stacked)
        XCTAssertEqual(p.size.width, 244)
    }
}
