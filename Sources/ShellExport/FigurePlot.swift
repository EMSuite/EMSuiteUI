//
//  FigurePlot.swift
//  Role: the two figure layouts the spectroscopy and map rooms share (Electron-Microscopy-Studio#902, plan row X10), built as
//        `FigureScene`s so PDF and SVG keep every line and label as a vector and as text:
//
//        - a spectrum: the curve as one path (never a picture), a framed plot with ticks and their numbers, the axis titles, and
//          a labelled line per marker (an element's line, an edge onset);
//        - a map: the picture at its own pixels, a vector scale bar on a plate at its bottom left, and a key below it (one row per
//          colour, or a colour ramp with its two ends and its title).
//
//        Helvetica at the style's type size (7 pt), nothing smaller. Numbers are written in the POSIX locale.
//

import Foundation

public enum FigurePlot {
    // MARK: - A spectrum

    public struct Spectrum: Sendable, Equatable {
        /// A vertical line at `x` with its label at the top of the plot (an element's line, an edge's onset).
        public struct Marker: Sendable, Equatable {
            public var x: Double
            public var label: String
            public var color: FigureColor

            public init(x: Double, label: String, color: FigureColor = FigureColor(gray: 0.45)) {
                self.x = x
                self.label = label
                self.color = color
            }
        }

        public var x: [Double]
        public var y: [Double]
        public var xTitle: String
        public var yTitle: String
        public var color: FigureColor
        public var markers: [Marker]

        public init(x: [Double], y: [Double], xTitle: String, yTitle: String, color: FigureColor = .black, markers: [Marker] = []) {
            self.x = x
            self.y = y
            self.xTitle = xTitle
            self.yTitle = yTitle
            self.color = color
            self.markers = markers
        }
    }

    /// The plot's height over its width.
    public static let spectrumAspect = 0.62
    static let frameLineWidth = 0.5, curveLineWidth = 0.6, tickLength = 2.5

