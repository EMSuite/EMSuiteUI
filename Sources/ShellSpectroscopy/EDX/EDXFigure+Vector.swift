//
//  EDXFigure+Vector.swift
//  Role: the EDS and EELS rooms' figures as vectors (Electron-Microscopy-Studio#902, plan row X10): the maps figure as ShellExport
//        panels (each map at its own pixels as the room draws it, the regions as lines over it, a vector scale bar, the colour bar as a
//        ramp, the footer as text) and the shown spectrum as one path with its lines marked (`FigurePlot.spectrum`), written as PDF or
//        SVG by `FigureRenderer`. The PNG stays `EDXMapsFigure`.
//

import Foundation
import ShellEDXModel
import ShellExport
import SpectroCore

/// The vector formats a room's figure is written in.
public nonisolated enum EDXFigureFormat: String, Sendable, CaseIterable {
    case pdf, svg

    public var title: String { rawValue.uppercased() }

    /// The figure's bytes, off the main actor: `FigureRenderer`'s PDF or SVG with `metadata` (title, software, methods record).
    @concurrent public static func data(_ scene: FigureScene, format: EDXFigureFormat, metadata: FigureMetadata) async throws -> Data {
        switch format {
        case .pdf: try FigureRenderer.pdf(scene, metadata: metadata)
        case .svg: Data(FigureRenderer.svg(scene, metadata: metadata).utf8)
        }
    }
}

extension EDXFigureContent {
    /// The figure as panels `style.width` wide (else 90 mm for one map, 190 mm for several), in the PNG's order (the colour mix, the
    /// room's maps, the cells another room made); nil when it holds no map.
    public func vectorScene(style: FigureStyle? = nil) -> FigureScene? {
        var panels: [FigurePlot.Panel] = []
        if let first = mix.first {
            let rgba = rasters[Self.mixKey] ?? MapRaster.mix(
                mix.map { MapRaster.MixLayer(values: $0.values, color: EDXRegionBridge.defaultColoring($0.symbol).endColor) }, count: first.values.count)
            if let panel = panel("Colour mix", mix.map(\.symbol).joined(separator: " + "), rgba: rgba, width: first.width, height: first.height,
                                 isMix: true) {
                panels.append(panel)
            }
        }
        for tile in tiles {
            let rgba = rasters[tile.symbol] ?? EDXMapRaster.rgba(values: tile.values, hue: EDXRoomFormat.hue(symbol: tile.symbol), width: tile.width)
            if let panel = panel(tile.symbol, tile.line, rgba: rgba, width: tile.width, height: tile.height, footer: tile.footer) {
                panels.append(panel)
            }
        }
        for cell in cells {
            if let panel = panel(cell.title, cell.detail, rgba: cell.rgba, width: cell.width, height: cell.height,
                                 ramp: cell.colourBar.map(Self.ramp), footer: cell.footer) {
                panels.append(panel)
            }
        }
        guard !panels.isEmpty else { return nil }
        // One map is a single column's figure; several sit side by side across the page.
        let style = style ?? FigureStyle(width: panels.count == 1 ? .mm90 : .mm190)
        return FigurePlot.panels(panels, title: title, subtitle: subtitle, style: style)
    }

    /// One map's panel: its RGB pixels (the room's are opaque), the regions when it draws them, the scale bar when shown.
    func panel(_ title: String, _ detail: String, rgba: [UInt8], width: Int, height: Int, isMix: Bool = false, ramp: FigurePlot.Ramp? = nil,
               footer: String? = nil) -> FigurePlot.Panel? {
        guard width >= 1, height >= 1, rgba.count == width * height * 4 else { return nil }
        var rgb = [UInt8]()
        rgb.reserveCapacity(width * height * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) { rgb += rgba[i..<i + 3] }
        let picture = FigureRaster(width: width, height: height, format: .rgb8, pixels: rgb)
        let k = Double(width) / Double(max(nx, 1))
        let overlay = drawsRegions(onMix: isMix) ? regionPaths(pixelsPerScanPixel: k) : []
        let scaleBar = showsScaleBar ? bar.map { FigurePlot.ScaleBar(lengthFraction: $0.fraction, label: $0.label) } : nil
        return FigurePlot.Panel(title: title, detail: detail, picture: picture, overlay: overlay, scaleBar: scaleBar, ramp: ramp, footer: footer)
    }

