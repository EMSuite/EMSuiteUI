//
//  FigurePrimitives.swift
//  Role: a scene lowered to four primitives (a picture, a path, a circle, a line of text), the only things the renderers draw.
//        Markers, tables and legends become primitives here, once, so the PDF, the PNG and the SVG place them alike.
//

import Foundation

/// How a path or circle is painted.
struct FigurePaint: Equatable {
    var fill: FigureColor?
    var stroke: FigureColor?
    var lineWidth: Double
}

/// One line of text with its size resolved.
struct FigureTextRun: Equatable {
    var string: String
    var origin: FigurePoint
    var anchor: FigureTextAnchor
    var size: Double
    var bold: Bool
    var color: FigureColor
}

/// What the renderers draw.
enum FigurePrimitive: Equatable {
    case raster(FigureRaster, FigureRect)
    /// Polylines; each subpath is closed when `closed`.
    case path([[FigurePoint]], closed: Bool, FigurePaint)
    case circle(center: FigurePoint, radius: Double, FigurePaint)
    case text(FigureTextRun)
}

extension FigureScene {
    /// The scene as primitives, back to front.
    var primitives: [FigurePrimitive] {
        var out: [FigurePrimitive] = []
        let typeSize = style.typeSize
        for layer in layers {
            switch layer {
            case .raster(let raster, let frame):
                out.append(.raster(raster, frame))
            case .path(let path):
                guard !path.points.isEmpty else { continue }
                out.append(.path([path.points], closed: path.closed,
                                 FigurePaint(fill: path.fill, stroke: path.stroke, lineWidth: path.lineWidth)))
            case .markers(let markers):
                let paint = FigurePaint(fill: markers.fill, stroke: markers.stroke, lineWidth: markers.lineWidth)
                for center in markers.centers {
                    out.append(Self.marker(markers.shape, at: center, size: markers.size, paint: paint))
                }
            case .text(let text):
                out.append(.text(FigureTextRun(string: text.string, origin: text.origin, anchor: text.anchor,
                                               size: text.size ?? typeSize, bold: text.bold, color: text.color)))
            case .table(let table):
                out += Self.table(table, typeSize: typeSize)
            case .legend(let legend):
                out += Self.legend(legend, typeSize: typeSize)
            }
        }
        return out
    }

    /// One marker of width `size` centred on `center`. The triangle points up and its box is centred on `center`.
    static func marker(_ shape: FigureMarkerShape, at center: FigurePoint, size: Double, paint: FigurePaint) -> FigurePrimitive {
        let r = size / 2
        let x = center.x, y = center.y
        switch shape {
        case .circle:
            return .circle(center: center, radius: r, paint)
        case .square:
            return .path([[FigurePoint(x: x - r, y: y - r), FigurePoint(x: x + r, y: y - r),
                           FigurePoint(x: x + r, y: y + r), FigurePoint(x: x - r, y: y + r)]], closed: true, paint)
        case .triangle:
            return .path([[FigurePoint(x: x, y: y - r), FigurePoint(x: x + r, y: y + r), FigurePoint(x: x - r, y: y + r)]],
                         closed: true, paint)
        case .diamond:
            return .path([[FigurePoint(x: x, y: y - r), FigurePoint(x: x + r, y: y),
                           FigurePoint(x: x, y: y + r), FigurePoint(x: x - r, y: y)]], closed: true, paint)
        case .cross:
            // Strokes only: a cross has no inside to fill.
            return .path([[FigurePoint(x: x - r, y: y - r), FigurePoint(x: x + r, y: y + r)],
                          [FigurePoint(x: x + r, y: y - r), FigurePoint(x: x - r, y: y + r)]], closed: false,
                         FigurePaint(fill: nil, stroke: paint.stroke ?? paint.fill, lineWidth: paint.lineWidth))
        case .plus:
            return .path([[FigurePoint(x: x - r, y: y), FigurePoint(x: x + r, y: y)],
                          [FigurePoint(x: x, y: y - r), FigurePoint(x: x, y: y + r)]], closed: false,
                         FigurePaint(fill: nil, stroke: paint.stroke ?? paint.fill, lineWidth: paint.lineWidth))
        }
    }

    /// A text baseline `1.1` type sizes below a row's top: the cap height's middle on the row's middle (rows 1.5 type sizes tall).
    static let baselineFactor = 1.1

    static func table(_ table: FigureTable, typeSize: Double) -> [FigurePrimitive] {
        var out: [FigurePrimitive] = []
        let rowHeight = FigureTable.rowHeightFactor * typeSize
        let left = table.origin.x, top = table.origin.y
        var totalWidth = 0.0
        for width in table.columnWidths { totalWidth += width }
        let right = left + totalWidth
        let rule = FigurePaint(fill: nil, stroke: .black, lineWidth: 0.5)
        let lines = [table.header] + table.rows
        for (index, cells) in lines.enumerated() {
            let baseline = top + Double(index) * rowHeight + baselineFactor * typeSize
            var columnLeft = left
            for (column, width) in table.columnWidths.enumerated() {
                defer { columnLeft += width }
                guard column < cells.count, !cells[column].isEmpty else { continue }
                let anchor = column < table.anchors.count ? table.anchors[column] : .start
                let x: Double
                switch anchor {
                case .start: x = columnLeft
                case .middle: x = columnLeft + width / 2
                case .end: x = columnLeft + width
                }
                out.append(.text(FigureTextRun(string: cells[column], origin: FigurePoint(x: x, y: baseline), anchor: anchor,
                                               size: typeSize, bold: index == 0, color: .black)))
            }
        }
        let bottom = top + Double(lines.count) * rowHeight
        for y in [top, top + rowHeight, bottom] {
            out.append(.path([[FigurePoint(x: left, y: y), FigurePoint(x: right, y: y)]], closed: false, rule))
        }
        return out
    }

    static func legend(_ legend: FigureLegend, typeSize: Double) -> [FigurePrimitive] {
        var out: [FigurePrimitive] = []
        let rowHeight = FigureTable.rowHeightFactor * typeSize
        let left = legend.origin.x
        for (index, entry) in legend.entries.enumerated() {
            let rowTop = legend.origin.y + Double(index) * rowHeight
            let middle = rowTop + rowHeight / 2
            switch entry.swatch {
            case .marker(let shape, let stroke, let fill):
                out.append(marker(shape, at: FigurePoint(x: left + typeSize / 2, y: middle), size: typeSize,
                                  paint: FigurePaint(fill: fill, stroke: stroke, lineWidth: 0.5)))
            case .box(let color):
                let half = typeSize / 2
                out.append(.path([[FigurePoint(x: left, y: middle - half), FigurePoint(x: left + typeSize, y: middle - half),
                                   FigurePoint(x: left + typeSize, y: middle + half), FigurePoint(x: left, y: middle + half)]],
                                 closed: true, FigurePaint(fill: color, stroke: nil, lineWidth: 0.5)))
            case .line(let color):
                out.append(.path([[FigurePoint(x: left, y: middle), FigurePoint(x: left + typeSize, y: middle)]], closed: false,
                                 FigurePaint(fill: nil, stroke: color, lineWidth: 1)))
            }
            out.append(.text(FigureTextRun(string: entry.label, origin: FigurePoint(x: left + 2 * typeSize, y: rowTop + baselineFactor * typeSize),
                                           anchor: .start, size: typeSize, bold: false, color: .black)))
        }
        return out
    }
}