    /// The spectrum as a figure `style.width` wide: the frame, the ticks with their numbers, the titles, the markers and the curve.
    /// The x axis spans the data (the round ticks inside it), the y axis widens to round ticks and takes in zero, as a spectrum plot
    /// is read. The margins make room for the widest numbers, so no text leaves the page. Points whose x or y is not finite are left
    /// out; a spectrum with fewer than two points draws the frame alone.
    public static func spectrum(_ spectrum: Spectrum, style: FigureStyle = FigureStyle()) -> FigureScene {
        let t = style.typeSize
        let width = style.widthPoints, height = width * spectrumAspect
        let points = zip(spectrum.x, spectrum.y).filter { $0.0.isFinite && $0.1.isFinite }
        let xs = points.map(\.0), ys = points.map(\.1)
        let xRange = range(xs), yRange = range(ys + [0])
        let slack = 1e-9 * (xRange.high - xRange.low)
        let roundX = ticks(low: xRange.low, high: xRange.high), xStep = step(roundX)
        let xTicks = roundX.filter { $0 >= xRange.low - slack && $0 <= xRange.high + slack }
        let yTicks = ticks(low: yRange.low, high: yRange.high)
        let xLow = xRange.low, xHigh = xRange.high
        let yLow = min(yRange.low, yTicks.first ?? yRange.low), yHigh = max(yRange.high, yTicks.last ?? yRange.high)
        let xLabels = xTicks.map { number($0, step: xStep) }, yLabels = yTicks.map { number($0, step: step(yTicks)) }
        // The left margin holds the widest y number, the right one half the last x number, which can sit on the frame's edge.
        let left = max(5 * t, (yLabels.map { textWidth($0, size: t) }.max() ?? 0) + 0.4 * t + 1)
        let right = max(t, 0.5 * textWidth(xLabels.last ?? "", size: t) + 1)
        let plot = FigureRect(x: left, y: 2 * t, width: width - left - right, height: height - 5.5 * t)
        func px(_ x: Double) -> Double { plot.x + (x - xLow) / max(xHigh - xLow, .leastNonzeroMagnitude) * plot.width }
        func py(_ y: Double) -> Double { plot.y + plot.height - (y - yLow) / max(yHigh - yLow, .leastNonzeroMagnitude) * plot.height }

        var layers: [FigureLayer] = [.path(.rectangle(plot, stroke: .black, fill: nil, lineWidth: frameLineWidth))]
        let bottom = plot.y + plot.height
        for (tick, label) in zip(xTicks, xLabels) {
            let x = px(tick)
            layers.append(.path(FigurePath(points: [FigurePoint(x: x, y: bottom), FigurePoint(x: x, y: bottom - tickLength)],
                                           lineWidth: frameLineWidth)))
            layers.append(.text(FigureText(label, at: FigurePoint(x: x, y: bottom + 1.2 * t), anchor: .middle)))
        }
        for (tick, label) in zip(yTicks, yLabels) {
            let y = py(tick)
            layers.append(.path(FigurePath(points: [FigurePoint(x: plot.x, y: y), FigurePoint(x: plot.x + tickLength, y: y)],
                                           lineWidth: frameLineWidth)))
            layers.append(.text(FigureText(label, at: FigurePoint(x: plot.x - 0.4 * t, y: y + 0.35 * t), anchor: .end)))
        }
        layers.append(.text(FigureText(spectrum.xTitle, at: FigurePoint(x: plot.x + plot.width / 2, y: bottom + 2.6 * t), anchor: .middle)))
        layers.append(.text(FigureText(spectrum.yTitle, at: FigurePoint(x: plot.x, y: plot.y - 0.6 * t))))
        layers += markerLayers(spectrum.markers, plot: plot, typeSize: t) { $0 >= xLow && $0 <= xHigh ? px($0) : nil }
        if points.count >= 2 {
            let curve = decimated(points, columns: Int(plot.width.rounded(.up)) * 2).map { FigurePoint(x: px($0.0), y: py($0.1)) }
            layers.append(.path(FigurePath(points: curve, stroke: spectrum.color, lineWidth: curveLineWidth)))
        }
        return FigureScene(style: style, heightMM: height / FigureScene.pointsPerMillimetre, layers: layers)
    }

    /// Each marker as a line down the plot and its label at the top: to the line's right, or to its left where the right would leave
    /// the frame; a label that would overlap the one before it in its row drops a row (an Fe Kα beside an Fe Kβ).
    static func markerLayers(_ markers: [Spectrum.Marker], plot: FigureRect, typeSize t: Double, x position: (Double) -> Double?)
        -> [FigureLayer] {
        var layers: [FigureLayer] = []
        var rowEnds: [Double] = []
        let rows = max(1, Int((plot.height / (1.2 * t)).rounded(.down)) - 1)
        for marker in markers.filter({ $0.x.isFinite }).sorted(by: { $0.x < $1.x }) {
            guard let x = position(marker.x) else { continue }
            layers.append(.path(FigurePath(points: [FigurePoint(x: x, y: plot.y), FigurePoint(x: x, y: plot.y + plot.height)],
                                           stroke: marker.color, lineWidth: frameLineWidth)))
            let w = textWidth(marker.label, size: t)
            let fitsRight = x + 0.3 * t + w <= plot.x + plot.width
            let start = fitsRight ? x + 0.3 * t : x - 0.3 * t - w
            let row = rowEnds.firstIndex { start > $0 + 0.3 * t } ?? min(rowEnds.count, rows - 1)
            if row < rowEnds.count { rowEnds[row] = start + w } else { rowEnds.append(start + w) }
            let origin = FigurePoint(x: fitsRight ? start : x - 0.3 * t, y: plot.y + (1.1 + 1.2 * Double(row)) * t)
            layers.append(.text(FigureText(marker.label, at: origin, anchor: fitsRight ? .start : .end, color: marker.color)))
        }
        return layers
    }

