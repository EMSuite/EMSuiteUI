@testable import ShellExport
import XCTest

/// The spectrum and map layouts (Electron-Microscopy-Studio#902, plan row X10): a spectrum is one path with its frame, ticks and
/// titles as text, never a picture; a map is its picture at its own pixels with a vector scale bar and a key. Red before: the layouts
/// did not exist, and the rooms' figures were pictures of their panes.
final class FigurePlotTests: XCTestCase {
    private func texts(_ scene: FigureScene) -> [String] {
        scene.layers.compactMap { if case .text(let text) = $0 { text.string } else { nil } }
    }

    private func paths(_ scene: FigureScene) -> [FigurePath] {
        scene.layers.compactMap { if case .path(let path) = $0 { path } else { nil } }
    }

    func testTicksAreRoundAndCoverTheRange() {
        XCTAssertEqual(FigurePlot.ticks(low: 0, high: 10), [0, 2, 4, 6, 8, 10])
        let unit = FigurePlot.ticks(low: 0.13, high: 0.97)
        XCTAssertEqual(unit.first ?? -1, 0, accuracy: 1e-12)
        XCTAssertEqual(unit.last ?? -1, 1, accuracy: 1e-12)
        let ticks = FigurePlot.ticks(low: 283, high: 2_048)
        XCTAssertEqual(ticks.first, 0)
        XCTAssertGreaterThanOrEqual(ticks.last ?? 0, 2_048)
        XCTAssertTrue((4...10).contains(ticks.count), "\(ticks)")
        XCTAssertEqual(FigurePlot.ticks(low: 1, high: 1), [])
    }

    func testTickNumbersCarryTheirStepsDecimals() {
        XCTAssertEqual(FigurePlot.number(0.4, step: 0.2), "0.4")
        XCTAssertEqual(FigurePlot.number(1_000, step: 500), "1000")
        XCTAssertEqual(FigurePlot.number(-0.0001, step: 0.5), "0.0")
        XCTAssertEqual(FigurePlot.number(100.2, step: 100.2 - 100.1), "100.2", "a step a hair under 0.1 keeps one decimal")
    }

    /// Every number, title and label of a spectrum lies on the page, by the layout's own width estimate: the last x number may sit
    /// on the frame's right edge, a long y number on its left, a marker by the right edge puts its label to the line's left.
    /// Red before: "10000" at the right edge was centred on a one-type-size margin and lost 3 pt to the page edge.
    func testEveryTextLiesOnThePage() {
        let cases: [(ClosedRange<Double>, Double)] = [(0...10_000, 1_000), (283...2_048, 5_000), (0...2_500, 1_234_567), (0.13...0.17, 3)]
        for (span, peak) in cases {
            let x = (0...400).map { span.lowerBound + Double($0) / 400 * (span.upperBound - span.lowerBound) }
            let y = x.indices.map { $0 == 200 ? peak : 1 }
            let markers = [FigurePlot.Spectrum.Marker(x: span.upperBound, label: "Cu Kβ"), .init(x: span.upperBound, label: "Zn Kα"),
                           .init(x: span.lowerBound, label: "O Kα")]
            let scene = FigurePlot.spectrum(.init(x: x, y: y, xTitle: "Energy (eV)", yTitle: "Counts", markers: markers))
            for case .text(let text) in scene.layers {
                let size = text.size ?? scene.style.typeSize, w = FigurePlot.textWidth(text.string, size: size)
                let start = switch text.anchor {
                case .start: text.origin.x
                case .middle: text.origin.x - w / 2
                case .end: text.origin.x - w
                }
                XCTAssertGreaterThanOrEqual(start, 0, "\(text.string) in \(span)")
                XCTAssertLessThanOrEqual(start + w, scene.widthPoints, "\(text.string) in \(span)")
                XCTAssertGreaterThanOrEqual(text.origin.y - size, 0, "\(text.string) in \(span)")
                XCTAssertLessThanOrEqual(text.origin.y, scene.heightPoints, "\(text.string) in \(span)")
            }
        }
    }

    /// The x axis spans the data, not round ticks beyond it: a 283 to 2048 eV spectrum starts at the frame's left edge.
    func testTheXAxisSpansTheData() {
        let x = (283...2_048).map(Double.init)
        let scene = FigurePlot.spectrum(.init(x: x, y: x.map { _ in 1 }, xTitle: "Energy (eV)", yTitle: "Counts"))
        let frame = paths(scene).first?.points.map(\.x) ?? []
        let curve = paths(scene).last?.points.map(\.x) ?? []
        XCTAssertEqual(curve.first ?? -1, frame.min() ?? 0, accuracy: 1e-9)
        XCTAssertEqual(curve.last ?? -1, frame.max() ?? 0, accuracy: 1e-9)
        XCTAssertFalse(texts(scene).contains("0"), "no tick below the data")
        XCTAssertTrue(texts(scene).contains("2000"))
    }

