import CoreGraphics
import FormatoCore
import Foundation
import PDFKit
import XCTest
@testable import ShellExport

/// Pin G1: six scenes built here, drawn as SVG (bytes equal to a golden), PDF (read back with PDFKit and Core Graphics) and PNG.
///
/// THE GOLDENS are `Goldens/<scene>.svg`, the SVG with each picture's base64 PNG replaced by `PNG` (the PNG's bytes come from the
/// Compression framework's deflate, which this pin does not own); `testSVGPictureIsThePictureAtItsOwnPixels` pins that payload
/// against FormatoCore's encoder instead. To write the goldens again after a deliberate change, run the tests once with
/// SHELLEXPORT_RECORD_GOLDENS=1 and review the diff.
final class FigureRendererTests: XCTestCase {
    static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Goldens")

    // MARK: - SVG

    func testSVGEqualsItsGolden() throws {
        let record = ProcessInfo.processInfo.environment["SHELLEXPORT_RECORD_GOLDENS"] == "1"
        for named in FigureTestScenes.all {
            let svg = Self.withoutPictureBytes(FigureRenderer.svg(named.scene, metadata: named.metadata))
            let url = Self.goldens.appendingPathComponent("\(named.name).svg")
            if record {
                try FileManager.default.createDirectory(at: Self.goldens, withIntermediateDirectories: true)
                try Data(svg.utf8).write(to: url)
                continue
            }
            let golden = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(svg, golden, "\(named.name): the SVG differs from Goldens/\(named.name).svg")
        }
        if record { XCTFail("Goldens recorded; unset SHELLEXPORT_RECORD_GOLDENS and review the diff.") }
    }

    /// Each `<image>`'s data URL is the picture's own pixels as FormatoCore's PNG: no resampling on the way.
    func testSVGPictureIsThePictureAtItsOwnPixels() throws {
        for named in FigureTestScenes.all {
            let svg = FigureRenderer.svg(named.scene, metadata: named.metadata)
            let payloads = Self.picturePayloads(svg)
            let rasters = Self.rasters(named.scene)
            XCTAssertEqual(payloads.count, rasters.count, named.name)
            for (payload, raster) in zip(payloads, rasters) {
                let expected = try FormatoPNG.encode(width: raster.width, height: raster.height,
                                                     format: raster.format == .gray8 ? .gray8 : .rgb8, pixels: Data(raster.pixels))
                XCTAssertEqual(Data(base64Encoded: payload), expected, named.name)
            }
        }
    }

