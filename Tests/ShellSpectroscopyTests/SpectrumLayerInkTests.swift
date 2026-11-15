import SwiftUI
import XCTest
@testable import ShellSpectroscopy

/// macEMSuite/MacEMUI#67: the hovered pixel's white spectrum vanished on a light window.
nonisolated final class SpectrumLayerInkTests: XCTestCase {
    private let white = RegionColor(red: 1, green: 1, blue: 1)

    /// The pixel's white turns near-black over a white halo in light mode, and stays white over a dark halo in dark mode.
    func testTheHoveredPixelReadsInBothAppearances() {
        let light = SpectrumLayerPlot.ink(of: white, in: .light)
        XCTAssertLessThan(light.line.red + light.line.green + light.line.blue, 0.5)
        XCTAssertEqual(light.halo, white)

        let dark = SpectrumLayerPlot.ink(of: white, in: .dark)
        XCTAssertEqual(dark.line, white)
        XCTAssertEqual(dark.halo, RegionColor(red: 0, green: 0, blue: 0))
    }

    /// A palette colour is the person's choice and keeps itself in either appearance, yellow included.
    func testPaletteColoursKeepThemselves() {
        for i in 0..<8 {
            let c = RegionPalette.color(at: i)
            XCTAssertEqual(SpectrumLayerPlot.ink(of: c, in: .light).line, c, "palette \(i)")
            XCTAssertEqual(SpectrumLayerPlot.ink(of: c, in: .dark).line, c, "palette \(i)")
        }
    }
}
