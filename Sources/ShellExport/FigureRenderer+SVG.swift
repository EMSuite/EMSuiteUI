//
//  FigureRenderer+SVG.swift
//  Role: the scene as SVG 1.1 text, deterministic so it can be compared byte for byte: one element per line in the scene's
//        order, numbers in points with at most three decimals (en_US_POSIX, trailing zeros dropped), colours as #rrggbb.
//
//  Text is plain `<text>` in "Helvetica, Arial, sans-serif", one element per label. The picture is a PNG of its own pixels in a
//  data URL, drawn pixelated. The title is `<title>`, the creator `<desc>`, the methods record `<metadata>`.
//

import FormatoCore
import Foundation

extension FigureRenderer {
    /// The scene as an SVG document, `width` and `height` in millimetres and the view box in points.
    public static func svg(_ scene: FigureScene, metadata: FigureMetadata) -> String {
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1""#
            + #" width="\#(number(scene.widthMM))mm" height="\#(number(scene.heightMM))mm""#
            + #" viewBox="0 0 \#(number(scene.widthPoints)) \#(number(scene.heightPoints))">"#)
        if !metadata.title.isEmpty { lines.append("<title>\(escaped(metadata.title))</title>") }
        if !metadata.creator.isEmpty { lines.append("<desc>\(escaped(metadata.creator))</desc>") }
        if let record = metadata.methodsRecord { lines.append("<metadata>\(escaped(record))</metadata>") }
        for primitive in scene.primitives {
            if let element = element(primitive) { lines.append(element) }
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// One primitive as one SVG element.
    static func element(_ primitive: FigurePrimitive) -> String? {
        switch primitive {
        case .raster(let raster, let frame):
            guard let png = try? FormatoPNG.encode(width: raster.width, height: raster.height,
                                                   format: raster.format == .gray8 ? .gray8 : .rgb8,
                                                   pixels: Data(raster.pixels)) else { return nil }
            return #"<image x="\#(number(frame.x))" y="\#(number(frame.y))" width="\#(number(frame.width))""#
                + #" height="\#(number(frame.height))" preserveAspectRatio="none""#
                + #" style="image-rendering:optimizeSpeed;image-rendering:pixelated""#
                + #" xlink:href="data:image/png;base64,\#(png.base64EncodedString())"/>"#
        case .path(let subpaths, let closed, let paint):
            var data: [String] = []
            for subpath in subpaths {
                guard let first = subpath.first else { continue }
                var parts = ["M\(number(first.x)) \(number(first.y))"]
                for point in subpath.dropFirst() { parts.append("L\(number(point.x)) \(number(point.y))") }
                if closed { parts.append("Z") }
                data.append(parts.joined(separator: " "))
            }
            guard !data.isEmpty else { return nil }
            return #"<path d="\#(data.joined(separator: " "))"\#(paintAttributes(paint))/>"#
        case .circle(let center, let radius, let paint):
            return #"<circle cx="\#(number(center.x))" cy="\#(number(center.y))" r="\#(number(radius))"\#(paintAttributes(paint))/>"#
        case .text(let run):
            guard !run.string.isEmpty else { return nil }
            var attributes = #" x="\#(number(run.origin.x))" y="\#(number(run.origin.y))""#
                + #" font-family="\#(FigureStyle.svgFontFamily)" font-size="\#(number(run.size))""#
            if run.bold { attributes += #" font-weight="bold""# }
            if run.anchor != .start { attributes += #" text-anchor="\#(run.anchor.rawValue)""# }
            attributes += colorAttributes("fill", run.color)
            return "<text\(attributes)>\(escaped(run.string))</text>"
        }
    }

    /// ` fill="…" stroke="…" stroke-width="…"`; `fill="none"` when the shape is not filled.
    private static func paintAttributes(_ paint: FigurePaint) -> String {
        var out = paint.fill.map { colorAttributes("fill", $0) } ?? #" fill="none""#
        if let stroke = paint.stroke, paint.lineWidth > 0 {
            out += colorAttributes("stroke", stroke)
            out += #" stroke-width="\#(number(paint.lineWidth))""#
        }
        return out
    }

    /// ` fill="#rrggbb"`, with ` fill-opacity="…"` when the colour is not opaque.
    private static func colorAttributes(_ name: String, _ color: FigureColor) -> String {
        var out = #" \#(name)="\#(hex(color))""#
        if color.alpha < 1 { out += #" \#(name)-opacity="\#(number(max(0, color.alpha)))""# }
        return out
    }

    static func hex(_ color: FigureColor) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", locale: posix, byte(color.red), byte(color.green), byte(color.blue))
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// At most three decimals, trailing zeros and a trailing point dropped, never "-0": 255.11811 is "255.118", 7.0 is "7".
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        var text = String(format: "%.3f", locale: posix, value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// Text and attribute values with &, <, >, " and ' escaped; characters XML 1.0 cannot hold are dropped.
    static func escaped(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            default:
                let value = scalar.value
                if value < 0x20 || value == 0xFFFE || value == 0xFFFF { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