    /// The regions as the room's overlay draws them: each visible one in its colour over a darker line, the selected one heavier; with
    /// no set, the selected region in white.
    func regionPaths(pixelsPerScanPixel k: Double) -> [FigurePath] {
        let shapes: [(geometry: RegionGeometry, color: FigureColor, heavy: Bool)]
        if let regions {
            shapes = regions.regions.filter(\.isVisible).map { region in
                (region.geometry, FigureColor(red: region.color.red, green: region.color.green, blue: region.color.blue), region.id == regions.selectedID)
            }
        } else if let geometry = EDXRegionBridge.geometry(region) {
            shapes = [(geometry, .white, false)]
        } else {
            shapes = []
        }
        return shapes.flatMap { shape -> [FigurePath] in
            let (points, closed) = Self.outline(shape.geometry, scale: k)
            let width = shape.heavy ? 1.2 : 0.75
            return [FigurePath(points: points, closed: closed, stroke: FigureColor(gray: 0, alpha: 0.55), lineWidth: width + 0.75),
                    FigurePath(points: points, closed: closed, stroke: shape.color, lineWidth: width)]
        }
    }

    /// A region's outline in picture pixels: a rectangle's corners, an ellipse as 64 points, a polygon's vertices, a line's ends.
    static func outline(_ geometry: RegionGeometry, scale k: Double) -> (points: [FigurePoint], closed: Bool) {
        func point(_ x: Double, _ y: Double) -> FigurePoint { FigurePoint(x: x * k, y: y * k) }
        switch geometry {
        case .rectangle(let x0, let y0, let x1, let y1):
            return ([point(x0, y0), point(x1, y0), point(x1, y1), point(x0, y1)], true)
        case .ellipse(let x0, let y0, let x1, let y1):
            let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, rx = abs(x1 - x0) / 2, ry = abs(y1 - y0) / 2
            return ((0..<64).map { i in
                let a = Double(i) / 64 * 2 * .pi
                return point(cx + rx * cos(a), cy + ry * sin(a))
            }, true)
        case .polygon(let vertices):
            return (vertices.map { point($0.x, $0.y) }, true)
        case .line(let a, let b):
            return ([point(a.x, a.y), point(b.x, b.y)], false)
        }
    }

    /// A cell's colour bar as a ramp of sixteen of its colours.
    static func ramp(_ bar: EDXFigureColourBar) -> FigurePlot.Ramp {
        let steps = min(16, max(bar.width, 1))
        let colors = (0..<steps).compactMap { step -> FigureColor? in
            let x = steps == 1 ? 0 : step * (bar.width - 1) / (steps - 1), i = 4 * x
            guard i + 2 < bar.rgba.count else { return nil }
            return FigureColor(red: Double(bar.rgba[i]) / 255, green: Double(bar.rgba[i + 1]) / 255, blue: Double(bar.rgba[i + 2]) / 255)
        }
        return FigurePlot.Ramp(colors: colors, low: bar.low, high: bar.high)
    }
}

extension EDXSession {
    /// The spectrum as the room shows it, as a plot: the channels inside `window` (the room's, else its automatic one, as the spectrum
    /// view clamps it), counts against energy in keV, each element line in the window marked. The detector's strobe peak below
    /// `EDXSpectrumWindow.strobeCeilingKeV` is electronics and often the tallest thing in the file; the view keeps it out of the count
    /// scale, and the figure leaves its channels out, so the real lines keep their height. Nil with no channel to draw.
    public func spectrumFigure(window: ClosedRange<Double>?) -> FigurePlot.Spectrum? {
        Self.spectrumFigure(plot: plot, markers: markers, window: window)
    }

    static func spectrumFigure(plot: EDXPlot, markers: [EDXMarker], window: ClosedRange<Double>?) -> FigurePlot.Spectrum? {
        guard !plot.data.isEmpty, plot.energyStep > 0 else { return nil }
        let end = plot.energyStart + plot.energyStep * Double(plot.data.count)
        let domain = plot.energyStart...max(end, plot.energyStart + plot.energyStep)
        let shown = EDXSpectrumWindow.clamp(window ?? EDXRoomFormat.autoWindow(plot: plot, markers: markers), domain: domain,
                                            minimumSpan: 2 * plot.energyStep)
        let low = max(shown.lowerBound, EDXSpectrumWindow.strobeCeilingKeV)
        var x: [Double] = [], y: [Double] = []
        for (i, counts) in plot.data.enumerated() {
            let energy = plot.energyStart + Double(i) * plot.energyStep
            guard energy >= low, energy <= shown.upperBound else { continue }
            x.append(energy)
            y.append(counts)
        }
        guard x.count >= 2 else { return nil }
        let marked = markers.filter { $0.energy >= low && $0.energy <= shown.upperBound }
        return FigurePlot.Spectrum(x: x, y: y, xTitle: "Energy (keV)", yTitle: "Counts",
                                   markers: marked.map { FigurePlot.Spectrum.Marker(x: $0.energy, label: $0.label) })
    }
}
