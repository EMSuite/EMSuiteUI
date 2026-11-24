//
//  FigurePlot+Panels.swift
//  Role: maps side by side as one vector figure (Electron-Microscopy-Studio#902, plan row X10): a title line, then the panels in
//        rows, each its title, its picture at its own pixels with the lines drawn over it (regions) and a vector scale bar on a plate,
//        and under it a colour ramp with its two ends' values and a footer, wrapped. The EDS and EELS rooms' maps figures are laid
//        out here; `FigureRenderer` writes them as PDF, SVG or PNG.
//

import Foundation

extension FigurePlot {
    /// One map of a panel figure.
    public struct Panel: Sendable, Equatable {
        public var title: String
        /// Beside the title, lighter ("Kα", "t/λ").
        public var detail: String
        public var picture: FigureRaster
        /// Lines over the picture in its pixel coordinates (x right, y down, a pixel one unit), their widths in points.
        public var overlay: [FigurePath]
        public var scaleBar: ScaleBar?
        /// The colour ramp under the picture.
        public var ramp: Ramp?
        public var footer: String?

        public init(title: String, detail: String = "", picture: FigureRaster, overlay: [FigurePath] = [], scaleBar: ScaleBar? = nil,
                    ramp: Ramp? = nil, footer: String? = nil) {
            self.title = title
            self.detail = detail
            self.picture = picture
            self.overlay = overlay
            self.scaleBar = scaleBar
            self.ramp = ramp
            self.footer = footer
        }
    }

    /// A colour ramp: its colours from low to high and the values at its ends in words ("0.21", "0.85 t/λ").
    public struct Ramp: Sendable, Equatable {
        public var colors: [FigureColor]
        public var low: String
        public var high: String

        public init(colors: [FigureColor], low: String, high: String) {
            self.colors = colors
            self.low = low
            self.high = high
        }
    }

    static let panelGap = 6.0

    /// The panels as a figure `style.width` wide under `title` and `subtitle`: two a row at 90 mm, three at 140 and 190 mm, each
    /// picture scaled to its column's width.
    public static func panels(_ panels: [Panel], title: String, subtitle: String = "", style: FigureStyle = FigureStyle()) -> FigureScene {
        let t = style.typeSize, width = style.widthPoints
        let columns = max(1, min(style.width == .mm90 ? 2 : 3, panels.count))
        let column = (width - Double(columns - 1) * panelGap) / Double(columns)
        var layers: [FigureLayer] = [.text(FigureText(title, at: FigurePoint(x: 0, y: t), bold: true))]
        var top = 1.6 * t
        if !subtitle.isEmpty {
            layers.append(.text(FigureText(subtitle, at: FigurePoint(x: 0, y: top + t), color: FigureColor(gray: 0.35))))
            top += 1.4 * t
        }
        top += 0.6 * t
        var start = 0
        while start < panels.count {
            let row = panels[start..<min(start + columns, panels.count)]
            var rowHeight = 0.0
            for (i, panel) in row.enumerated() {
                let made = panelLayers(of: panel, width: column, typeSize: t)
                layers += made.layers.map { $0.offset(x: Double(i) * (column + panelGap), y: top) }
                rowHeight = max(rowHeight, made.height)
            }
            top += rowHeight + panelGap
            start += columns
        }
        return FigureScene(style: style, heightMM: (top - panelGap) / FigureScene.pointsPerMillimetre, layers: layers)
    }

    /// One panel `width` wide from its top-left corner, and its height.
    static func panelLayers(of panel: Panel, width: Double, typeSize t: Double) -> (layers: [FigureLayer], height: Double) {
        var layers: [FigureLayer] = [.text(FigureText(panel.title, at: FigurePoint(x: 0, y: t), bold: true))]
        if !panel.detail.isEmpty {
            let x = textWidth(panel.title, size: t) + 0.4 * t
            layers.append(.text(FigureText(panel.detail, at: FigurePoint(x: x, y: t), color: FigureColor(gray: 0.35))))
        }
        let top = 1.5 * t
        let k = width / Double(max(panel.picture.width, 1))
        let pictureHeight = k * Double(panel.picture.height)
        var picture: [FigureLayer] = [.raster(panel.picture, frame: FigureRect(x: 0, y: 0, width: width, height: pictureHeight))]
        picture += panel.overlay.map { path in
            var path = path
            path.points = path.points.map { FigurePoint(x: $0.x * k, y: $0.y * k) }
            return .path(path)
        }
        if let bar = panel.scaleBar, bar.lengthFraction > 0 {
            picture += barLayers(length: bar.lengthFraction * width, label: bar.label, pictureHeight: pictureHeight, typeSize: t)
        }
        layers += picture.map { $0.offset(x: 0, y: top) }
        var y = top + pictureHeight
        if let ramp = panel.ramp, !ramp.colors.isEmpty {
            let low = textWidth(ramp.low, size: t), high = textWidth(ramp.high, size: t)
            let rampX = low + 0.4 * t, rampWidth = max(t, width - low - high - 0.8 * t), box = rampWidth / Double(ramp.colors.count)
            let barTop = y + 0.5 * t
            layers.append(.text(FigureText(ramp.low, at: FigurePoint(x: 0, y: barTop + 0.85 * t))))
            for (i, color) in ramp.colors.enumerated() {
                layers.append(.path(.rectangle(FigureRect(x: rampX + Double(i) * box, y: barTop, width: box + 0.05, height: t), fill: color)))
            }
            layers.append(.path(.rectangle(FigureRect(x: rampX, y: barTop, width: rampWidth, height: t), stroke: .black, fill: nil,
                                           lineWidth: frameLineWidth)))
            layers.append(.text(FigureText(ramp.high, at: FigurePoint(x: width, y: barTop + 0.85 * t), anchor: .end)))
            y = barTop + t
        }
        if let footer = panel.footer, !footer.isEmpty {
            for line in wrapped(footer, width: width, size: t) {
                y += 1.2 * t
                layers.append(.text(FigureText(line, at: FigurePoint(x: 0, y: y), color: FigureColor(gray: 0.35))))
            }
            y += 0.3 * t
        }
        return (layers, y)
    }

    /// `text` broken at spaces into lines no wider than `width` by the layout's estimate; a word wider than a line stands alone.
    static func wrapped(_ text: String, width: Double, size: Double) -> [String] {
        var lines: [String] = [], line = ""
        for word in text.split(separator: " ") {
            let candidate = line.isEmpty ? String(word) : line + " " + word
            if !line.isEmpty, textWidth(candidate, size: size) > width {
                lines.append(line)
                line = String(word)
            } else {
                line = candidate
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}

extension FigureLayer {
    /// The layer moved by `x` and `y` points.
    func offset(x dx: Double, y dy: Double) -> FigureLayer {
        func moved(_ p: FigurePoint) -> FigurePoint { FigurePoint(x: p.x + dx, y: p.y + dy) }
        switch self {
        case .raster(let raster, let frame):
            return .raster(raster, frame: FigureRect(x: frame.x + dx, y: frame.y + dy, width: frame.width, height: frame.height))
        case .path(var path):
            path.points = path.points.map(moved)
            return .path(path)
        case .markers(var markers):
            markers.centers = markers.centers.map(moved)
            return .markers(markers)
        case .text(var text):
            text.origin = moved(text.origin)
            return .text(text)
        case .table(var table):
            table.origin = moved(table.origin)
            return .table(table)
        case .legend(var legend):
            legend.origin = moved(legend.origin)
            return .legend(legend)
        }
    }
}
