//
//  FigureRenderer.swift
//  Role: a figure scene as a file: PDF and SVG with live text, PNG at a chosen scale. One scene, three renderers, so the files
//        cannot disagree. Core Graphics and Core Text only (no SwiftUI, no AppKit), so it runs off the main actor.
//
//  PDF: one page the figure's size (90 mm wide is 255.118 pt), transparent, Helvetica embedded as a subset by Core Graphics; the
//  picture is embedded at its own pixels with interpolation off. Title and creator are the document info's, the methods record
//  is its Subject.
//  PNG: the same drawing on white at `scale` pixels per point, the picture's pixels nearest-neighbour; Title, Software and
//  Description (the methods record) as text chunks, written by FormatoCore's `FormatoPNG` (ImageIO turns those properties
//  into XMP instead).
//  SVG: `FigureRenderer+SVG.swift`.
//

import CoreGraphics
import CoreText
import FormatoCore
import Foundation

/// Why a figure could not be drawn.
public enum FigureRenderError: Error, Equatable, LocalizedError {
    /// Core Graphics did not open a context of the figure's size.
    case contextUnavailable
    /// The figure has no size, or its PNG would be wider or taller than 65 535 pixels.
    case unsupportedSize

    public var errorDescription: String? {
        switch self {
        case .contextUnavailable: "Core Graphics could not open a drawing context for the figure."
        case .unsupportedSize: "The figure has no size, or is too large for a PNG at this scale."
        }
    }
}

/// Draws a `FigureScene` as PDF, SVG or PNG.
public enum FigureRenderer {
    // MARK: - PDF

    /// The scene as a one-page PDF with live text.
    public static func pdf(_ scene: FigureScene, metadata: FigureMetadata) throws -> Data {
        let width = scene.widthPoints, height = scene.heightPoints
        guard width > 0, height > 0, width.isFinite, height.isFinite else { throw FigureRenderError.unsupportedSize }
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        var info: [CFString: Any] = [kCGPDFContextTitle: metadata.title, kCGPDFContextCreator: metadata.creator]
        if let record = metadata.methodsRecord { info[kCGPDFContextSubject] = record }
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else {
            throw FigureRenderError.contextUnavailable
        }
        context.beginPDFPage(nil)
        draw(scene.primitives, in: context, height: height)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    // MARK: - PNG

    /// The scene on white at `scale` pixels per point (300 dpi is 300 / 72), as 8-bit RGB with the metadata as text chunks.
    public static func png(_ scene: FigureScene, scale: Double, metadata: FigureMetadata) throws -> Data {
        let bitmap = try rgbBitmap(scene, scale: scale)
        var text: [PNGTextEntry] = []
        if !metadata.title.isEmpty { text.append(PNGTextEntry(keyword: "Title", value: metadata.title)) }
        if !metadata.creator.isEmpty { text.append(PNGTextEntry(keyword: "Software", value: metadata.creator)) }
        if let record = metadata.methodsRecord { text.append(PNGTextEntry(keyword: "Description", value: record)) }
        return try FormatoPNG.encode(width: bitmap.width, height: bitmap.height, format: .rgb8, pixels: Data(bitmap.rgb), text: text)
    }

    /// The PNG's pixels: RGB, three bytes each, row-major from the top-left.
    static func rgbBitmap(_ scene: FigureScene, scale: Double) throws -> (width: Int, height: Int, rgb: [UInt8]) {
        let side = (width: (scene.widthPoints * scale).rounded(), height: (scene.heightPoints * scale).rounded())
        // Checked before `Int(_:)`, which traps on NaN and on a value past Int's range.
        guard scale > 0, side.width >= 1, side.height >= 1,
              side.width <= Double(FormatoPNG.maximumSide), side.height <= Double(FormatoPNG.maximumSide) else {
            throw FigureRenderError.unsupportedSize
        }
        let pixelWidth = Int(side.width), pixelHeight = Int(side.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FigureRenderError.contextUnavailable
        }
        context.setFillColor(cgColor(.white))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        draw(scene.primitives, in: context, height: scene.heightPoints)
        guard let base = context.data else { throw FigureRenderError.contextUnavailable }

        // The bitmap's first row is the picture's top. The background is opaque, so premultiplied RGBA is plain RGBA.
        let bytesPerRow = context.bytesPerRow
        let source = base.assumingMemoryBound(to: UInt8.self)
        var rgb = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 3)
        for row in 0..<pixelHeight {
            for column in 0..<pixelWidth {
                let from = row * bytesPerRow + column * 4
                let to = (row * pixelWidth + column) * 3
                rgb[to] = source[from]
                rgb[to + 1] = source[from + 1]
                rgb[to + 2] = source[from + 2]
            }
        }
        return (width: pixelWidth, height: pixelHeight, rgb: rgb)
    }

