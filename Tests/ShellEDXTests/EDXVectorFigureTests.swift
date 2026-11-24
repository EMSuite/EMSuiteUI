//
//  EDXVectorFigureTests.swift
//  The EDS and EELS rooms' figures as vectors (Electron-Microscopy-Studio#902, plan row X10): the maps are panels, each map at its own
//  pixels with the regions as lines and the colour bar as a ramp; the spectrum is one path with its lines marked. Red before: the room
//  wrote its maps only as a PNG of its view, and its spectrum as numbers.
//

import XCTest
@testable import ShellEDXModel
@testable import ShellExport
@testable import ShellSpectroscopy
import UniformTypeIdentifiers

nonisolated final class EDXVectorFigureTests: XCTestCase {
    private static let shown = SpectralRegion(name: "A", color: RegionColor(red: 1, green: 0, blue: 0),
                                              geometry: .rectangle(x0: 0, y0: 0, x1: 1, y1: 1))
    private static let hidden = SpectralRegion(name: "B", color: RegionColor(red: 0, green: 0, blue: 1), isVisible: false,
                                               geometry: .polygon([RegionPoint(x: 0, y: 0), RegionPoint(x: 2, y: 0), RegionPoint(x: 1, y: 1)]))

    @MainActor private func content() -> EDXFigureContent {
        let tiles = ["O", "Ni"].map { EDXMapTile(symbol: $0, width: 2, height: 1, values: [1, 2], version: 1, line: "\($0) Kα", note: nil) }
        let ramp = (0..<256).flatMap { [UInt8(0), UInt8($0), UInt8(0), UInt8(255)] }
        let cell = EDXFigureCell(id: "t", title: "t/λ", detail: "", rgba: [UInt8](repeating: 128, count: 2 * 1 * 4), width: 2, height: 1,
                                 footer: "log-ratio, no plural scattering correction",
                                 colourBar: EDXFigureColourBar(rgba: ramp, width: 256, low: "0.21", high: "0.85 t/λ"))
        return EDXFigureContent(title: "planted.dm4", subtitle: "Whole map · net counts", tiles: tiles, region: .wholeMap, nx: 2, ny: 1,
                                bar: (fraction: 0.5, label: "1 nm"), cells: [cell],
                                regions: SpectralRegionSet(regions: [Self.shown, Self.hidden], selectedID: Self.shown.id))
    }

    /// Every map is a picture at its own pixels; the visible region is drawn on each (no mix), heavier as the selected one, over a
    /// darker line; the hidden one is not; the cell's colour bar is a ramp of boxes between its two values; the bar is vector.
    @MainActor func testTheMapsArePanelsWithTheirRegionsAndBars() throws {
        let scene = try XCTUnwrap(content().vectorScene())
        XCTAssertEqual(scene.widthMM, 190, "three maps across the page")
        let one = EDXFigureContent(title: "planted.dm4", subtitle: "", tiles: [EDXMapTile(symbol: "O", width: 2, height: 1, values: [1, 2], version: 1,
                                                                                    line: "O Kα", note: nil)],
                                   region: .wholeMap, nx: 2, ny: 1, bar: nil)
        XCTAssertEqual(one.vectorScene()?.widthMM, 90, "one map is a single column's figure")
        let pictures = scene.layers.compactMap { if case .raster(let raster, _) = $0 { raster } else { nil } }
        XCTAssertEqual(pictures.count, 3)
        XCTAssertTrue(pictures.allSatisfy { $0.width == 2 && $0.height == 1 && $0.format == .rgb8 })
        let paths = scene.layers.compactMap { if case .path(let path) = $0 { path } else { nil } }
        let red = paths.filter { $0.stroke == FigureColor(red: 1, green: 0, blue: 0) }
        XCTAssertEqual(red.count, 3, "the visible region on each of the three maps")
        XCTAssertTrue(red.allSatisfy { $0.closed && $0.points.count == 4 && $0.lineWidth == 1.2 })
        XCTAssertFalse(paths.contains { $0.stroke == FigureColor(red: 0, green: 0, blue: 1) }, "a hidden region stays hidden")
        let texts = scene.layers.compactMap { if case .text(let text) = $0 { text.string } else { nil } }
        for label in ["planted.dm4", "O", "Kα", "O Kα", "t/λ", "0.21", "0.85 t/λ", "1 nm"] where label != "Kα" {
            XCTAssertTrue(texts.contains(label) || texts.contains { $0.hasPrefix(label) }, "\(label) in \(texts)")
        }
        XCTAssertEqual(texts.filter { $0 == "1 nm" }.count, 3, "a vector scale bar on each map")
        let greens = paths.filter { $0.fill.map { $0.red == 0 && $0.blue == 0 && $0.green > 0 } ?? false }
        XCTAssertEqual(greens.count, 15, "the colour bar as sixteen boxes, the first black")
    }

    /// A region's outline in picture pixels: a rectangle's four corners, an ellipse of 64 points, a line's two ends, open.
    @MainActor func testRegionOutlines() {
        let rect = EDXFigureContent.outline(.rectangle(x0: 1, y0: 2, x1: 3, y1: 4), scale: 2)
        XCTAssertEqual(rect.points.first, FigurePoint(x: 2, y: 4))
        XCTAssertEqual(rect.points.count, 4)
        XCTAssertEqual(EDXFigureContent.outline(.ellipse(x0: 0, y0: 0, x1: 2, y1: 2), scale: 1).points.count, 64)
        let line = EDXFigureContent.outline(.line(RegionPoint(x: 0, y: 0), RegionPoint(x: 1, y: 1)), scale: 1)
        XCTAssertFalse(line.closed)
    }

    /// The spectrum figure is the room's window, and the detector's strobe peak below 0.1 keV neither shows nor sets the count axis:
    /// a planted strobe of a million counts beside a 100-count line leaves the line the figure's top. Red under: every channel plotted
    /// (the line a few points high under the strobe), or the window ignored.
    @MainActor func testTheSpectrumFigureIsTheWindowWithoutTheStrobe() throws {
        var data = [Double](repeating: 5, count: 1_000)
        for i in 0..<5 { data[i] = 1_000_000 }   // 0 to 0.04 keV: the strobe
        data[150] = 100                          // 1.5 keV
        data[800] = 300                          // 8 keV, outside the window
        let plot = EDXPlot(energyStart: 0, energyStep: 0.01, data: data)
        let markers = [EDXMarker(symbol: "Al", label: "Al Kα", energy: 1.486, quantified: true),
                       EDXMarker(symbol: "Cu", label: "Cu Kα", energy: 8.04, quantified: true)]
        let figure = try XCTUnwrap(EDXSession.spectrumFigure(plot: plot, markers: markers, window: 0...4))
        XCTAssertGreaterThanOrEqual(figure.x.first ?? 0, EDXSpectrumWindow.strobeCeilingKeV)
        XCTAssertLessThanOrEqual(figure.x.last ?? 99, 4)
        XCTAssertEqual(figure.y.max(), 100, "the line sets the top, not the strobe")
        XCTAssertEqual(figure.markers.map(\.label), ["Al Kα"], "only the lines in the window")
        XCTAssertNil(EDXSession.spectrumFigure(plot: EDXPlot(energyStart: 0, energyStep: 0.01, data: []), markers: [], window: nil))
    }

    /// The four figure kinds write PDF or SVG under the spectrum's and the maps' names; the others are no figure.
    @MainActor func testTheFigureKinds() async throws {
        XCTAssertEqual(EDXExportKind.mapsPDF.contentType, .pdf)
        XCTAssertEqual(EDXExportKind.spectrumSVG.contentType, .svg)
        XCTAssertEqual(EDXExportKind.spectrumPDF.suffix, " spectrum")
        XCTAssertEqual(EDXExportKind.mapsSVG.suffix, " maps")
        XCTAssertEqual(EDXExportKind.allCases.compactMap(\.figureFormat), [.pdf, .svg, .pdf, .svg])
        let scene = try XCTUnwrap(content().vectorScene())
        let svg = try await EDXFigureFormat.data(scene, format: .svg, metadata: FigureMetadata(title: "planted.dm4", creator: "test"))
        let text = try XCTUnwrap(String(data: svg, encoding: .utf8))
        XCTAssertTrue(text.contains("<text"), "the labels are live text")
        let pdf = try await EDXFigureFormat.data(scene, format: .pdf, metadata: FigureMetadata(title: "planted.dm4", creator: "test"))
        XCTAssertEqual(Array(pdf.prefix(4)), Array("%PDF".utf8))
        XCTAssertEqual(EDXRoomState.creator(info: ["CFBundleName": "Electron Microscopy Studio", "CFBundleShortVersionString": "2.5.0"]),
                       "Electron Microscopy Studio 2.5.0")
    }
}
