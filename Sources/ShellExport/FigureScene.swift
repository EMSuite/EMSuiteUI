//
//  FigureScene.swift
//  Role: one figure as a value: its style (a journal column width and the type size), its height and its layers (a picture at its
//        own pixels, paths, markers, text, a table, a legend). `FigureRenderer` draws the same scene as PDF, SVG and PNG, so the
//        three cannot disagree.
//
//  COORDINATES are points (1/72 inch) from the figure's top-left corner, y down, as SVG has them; the PDF and PNG renderers flip.
//  A text label is one line at one origin (its baseline), never wrapped, so a vector editor keeps it as one run.
//

import Foundation

/// A point in figure points, from the top-left corner, y down.
public struct FigurePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle in figure points, from the top-left corner, y down.
public struct FigureRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// An sRGB colour, each component in 0...1.
public struct FigureColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(gray: Double, alpha: Double = 1) {
        self.init(red: gray, green: gray, blue: gray, alpha: alpha)
    }

    public static let black = FigureColor(gray: 0)
    public static let white = FigureColor(gray: 1)
}

/// The journal's frame for a figure: its column width and its type size, Helvetica throughout.
public struct FigureStyle: Sendable, Equatable {
    /// The widths Elsevier journals ask for (Ultramicroscopy, Acta Materialia, Micron): single, one and a half, double column.
    public enum Width: Double, Sendable, Equatable, CaseIterable {
        case mm90 = 90
        case mm140 = 140
        case mm190 = 190
    }

    public var width: Width
    /// The type size in points at final width.
    public var typeSize: Double

    public init(width: Width = .mm90, typeSize: Double = 7) {
        self.width = width
        self.typeSize = typeSize
    }

    /// The PostScript names of the PDF's and PNG's fonts.
    public static let fontName = "Helvetica"
    public static let boldFontName = "Helvetica-Bold"
    /// The SVG's font family: Helvetica where it is installed, its metric twin Arial elsewhere.
    public static let svgFontFamily = "Helvetica, Arial, sans-serif"

    public var widthMM: Double { width.rawValue }
    public var widthPoints: Double { widthMM * FigureScene.pointsPerMillimetre }
}

/// One figure: a style, a height and layers drawn in order, the first at the back.
public struct FigureScene: Sendable, Equatable {
    /// 72 points to the inch, 25.4 mm to the inch.
    public static let pointsPerMillimetre = 72.0 / 25.4

    public var style: FigureStyle
    /// The figure's height in millimetres (its width is the style's).
    public var heightMM: Double
    public var layers: [FigureLayer]

    public init(style: FigureStyle = FigureStyle(), heightMM: Double, layers: [FigureLayer]) {
        self.style = style
        self.heightMM = heightMM
        self.layers = layers
    }

    public var widthMM: Double { style.widthMM }
    public var widthPoints: Double { style.widthPoints }
    public var heightPoints: Double { heightMM * Self.pointsPerMillimetre }
}

/// One thing drawn in a figure.
public enum FigureLayer: Sendable, Equatable {
    /// A picture at its own pixels, stretched over `frame`, never smoothed.
    case raster(FigureRaster, frame: FigureRect)
    case path(FigurePath)
    case markers(FigureMarkers)
    case text(FigureText)
    case table(FigureTable)
    case legend(FigureLegend)
}

/// A picture's pixels: row-major from the top-left, 8 bits per sample.
public struct FigureRaster: Sendable, Equatable {
    public enum Format: Sendable, Equatable {
        case gray8
        case rgb8

        public var bytesPerPixel: Int {
            switch self {
            case .gray8: 1
            case .rgb8: 3
            }
        }
    }

    public let width: Int
    public let height: Int
    public let format: Format
    public let pixels: [UInt8]

    /// `pixels` holds `width * height * format.bytesPerPixel` bytes.
    public init(width: Int, height: Int, format: Format, pixels: [UInt8]) {
        precondition(width >= 1 && height >= 1, "FigureRaster: \(width) x \(height) pixels")
        precondition(pixels.count == width * height * format.bytesPerPixel,
                     "FigureRaster: \(pixels.count) bytes for \(width) x \(height) \(format)")
        self.width = width
        self.height = height
        self.format = format
        self.pixels = pixels
    }

    /// The pixels as RGB, three bytes each (gray is repeated), for the drawings that take colour only.
    var rgbPixels: [UInt8] {
        switch format {
        case .rgb8:
            return pixels
        case .gray8:
            var out = [UInt8]()
            out.reserveCapacity(pixels.count * 3)
            for value in pixels { out.append(contentsOf: [value, value, value]) }
            return out
        }
    }
}

/// A polyline, open or closed, stroked, filled or both.
public struct FigurePath: Sendable, Equatable {
    public var points: [FigurePoint]
    public var closed: Bool
    public var stroke: FigureColor?
    public var fill: FigureColor?
    /// The stroke's width in points.
    public var lineWidth: Double

    public init(points: [FigurePoint], closed: Bool = false, stroke: FigureColor? = .black, fill: FigureColor? = nil,
                lineWidth: Double = 0.5) {
        self.points = points
        self.closed = closed
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
    }