    /// A spectrum stored high to low is thinned too, in its own order.
    func testADescendingSpectrumIsDecimated() {
        let points = (0..<100_000).map { (Double(100_000 - $0), Double($0 % 7)) }
        let thinned = FigurePlot.decimated(points, columns: 100)
        XCTAssertLessThanOrEqual(thinned.count, 202, "two a column and the two ends")
        XCTAssertGreaterThan(thinned.first?.0 ?? 0, thinned.last?.0 ?? 0)
        XCTAssertEqual(thinned.first?.0, points.first?.0, "the first point stays")
        XCTAssertEqual(thinned.last?.0, points.last?.0, "the last point stays")
    }

    /// A spectrum is drawn as a path, not a picture: the curve is one path of its points, the frame and ticks are paths, the numbers
    /// and titles are text, and a marker is a line with its label.
    func testASpectrumIsAPath() {
        let x = (0..<100).map { Double($0) * 0.01 }, y = x.map { 1_000 * exp(-pow(($0 - 0.5) / 0.1, 2)) }
        let scene = FigurePlot.spectrum(.init(x: x, y: y, xTitle: "Energy (keV)", yTitle: "Counts",
                                              markers: [.init(x: 0.525, label: "O Kα")]))
        XCTAssertFalse(scene.layers.contains { if case .raster = $0 { true } else { false } }, "no picture")
        let curve = paths(scene).last
        XCTAssertEqual(curve?.points.count, 100, "the curve keeps every point it can show")
        XCTAssertEqual(curve?.closed, false)
        XCTAssertTrue(texts(scene).contains("Energy (keV)"))
        XCTAssertTrue(texts(scene).contains("Counts"))
        XCTAssertTrue(texts(scene).contains("O Kα"))
        XCTAssertTrue(texts(scene).contains("1000"), "the y axis reaches the peak")
        XCTAssertEqual(scene.widthMM, 90)
        XCTAssertEqual(scene.heightMM, 90 * FigurePlot.spectrumAspect, accuracy: 1e-9)
        let points = curve?.points ?? []
        XCTAssertTrue(points.allSatisfy { $0.x >= 0 && $0.x <= scene.widthPoints && $0.y >= 0 && $0.y <= scene.heightPoints })
    }

    /// A million channels become at most two points a column, the peak among them.
    func testALongSpectrumIsDecimatedAndKeepsItsPeak() {
        let n = 1_000_000
        var y = [Double](repeating: 1, count: n)
        y[777_777] = 50
        let scene = FigurePlot.spectrum(.init(x: (0..<n).map(Double.init), y: y, xTitle: "Channel", yTitle: "Counts"))
        let curve = paths(scene).last?.points ?? []
        XCTAssertLessThanOrEqual(curve.count, 2 * Int(scene.widthPoints.rounded(.up)) * 2)
        let top = curve.min { $0.y < $1.y }   // y grows downward: the peak is the smallest y
        XCTAssertNotNil(top)
        XCTAssertTrue(curve.filter { $0.y == top?.y }.count == 1, "one peak, kept")
    }

    /// A map is its picture across the width, a vector bar on a plate over its bottom left, and its key below.
    func testAMapIsAPictureWithAVectorBarAndAKey() throws {
        let raster = FigureRaster(width: 4, height: 2, format: .rgb8, pixels: [UInt8](repeating: 128, count: 24))
        let red = FigureColor(red: 1, green: 0, blue: 0), blue = FigureColor(red: 0, green: 0, blue: 1)
        let entries = [FigureLegend.Entry("Al", swatch: .box(red)), FigureLegend.Entry("Mg₂Si", swatch: .box(blue))]
        let scene = FigurePlot.map(raster, scaleBar: .init(lengthFraction: 0.25, label: "500 nm"), key: .entries(entries))
        guard case .raster(let picture, let frame) = try XCTUnwrap(scene.layers.first) else { return XCTFail("the picture first") }
        XCTAssertEqual(picture, raster)
        XCTAssertEqual(frame.width, scene.widthPoints)
        XCTAssertEqual(frame.height, scene.widthPoints / 2, accuracy: 1e-9)
        let bar = try XCTUnwrap(paths(scene).first { $0.fill == .white })
        XCTAssertEqual(bar.points[1].x - bar.points[0].x, scene.widthPoints / 4, accuracy: 1e-9)
        XCTAssertTrue(texts(scene).contains("500 nm"))
        XCTAssertTrue(scene.layers.contains { if case .legend(let legend) = $0 { legend.entries == entries } else { false } })
        XCTAssertGreaterThan(scene.heightPoints, frame.height, "the key sits below the picture")
    }

    /// A ramp key: its boxes span half the width in order, with its two ends and its title as text.
    func testAMapRampKey() {
        let raster = FigureRaster(width: 2, height: 2, format: .gray8, pixels: [0, 85, 170, 255])
        let colors = (0..<8).map { FigureColor(gray: Double($0) / 7) }
        let scene = FigurePlot.map(raster, key: .ramp(colors: colors, low: "0", high: "1.2", title: "t/λ"))
        let boxes = paths(scene).filter { $0.fill != nil && $0.stroke == nil }
        XCTAssertEqual(boxes.map(\.fill), colors.map { Optional($0) })
        XCTAssertEqual(Set(texts(scene)), ["0", "1.2", "t/λ"])
    }
}