    /// An estimate of a line of text's width in Helvetica at `size` points, for room in a layout (the text itself stays live): the
    /// digits and their signs are 0.556 em, as Helvetica draws them, every other character is taken at 0.667 em, which covers its
    /// capitals and most of its lowercase.
    static func textWidth(_ text: String, size: Double) -> Double {
        text.reduce(0) { $0 + ("0123456789.,-+−".contains($1) ? 0.556 : 0.667) } * size
    }

    /// The lowest and highest of `values`; 0 to 1 when there are none, and a unit wide around a single value.
    static func range(_ values: [Double]) -> (low: Double, high: Double) {
        guard let low = values.min(), let high = values.max() else { return (0, 1) }
        return low < high ? (low, high) : (low - 0.5, high + 0.5)
    }

    /// Round ticks covering `low` to `high`, four to eight of them: steps of 1, 2 or 5 times a power of ten (the usual plot rule).
    public static func ticks(low: Double, high: Double) -> [Double] {
        guard low.isFinite, high.isFinite, high > low else { return [] }
        let raw = (high - low) / 5
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { (high - low) / $0 <= 8 } ?? 10 * magnitude
        // A hair of tolerance: 0.3 / 0.1 is 2.9999999999999996, and 0.3 is a tick, not a step past one.
        let first = (low / step + 1e-9).rounded(.down) * step, last = (high / step - 1e-9).rounded(.up) * step
        let count = Int(((last - first) / step).rounded())
        return (0...count).map { first + Double($0) * step }
    }

    static func step(_ ticks: [Double]) -> Double { ticks.count >= 2 ? ticks[1] - ticks[0] : 1 }

