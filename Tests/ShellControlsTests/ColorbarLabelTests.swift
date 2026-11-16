import ShellMetal
import SwiftUI
import XCTest
@testable import ShellControls

/// MacEMUI#160: a wide range (a strain map's -1.23e-05 … 0 … 1.23e-05) wrapped its numbers onto two lines under the
/// fixed-width strip. The numbers stay on one line and the plate grows wider instead.
nonisolated final class ColorbarLabelTests: XCTestCase {
    @MainActor private func size(_ view: some View) throws -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "the colour bar renders")
        return CGSize(width: image.width, height: image.height)
    }

    @MainActor func testWideNumbersStayOnOneLineAndWidenThePlate() throws {
        let narrow = try size(Colorbar(colormap: .viridis, low: 0, high: 1, unitLabel: "strain"))
        let wide = try size(Colorbar(colormap: .viridis, low: -1.23456e-5, high: 1.23456e-5,
                                     unitLabel: "strain", marksZero: true))
        XCTAssertEqual(wide.height, narrow.height, "a wrapped number makes the plate taller")
        XCTAssertGreaterThan(wide.width, narrow.width, "the plate grows to hold the numbers on one line")
    }

    @MainActor func testALongUnitStaysOnOneLine() throws {
        let short = try size(Colorbar(colormap: .viridis, low: 0, high: 1, unitLabel: "nm"))
        let long = try size(Colorbar(colormap: .viridis, low: 0, high: 1,
                                     unitLabel: "rotation about the beam axis, degrees"))
        XCTAssertEqual(long.height, short.height, "a wrapped unit makes the plate taller")
    }
}
