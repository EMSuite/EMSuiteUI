import ShellMetal
import SwiftUI
import XCTest
@testable import ShellControls

/// MacEMUI#160: the AA6060 strain map's range -0,005681 … 0 … 0,005681 broke its last digit onto a second line on a Mac
/// (mac4DSTEM 5.4.0 walk, picture 09): the number row was fixed at the strip's 132 pt. Whether a given range overflows
/// 132 pt depends on the machine's font metrics (on the CI runner this one fits), so the tests check the invariant
/// rather than a width: every number and the unit stay on one line, so the plate is never taller than one line each.
nonisolated final class ColorbarLabelTests: XCTestCase {
    @MainActor private func size(_ view: some View) throws -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "the colour bar renders")
        return CGSize(width: image.width, height: image.height)
    }

    @MainActor func testTheWalksStrainRangeStaysOnOneLine() throws {
        let narrow = try size(Colorbar(colormap: .viridis, low: 0, high: 1, unitLabel: "strain"))
        let strain = try size(Colorbar(colormap: .viridis, low: -0.005681, high: 0.005681,
                                       unitLabel: "strain", marksZero: true))
        XCTAssertEqual(strain.height, narrow.height, "a wrapped number makes the plate taller")
        XCTAssertGreaterThanOrEqual(strain.width, narrow.width, "the plate never narrows below the strip")
    }

    @MainActor func testWideNumbersStayOnOneLine() throws {
        let narrow = try size(Colorbar(colormap: .viridis, low: 0, high: 1, unitLabel: "strain"))
        let wide = try size(Colorbar(colormap: .viridis, low: -1.23456e-5, high: 1.23456e-5,
                                     unitLabel: "strain", marksZero: true))
        XCTAssertEqual(wide.height, narrow.height, "a wrapped number makes the plate taller")
    }

    @MainActor func testALongUnitStaysOnOneLine() throws {
        let short = try size(Colorbar(colormap: .viridis, low: 0, high: 1, unitLabel: "nm"))
        let long = try size(Colorbar(colormap: .viridis, low: 0, high: 1,
                                     unitLabel: "rotation about the beam axis, degrees"))
        XCTAssertEqual(long.height, short.height, "a wrapped unit makes the plate taller")
    }
}
