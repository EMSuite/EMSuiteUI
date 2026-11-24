@testable import ShellExport
import XCTest

/// Maps side by side (Electron-Microscopy-Studio#902, plan row X10): each panel its title, its picture across its column at its own
/// pixels, the overlay scaled with it, a vector bar, a ramp and a wrapped footer; two a row at 90 mm, three at 190. Red before: no
/// panel layout existed, and the EDS and EELS maps figures were pictures of the room's view.
final class FigurePanelsTests: XCTestCase {
    private func panel(_ title: String, footer: String? = nil) -> FigurePlot.Panel {
        FigurePlot.Panel(title: title, detail: "Kα", picture: FigureRaster(width: 4, height: 2, format: .gray8, pixels: [UInt8](repeating: 9, count: 8)),
                         overlay: [FigurePath(points: [FigurePoint(x: 0, y: 0), FigurePoint(x: 4, y: 2)], stroke: .white, lineWidth: 1)],
                         scaleBar: FigurePlot.ScaleBar(lengthFraction: 0.25, label: "1 µm"),
                         ramp: FigurePlot.Ramp(colors: [.black, .white], low: "0", high: "12 counts"), footer: footer)
    }

    func testPanelsFillTheirColumnsInRows() {
        let three = (1...3).map { panel("P\($0)") }
        let narrow = FigurePlot.panels(three, title: "scan.dm4", style: FigureStyle(width: .mm90))
        let frames = narrow.layers.compactMap { if case .raster(_, let frame) = $0 { frame } else { nil } }
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].y, frames[1].y, "two a row at 90 mm")
        XCTAssertGreaterThan(frames[2].y, frames[0].y + frames[0].height, "the third on the next row")
        XCTAssertEqual(frames[0].width, (narrow.widthPoints - FigurePlot.panelGap) / 2, accuracy: 1e-9)
        XCTAssertEqual(frames[0].height, frames[0].width / 2, accuracy: 1e-9, "the picture keeps its aspect")
        let wide = FigurePlot.panels(three, title: "scan.dm4", style: FigureStyle(width: .mm190))
        let wideFrames = wide.layers.compactMap { if case .raster(_, let frame) = $0 { frame } else { nil } }
        XCTAssertEqual(Set(wideFrames.map(\.y)).count, 1, "three a row at 190 mm")
        // The overlay is scaled from picture pixels to the panel: its far end at the picture's bottom-right corner.
        let overlay = wide.layers.compactMap { if case .path(let path) = $0, path.stroke == .white, path.lineWidth == 1 { path } else { nil } }
        XCTAssertEqual(overlay.first?.points.last?.x ?? 0, wideFrames[0].x + wideFrames[0].width, accuracy: 1e-9)
        XCTAssertEqual(overlay.first?.points.last?.y ?? 0, wideFrames[0].y + wideFrames[0].height, accuracy: 1e-9)
    }

    /// Every text on the page, the footer wrapped to its column.
    func testEveryTextLiesOnThePage() {
        let long = "k-factors from the Cliff-Lorimer table of the vendor, no absorption correction, 3 pixels failed to fit and are left out"
        let scene = FigurePlot.panels([panel("O", footer: long), panel("Ni")], title: "scan.dm4", subtitle: "Whole map · net counts",
                                      style: FigureStyle(width: .mm90))
        var footerLines = 0
        for case .text(let text) in scene.layers {
            let size = text.size ?? scene.style.typeSize, w = FigurePlot.textWidth(text.string, size: size)
            let start = switch text.anchor {
            case .start: text.origin.x
            case .middle: text.origin.x - w / 2
            case .end: text.origin.x - w
            }
            XCTAssertGreaterThanOrEqual(start, -1e-9, text.string)
            XCTAssertLessThanOrEqual(start + w, scene.widthPoints + 1e-9, text.string)
            XCTAssertLessThanOrEqual(text.origin.y, scene.heightPoints + 1e-9, text.string)
            if long.contains(text.string), text.string.count > 3 { footerLines += 1 }
        }
        XCTAssertGreaterThan(footerLines, 1, "the footer wraps")
        XCTAssertEqual(FigurePlot.wrapped("a b", width: 1000, size: 7), ["a b"])
    }
}