    /// A marker sits within 0.01 pt of its overlay position, read from the SVG's numbers.
    func testMarkersSitOnTheirPositions() throws {
        let svg = FigureRenderer.svg(FigureTestScenes.overlay.scene, metadata: FigureTestScenes.overlay.metadata)
        let circles = Self.circleCenters(svg)
        XCTAssertEqual(circles.count, FigureTestScenes.spots.count)
        for (circle, spot) in zip(circles, FigureTestScenes.spots) {
            XCTAssertEqual(circle.x, spot.x, accuracy: 0.01)
            XCTAssertEqual(circle.y, spot.y, accuracy: 0.01)
        }

        // Two phases: the circles are the austenite's, each triangle's apex is half a marker above its ferrite position.
        let phases = FigureRenderer.svg(FigureTestScenes.phases.scene, metadata: FigureTestScenes.phases.metadata)
        let phaseCircles = Self.circleCenters(phases)
        XCTAssertEqual(phaseCircles.count, FigureTestScenes.austenite.count + 1, "two spots and the legend's swatch")
        for (circle, spot) in zip(phaseCircles, FigureTestScenes.austenite) {
            XCTAssertEqual(circle.x, spot.x, accuracy: 0.01)
            XCTAssertEqual(circle.y, spot.y, accuracy: 0.01)
        }
        for spot in FigureTestScenes.ferrite {
            XCTAssertTrue(phases.contains(#"<path d="M\#(FigureRenderer.number(spot.x)) \#(FigureRenderer.number(spot.y - 2.5)) "#),
                          "a triangle's apex at (\(spot.x), \(spot.y - 2.5))")
        }
    }

    func testSVGTextIsPlainTextInHelvetica() {
        let svg = FigureRenderer.svg(FigureTestScenes.table.scene, metadata: FigureTestScenes.table.metadata)
        XCTAssertTrue(svg.contains(##"<text x="170" y="17.7" font-family="Helvetica, Arial, sans-serif" font-size="7" font-weight="bold" fill="#000000">hkl</text>"##))
        XCTAssertTrue(svg.contains(##"<text x="224" y="28.2" font-family="Helvetica, Arial, sans-serif" font-size="7" text-anchor="end" fill="#000000">2.338</text>"##))
        XCTAssertTrue(svg.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        XCTAssertTrue(svg.contains(#" width="90mm" height="60mm" viewBox="0 0 255.118 170.079">"#))
    }

    func testSVGMetadataIsEscaped() {
        let svg = FigureRenderer.svg(FigureTestScenes.overlay.scene, metadata: FigureTestScenes.overlay.metadata)
        XCTAssertTrue(svg.contains("<title>Pattern &amp; overlay</title>"))
        XCTAssertTrue(svg.contains("<desc>EMSuiteUI tests</desc>"))
        XCTAssertTrue(svg.contains("<metadata>{&quot;room&quot;:&quot;diffraction&quot;,&quot;version&quot;:1}</metadata>"))
    }

    func testNumbersAndEscaping() {
        XCTAssertEqual(FigureRenderer.number(90 * 72.0 / 25.4), "255.118")
        XCTAssertEqual(FigureRenderer.number(7), "7")
        XCTAssertEqual(FigureRenderer.number(0.5), "0.5")
        XCTAssertEqual(FigureRenderer.number(-0.0001), "0")
        XCTAssertEqual(FigureRenderer.number(-2.25), "-2.25")
        XCTAssertEqual(FigureRenderer.number(.nan), "0")
        XCTAssertEqual(FigureRenderer.hex(FigureColor(red: 1, green: 0.5, blue: 0)), "#ff8000")
        XCTAssertEqual(FigureRenderer.escaped("a<b>&\"c'\u{1}"), "a&lt;b&gt;&amp;&quot;c&apos;")
    }

    // MARK: - Style

    func testStyleWidthsAndTypeSize() {
        XCTAssertEqual(FigureStyle().widthMM, 90)
        XCTAssertEqual(FigureStyle().typeSize, 7)
        XCTAssertEqual(FigureStyle.Width.allCases.map(\.rawValue), [90, 140, 190])
        XCTAssertEqual(FigureStyle(width: .mm190).widthPoints, 190 * 72 / 25.4, accuracy: 1e-9)
    }

    // MARK: - PDF

    func testPDFReadBack() throws {
        for named in FigureTestScenes.all {
            let data = try FigureRenderer.pdf(named.scene, metadata: named.metadata)
            let document = try XCTUnwrap(PDFDocument(data: data), named.name)
            XCTAssertEqual(document.pageCount, 1, named.name)
            let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
            XCTAssertEqual(Double(box.width) * 25.4 / 72, named.scene.widthMM, accuracy: 0.01, named.name)
            XCTAssertEqual(Double(box.height) * 25.4 / 72, named.scene.heightMM, accuracy: 0.01, named.name)

            // Every label is text in the file (whitespace aside: PDFKit spaces runs as it reads them).
            let text = Self.squeezed(document.string ?? "")
            for label in Self.labels(named.scene) {
                XCTAssertTrue(text.contains(Self.squeezed(label)), "\(named.name): \"\(label)\" is not text in the PDF")
            }

            let attributes = document.documentAttributes ?? [:]
            XCTAssertEqual(attributes[PDFDocumentAttribute.titleAttribute] as? String, named.metadata.title, named.name)
            XCTAssertEqual(attributes[PDFDocumentAttribute.creatorAttribute] as? String, named.metadata.creator, named.name)
            if let record = named.metadata.methodsRecord {
                XCTAssertEqual(attributes[PDFDocumentAttribute.subjectAttribute] as? String, record, named.name)
            }

            // The fonts are embedded, and each picture is in the file at its own pixel size.
            XCTAssertNotNil(data.range(of: Data("/FontFile".utf8)), "\(named.name): no embedded font")
            let sizes = PDFPictures.sizes(in: data)
            for raster in Self.rasters(named.scene) {
                XCTAssertTrue(sizes.contains([raster.width, raster.height]),
                              "\(named.name): no \(raster.width) x \(raster.height) picture in the PDF, found \(sizes)")
            }
        }
    }

    // MARK: - PNG

    func testPNGSizeAndTextChunks() throws {
        let named = FigureTestScenes.overlay
        let png = try FigureRenderer.png(named.scene, scale: 300.0 / 72, metadata: named.metadata)
        let width = Int(Self.bigEndian32(png, at: 16)), height = Int(Self.bigEndian32(png, at: 20))
        XCTAssertEqual(width, Int((named.scene.widthPoints * 300 / 72).rounded()))
        XCTAssertEqual(height, Int((named.scene.heightPoints * 300 / 72).rounded()))
        let entries = try FormatoPNG.textEntries(in: png)
        XCTAssertEqual(entries, [PNGTextEntry(keyword: "Title", value: "Pattern & overlay"),
                                 PNGTextEntry(keyword: "Software", value: "EMSuiteUI tests"),
                                 PNGTextEntry(keyword: "Description", value: #"{"room":"diffraction","version":1}"#)])
    }

    /// The picture keeps its own pixels: 3 px inside each 20-pt pixel's edge the PNG holds the pixel's value, where smoothing
    /// would blend in a neighbour 30 levels away.
    func testPNGPictureIsNeverSmoothed() throws {
        let named = FigureTestScenes.image
        let bitmap = try FigureRenderer.rgbBitmap(named.scene, scale: 1)
        XCTAssertEqual(bitmap.width, 255)
        XCTAssertEqual(bitmap.height, 170)
        let frame = FigureTestScenes.imageFrame
        let raster = FigureTestScenes.gradient
        for j in 0..<raster.height {
            for i in 0..<raster.width where !(i >= 5 && j >= 5) {   // the scale bar and its label sit on the bottom-right pixels
                let value = Int(raster.pixels[j * raster.width + i])
                for (dx, dy) in [(3, 3), (16, 3), (3, 16), (16, 16), (10, 10)] {
                    let x = Int(frame.x) + 20 * i + dx, y = Int(frame.y) + 20 * j + dy
                    let index = (y * bitmap.width + x) * 3
                    for channel in 0..<3 {
                        XCTAssertLessThanOrEqual(abs(Int(bitmap.rgb[index + channel]) - value), 1,
                                                 "pixel (\(i), \(j)) at (\(x), \(y)) channel \(channel)")
                    }
                }
            }
        }
        // White outside the picture.
        XCTAssertEqual(Array(bitmap.rgb[0..<3]), [255, 255, 255])
    }

    func testPNGRefusesAScaleWithNoSize() {
        XCTAssertThrowsError(try FigureRenderer.png(FigureTestScenes.image.scene, scale: 0, metadata: FigureTestScenes.image.metadata))
        XCTAssertThrowsError(try FigureRenderer.png(FigureTestScenes.image.scene, scale: .nan, metadata: FigureTestScenes.image.metadata))
    }

    // MARK: - Helpers

    static func labels(_ scene: FigureScene) -> [String] {
        scene.primitives.compactMap { primitive in
            if case .text(let run) = primitive { return run.string }
            return nil
        }
    }

    static func rasters(_ scene: FigureScene) -> [FigureRaster] {
        scene.layers.compactMap { layer in
            if case .raster(let raster, _) = layer { return raster }
            return nil
        }
    }

    static func squeezed(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) { out.append(scalar) }
        return String(out)
    }

    static let pictureMarker = "data:image/png;base64,"

    /// The SVG with every picture's base64 payload replaced by `PNG`.
    static func withoutPictureBytes(_ svg: String) -> String {
        let parts = svg.components(separatedBy: pictureMarker)
        guard parts.count > 1 else { return svg }
        var out = parts[0]
        for part in parts.dropFirst() {
            let rest = part.firstIndex(of: "\"").map { String(part[$0...]) } ?? part
            out += pictureMarker + "PNG" + rest
        }
        return out
    }

    static func picturePayloads(_ svg: String) -> [String] {
        svg.components(separatedBy: pictureMarker).dropFirst().map { part in
            String(part.prefix { $0 != "\"" })
        }
    }

    /// Every `<circle cx="…" cy="…"` in document order.
    static func circleCenters(_ svg: String) -> [FigurePoint] {
        svg.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("<circle ") else { return nil }
            guard let x = attribute("cx", in: line).flatMap({ Double($0) }), let y = attribute("cy", in: line).flatMap({ Double($0) }) else {
                return nil
            }
            return FigurePoint(x: x, y: y)
        }
    }

    static func attribute(_ name: String, in line: String) -> String? {
        guard let start = line.range(of: " \(name)=\"") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    static func bigEndian32(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = Array(data[offset..<(offset + 4)])
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
}

/// The pictures a PDF page draws, as [width, height] in pixels, read from its image XObjects (and those of its forms).
enum PDFPictures {
    final class Found {
        var sizes: [[Int]] = []
    }

    static func sizes(in data: Data) -> [[Int]] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: 1), let dictionary = page.dictionary else { return [] }
        let found = Found()
        collect(dictionary, into: found)
        return found.sizes
    }

    static func collect(_ owner: CGPDFDictionaryRef, into found: Found) {
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(owner, "Resources", &resources), let resources else { return }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return }
        let info = Unmanaged.passUnretained(found).toOpaque()
        CGPDFDictionaryApplyFunction(objects, { _, object, info in
            guard let info else { return }
            let found = Unmanaged<PDFPictures.Found>.fromOpaque(info).takeUnretainedValue()
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream) else {
                return
            }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
            switch String(cString: subtype) {
            case "Image":
                var width: CGPDFInteger = 0
                var height: CGPDFInteger = 0
                if CGPDFDictionaryGetInteger(dictionary, "Width", &width), CGPDFDictionaryGetInteger(dictionary, "Height", &height) {
                    found.sizes.append([Int(width), Int(height)])
                }
            case "Form":
                PDFPictures.collect(dictionary, into: found)
            default:
                break
            }
        }, info)
    }
}