    /// A rectangle (a scale bar, a frame).
    public static func rectangle(_ rect: FigureRect, stroke: FigureColor? = nil, fill: FigureColor? = .black,
                                 lineWidth: Double = 0.5) -> FigurePath {
        FigurePath(points: [FigurePoint(x: rect.x, y: rect.y), FigurePoint(x: rect.x + rect.width, y: rect.y),
                            FigurePoint(x: rect.x + rect.width, y: rect.y + rect.height), FigurePoint(x: rect.x, y: rect.y + rect.height)],
                   closed: true, stroke: stroke, fill: fill, lineWidth: lineWidth)
    }
}

/// A marker's shape. A phase keeps one shape, so two phases read apart in grey too.
public enum FigureMarkerShape: String, Sendable, Equatable, CaseIterable {
    case circle
    case square
    case triangle
    case diamond
    /// ×
    case cross
    /// +
    case plus
}

/// Markers of one look at several centres (one phase's spots, one set of overlay positions).
public struct FigureMarkers: Sendable, Equatable {
    public var shape: FigureMarkerShape
    public var centers: [FigurePoint]
    /// The marker's width in points (a circle's diameter).
    public var size: Double
    public var stroke: FigureColor?
    public var fill: FigureColor?
    public var lineWidth: Double

    public init(shape: FigureMarkerShape, centers: [FigurePoint], size: Double, stroke: FigureColor? = .black,
                fill: FigureColor? = nil, lineWidth: Double = 0.5) {
        self.shape = shape
        self.centers = centers
        self.size = size
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
    }
}

/// Where a label's origin sits along its line.
public enum FigureTextAnchor: String, Sendable, Equatable {
    case start
    case middle
    case end
}

/// One line of text at one origin: the baseline's start, middle or end.
public struct FigureText: Sendable, Equatable {
    public var string: String
    public var origin: FigurePoint
    public var anchor: FigureTextAnchor
    /// Points; nil is the style's type size.
    public var size: Double?
    public var bold: Bool
    public var color: FigureColor

    public init(_ string: String, at origin: FigurePoint, anchor: FigureTextAnchor = .start, size: Double? = nil, bold: Bool = false,
                color: FigureColor = .black) {
        self.string = string
        self.origin = origin
        self.anchor = anchor
        self.size = size
        self.bold = bold
        self.color = color
    }
}

/// A ruled table (a rule above, under the header and below), at the style's type size, the header bold. Rows are
/// `FigureTable.rowHeightFactor` type sizes tall; columns are as wide as given, so the SVG needs no font metrics.
public struct FigureTable: Sendable, Equatable {
    /// The table's top-left corner.
    public var origin: FigurePoint
    public var columnWidths: [Double]
    /// Each column's anchor (a number column reads best at `.end`); missing entries are `.start`.
    public var anchors: [FigureTextAnchor]
    public var header: [String]
    public var rows: [[String]]

    public init(origin: FigurePoint, columnWidths: [Double], anchors: [FigureTextAnchor] = [], header: [String], rows: [[String]]) {
        self.origin = origin
        self.columnWidths = columnWidths
        self.anchors = anchors
        self.header = header
        self.rows = rows
    }

    /// A row's height in type sizes (the legend's too).
    public static let rowHeightFactor = 1.5
}

/// A key: one row per entry, a swatch then its label.
public struct FigureLegend: Sendable, Equatable {
    public enum Swatch: Sendable, Equatable {
        case marker(FigureMarkerShape, stroke: FigureColor?, fill: FigureColor?)
        /// A filled square (a map's colour).
        case box(FigureColor)
        /// A short line (a spectrum's colour).
        case line(FigureColor)
    }

    public struct Entry: Sendable, Equatable {
        public var label: String
        public var swatch: Swatch

        public init(_ label: String, swatch: Swatch) {
            self.label = label
            self.swatch = swatch
        }
    }

    /// The legend's top-left corner.
    public var origin: FigurePoint
    public var entries: [Entry]

    public init(origin: FigurePoint, entries: [Entry]) {
        self.origin = origin
        self.entries = entries
    }
}

/// What the files say about themselves: PDF document info, SVG `<title>`, `<desc>` and `<metadata>`, PNG text chunks.
public struct FigureMetadata: Sendable, Equatable {
    public var title: String
    /// The software line ("macEM 2.4.0").
    public var creator: String
    /// The methods record as JSON (`MethodsRecord.json()`), embedded as it is: PDF Subject, SVG `<metadata>`, PNG `Description`.
    public var methodsRecord: String?

    public init(title: String, creator: String, methodsRecord: String? = nil) {
        self.title = title
        self.creator = creator
        self.methodsRecord = methodsRecord
    }

    /// The metadata with `methods` as its record's canonical JSON; throws what `MethodsRecord.json()` throws.
    public init(title: String, creator: String, methods: MethodsRecord) throws {
        try self.init(title: title, creator: creator, methodsRecord: methods.json())
    }
}