    /// A tick's number with as many decimals as its step needs, in the POSIX locale; "-0" is written "0".
    static func number(_ value: Double, step: Double) -> String {
        // A step of 0.1 found as 100.2 − 100.1 is 0.09999…: a hair of tolerance keeps it one decimal.
        let decimals = max(0, Int((-log10(step) - 1e-6).rounded(.up)))
        let text = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
        return Double(text) == 0 ? String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), 0.0) : text
    }

    /// At most two points a column (the lowest and the highest, in their order; the first and the last point besides), so a spectrum of a million channels is a path a
    /// vector editor opens and still shows every peak; a curve with no more points than that is kept as it is.
    static func decimated(_ points: [(Double, Double)], columns: Int) -> [(Double, Double)] {
        guard columns >= 1, points.count > 2 * columns, let first = points.first?.0, let last = points.last?.0, last != first else {
            return points
        }
        // A spectrum stored high to low (a wavelength axis) is thinned the same way and kept in its order.
        if last < first { return Array(decimated(Array(points.reversed()), columns: columns).reversed()) }
        var out: [(Double, Double)] = []
        out.reserveCapacity(2 * columns)
        var start = 0
        while start < points.count {
            let column = min(columns - 1, Int((points[start].0 - first) / (last - first) * Double(columns)))
            var end = start
            var lowest = start, highest = start
            while end < points.count, min(columns - 1, Int((points[end].0 - first) / (last - first) * Double(columns))) == column {
                if points[end].1 < points[lowest].1 { lowest = end }
                if points[end].1 > points[highest].1 { highest = end }
                end += 1
            }
            // The curve's two ends stay, so it reaches the frame's edges however flat its first and last columns are.
            let ends = (start == 0 ? [0] : []) + (end == points.count ? [points.count - 1] : [])
            for index in Set([lowest, highest] + ends).sorted() { out.append(points[index]) }
            start = max(end, start + 1)
        }
        return out
    }

    // MARK: - A map

    /// What a map's key shows below it.
    public enum MapKey: Sendable, Equatable {
        /// One row per colour (a phase, an element of a colour mix).
        case entries([FigureLegend.Entry])
        /// A colour ramp from `colors.first` to `colors.last`, with its two ends' values and its title ("t/λ").
        case ramp(colors: [FigureColor], low: String, high: String, title: String)
    }

    /// A scale bar `lengthFraction` of the picture's width long, with its label ("500 nm").
    public struct ScaleBar: Sendable, Equatable {
        public var lengthFraction: Double
        public var label: String

        public init(lengthFraction: Double, label: String) {
            self.lengthFraction = lengthFraction
            self.label = label
        }
    }

    static let plateColor = FigureColor(gray: 0, alpha: 0.45)
    static let barThickness = 1.5, platePadding = 3.0, plateMargin = 4.0

    /// The map as a figure `style.width` wide: the picture across the width at its own pixels, the scale bar over its bottom left
    /// when given, and the key below it.
    public static func map(_ raster: FigureRaster, scaleBar: ScaleBar? = nil, key: MapKey? = nil, style: FigureStyle = FigureStyle()) -> FigureScene {
        let t = style.typeSize
        let width = style.widthPoints
        let pictureHeight = width * Double(raster.height) / Double(max(raster.width, 1))
        var layers: [FigureLayer] = [.raster(raster, frame: FigureRect(x: 0, y: 0, width: width, height: pictureHeight))]
        if let scaleBar, scaleBar.lengthFraction > 0 {
            layers += barLayers(length: scaleBar.lengthFraction * width, label: scaleBar.label, pictureHeight: pictureHeight, typeSize: t)
        }
        var height = pictureHeight
        switch key {
        case .entries(let entries) where !entries.isEmpty:
            layers.append(.legend(FigureLegend(origin: FigurePoint(x: 0, y: pictureHeight + 0.6 * t), entries: entries)))
            height += 0.6 * t + Double(entries.count) * FigureTable.rowHeightFactor * t
        case .ramp(let colors, let low, let high, let title) where !colors.isEmpty:
            let top = pictureHeight + 1.8 * t, rampWidth = width / 2, box = rampWidth / Double(colors.count)
            layers.append(.text(FigureText(title, at: FigurePoint(x: 0, y: top - 0.5 * t))))
            for (i, color) in colors.enumerated() {
                // Each box a hair wider than its share, so no seam shows between neighbours in a viewer that antialiases.
                layers.append(.path(.rectangle(FigureRect(x: Double(i) * box, y: top, width: box + 0.05, height: t), fill: color)))
            }
            layers.append(.path(.rectangle(FigureRect(x: 0, y: top, width: rampWidth, height: t), stroke: .black, fill: nil,
                                           lineWidth: frameLineWidth)))
            layers.append(.text(FigureText(low, at: FigurePoint(x: 0, y: top + 2 * t))))
            layers.append(.text(FigureText(high, at: FigurePoint(x: rampWidth, y: top + 2 * t), anchor: .end)))
            height = top + 2.5 * t
        default:
            break
        }
        return FigureScene(style: style, heightMM: height / FigureScene.pointsPerMillimetre, layers: layers)
    }

    /// The bar `length` points long at the picture's bottom left, its label above it, on a translucent black plate.
    static func barLayers(length: Double, label: String, pictureHeight: Double, typeSize: Double) -> [FigureLayer] {
        // An estimate of the label's width for the plate; the label itself is live text.
        let labelWidth = textWidth(label, size: typeSize)
        let plateWidth = max(length, labelWidth) + 2 * platePadding
        let plateHeight = typeSize + 2 + barThickness + 2 * platePadding
        let plate = FigureRect(x: plateMargin, y: pictureHeight - plateMargin - plateHeight, width: plateWidth, height: plateHeight)
        let barTop = plate.y + plate.height - platePadding - barThickness
        return [
            .path(.rectangle(plate, fill: plateColor)),
            .path(.rectangle(FigureRect(x: plate.x + platePadding, y: barTop, width: length, height: barThickness), fill: .white)),
            .text(FigureText(label, at: FigurePoint(x: plate.x + platePadding, y: barTop - 2), color: .white)),
        ]
    }
}
