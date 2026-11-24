//
//  SecondSignalTests.swift
//  EMSuiteUI Q8: every state the shared EDS views tell by colour carries a second signal (a shape, a dash or a word), and the
//  styles follow Increase Contrast.
//

import XCTest
@testable import ShellSpectroscopy

nonisolated final class SecondSignalTests: XCTestCase {

    // MARK: The periodic table

    /// Proposed and fit only were both plain outlines that differed in colour alone. Red before: there was no dash.
    func testProposedAndFitOnlyDifferByTheirOutlineNotOnlyItsColour() {
        XCTAssertFalse(PeriodicTable.dash(.suggested("quantify")).isEmpty, "proposed is dashed")
        XCTAssertTrue(PeriodicTable.dash(.fitOnly).isEmpty, "fit only is solid")
        XCTAssertNotEqual(PeriodicTable.dash(.suggested("fit only")), PeriodicTable.dash(.fitOnly))
    }

    func testIncreaseContrastThickensTheOutlinesAndLiftsTheDimAndTheWell() {
        XCTAssertGreaterThan(PeriodicTable.borderWidth(increasedContrast: true), PeriodicTable.borderWidth(increasedContrast: false))
        XCTAssertGreaterThan(PeriodicTable.unavailableInkOpacity(increasedContrast: true), PeriodicTable.unavailableInkOpacity(increasedContrast: false))
        XCTAssertGreaterThan(PeriodicTable.offWellOpacity(increasedContrast: true), PeriodicTable.offWellOpacity(increasedContrast: false))
        XCTAssertGreaterThanOrEqual(PeriodicTable.unavailableInkOpacity(increasedContrast: false), 0.35, "a dim symbol stays readable")
    }

    // MARK: The spectrum

    /// The spectrum, the continuum and the fit were three solid lines told apart by colour. Each now differs from every other by
    /// its dash or its fill, and the legend names them.
    func testEachCurveDiffersFromEveryOtherByItsShape() {
        let all = EDXSpectrumSeries.allCases
        XCTAssertEqual(all.map(\.title), ["spectrum", "continuum", "fit"])
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] {
                XCTAssertTrue(a.dash != b.dash || a.isFilled != b.isFilled, "\(a.title) and \(b.title) differ by colour alone")
            }
        }
        XCTAssertGreaterThan(EDXSpectrumSeries.lineWidth(increasedContrast: true), EDXSpectrumSeries.lineWidth(increasedContrast: false))
    }

    // MARK: The maps

    /// A computing map was told by its fading alone; the badge says it.
    func testABusyTileSaysSo() {
        XCTAssertEqual(EDXMapTileBusyBadge.text, "Updating…")
    }
}