    // MARK: - Core Graphics

    /// Draws `primitives` into `context`, whose user space is the figure's in points with y up; `height` is the figure's.
    static func draw(_ primitives: [FigurePrimitive], in context: CGContext, height: Double) {
        context.saveGState()
        // Figure space: y down from the top, as the scene and the SVG have it.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for primitive in primitives {
            switch primitive {
            case .raster(let raster, let frame):
                drawRaster(raster, in: frame, context: context)
            case .path(let subpaths, let closed, let paint):
                let path = CGMutablePath()
                for subpath in subpaths {
                    guard let first = subpath.first else { continue }
                    path.move(to: cgPoint(first))
                    for point in subpath.dropFirst() { path.addLine(to: cgPoint(point)) }
                    if closed { path.closeSubpath() }
                }
                paintPath(path, paint, context: context)
            case .circle(let center, let radius, let paint):
                let path = CGMutablePath()
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
                paintPath(path, paint, context: context)
            case .text(let run):
                drawText(run, context: context)
            }
        }
        context.restoreGState()
    }

    private static func paintPath(_ path: CGPath, _ paint: FigurePaint, context: CGContext) {
        if let fill = paint.fill {
            context.addPath(path)
            context.setFillColor(cgColor(fill))
            context.fillPath()
        }
        if let stroke = paint.stroke, paint.lineWidth > 0 {
            context.addPath(path)
            context.setStrokeColor(cgColor(stroke))
            context.setLineWidth(CGFloat(paint.lineWidth))
            context.strokePath()
        }
    }

    /// The picture at its own pixels over `frame`, nearest-neighbour. It is drawn as sRGB RGB (gray repeated), so a PNG's pixel
    /// keeps the picture's value.
    private static func drawRaster(_ raster: FigureRaster, in frame: FigureRect, context: CGContext) {
        guard let image = cgImage(raster) else { return }
        context.saveGState()
        context.interpolationQuality = .none
        // An image is drawn with its top at the rectangle's larger y; in figure space that is the bottom, so flip once more.
        context.translateBy(x: CGFloat(frame.x), y: CGFloat(frame.y + frame.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        context.restoreGState()
    }

    static func cgImage(_ raster: FigureRaster) -> CGImage? {
        let bytes = raster.rgbPixels
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8, bitsPerPixel: 24,
                       bytesPerRow: raster.width * 3, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// One Core Text line at its origin; a middle or end anchor moves it left by half or all of its typographic width.
    private static func drawText(_ run: FigureTextRun, context: CGContext) {
        guard !run.string.isEmpty, let line = ctLine(run) else { return }
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let x: Double
        switch run.anchor {
        case .start: x = run.origin.x
        case .middle: x = run.origin.x - width / 2
        case .end: x = run.origin.x - width
        }
        context.saveGState()
        // The user space is flipped (y down); the text matrix flips the glyphs back upright.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: run.origin.y)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func ctLine(_ run: FigureTextRun) -> CTLine? {
        let name = run.bold ? FigureStyle.boldFontName : FigureStyle.fontName
        let font = CTFontCreateWithName(name as CFString, CGFloat(run.size), nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: cgColor(run.color)]
        guard let attributed = CFAttributedStringCreate(kCFAllocatorDefault, run.string as CFString, attributes as CFDictionary) else {
            return nil
        }
        return CTLineCreateWithAttributedString(attributed)
    }

    private static func cgPoint(_ point: FigurePoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }

    static func cgColor(_ color: FigureColor) -> CGColor {
        CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.alpha))
    }
}
