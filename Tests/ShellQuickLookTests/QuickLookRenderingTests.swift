//
//  QuickLookRenderingTests.swift
//  4DSTEM Studio's Quick Look tests (suite task 47c), moved with the code (EMSuiteUI#225) and run unchanged against ShellQuickLook;
//  the scale bar's tests are new. The pixels and the preview card, on planted frames, UI-free. Registration, stated before the first run:
//  - Stretch: a 100 x 100 ramp (value = column + 100 * row, 0...9999) puts its 1 % and 99 % levels at the sorted values at
//    rank round(9999 * 0.01) = 100 and round(9999 * 0.99) = 9899; the darkest pixel maps to 0, the brightest to 255, and the map is
//    monotone in the value.
//  - Pattern: a 64 x 64 frame of background 10 with a 1e6 centre and a 1e3 ring: in log scale the ring is well above black
//    (linear 1e3 / 1e6 would be 0.1 % of white = 0); the centre is 255.
//  - Spectrum: a trace, drawn 2:1; its bitmap has bright pixels on a black ground.
//  - Rows: the card lists format, size, step, voltage and camera length from the summary with a locale-free decimal mark; a 4D file
//    lists the scan and the detector separately; missing facts add no row.
//  - Card: the PNG data is a PNG, 1520 x 800 pixels (760 x 400 pt at scale 2).
//

import XCTest
import CoreGraphics
import ImageIO
import FormatoPeek
import ImagoCore
import ShellQuickLook

nonisolated final class QuickLookRenderingTests: XCTestCase {
    private func frame(_ width: Int, _ height: Int, kind: Peek.Kind = .image, _ value: (Int, Int) -> Float) -> Peek.Frame {
        var pixels: [Float] = []
        for r in 0..<height { for c in 0..<width { pixels.append(value(r, c)) } }
        return Peek.Frame(width: width, height: height, pixels: pixels, sourceWidth: width, sourceHeight: height, stride: 1,
                          kind: kind, enteredAt: [], source: "planted")
    }

    func testAnImageIsStretchedBetweenItsOnePercentAndNinetyNinePercentLevels() {
        let ramp = frame(100, 100) { r, c in Float(c + 100 * r) }
        let s = QuickLookRendering.stretch(for: ramp)
        XCTAssertEqual(s.low, 100); XCTAssertEqual(s.high, 9899); XCTAssertFalse(s.logScale)
        let grey = QuickLookRendering.grayscale(ramp)
        XCTAssertEqual(grey[0], 0); XCTAssertEqual(grey[9999], 255)
        XCTAssertEqual(grey[100 * 50 + 50], 128, accuracy: 1, "the middle value maps to the middle grey")
        for i in 1..<grey.count { XCTAssertGreaterThanOrEqual(grey[i], grey[i - 1], "monotone along the ramp") }
    }

    func testADiffractionPatternIsDrawnInLogScaleSoTheRingIsVisible() {
        let pattern = frame(64, 64, kind: .diffractionPattern) { r, c in
            let d = ((Double(r) - 32) * (Double(r) - 32) + (Double(c) - 32) * (Double(c) - 32)).squareRoot()
            return d < 2 ? 1e6 : (abs(d - 20) < 1.5 ? 1e3 : 10)
        }
        XCTAssertTrue(QuickLookRendering.stretch(for: pattern).logScale)
        let grey = QuickLookRendering.grayscale(pattern)
        XCTAssertEqual(grey[32 * 64 + 32], 255)
        let ring = grey[32 * 64 + 52]
        XCTAssertGreaterThan(ring, 100, "a 1e3 ring under a 1e6 centre is visible in log scale (linear would be 0)")
        XCTAssertEqual(grey[0], 0)
    }

    func testASpectrumIsATraceDrawnTwoToOne() throws {
        let spectrum = frame(200, 1, kind: .spectrum) { _, c in c == 100 ? 50 : 1 }
        let size = QuickLookRendering.fittedSize(for: spectrum, within: CGSize(width: 400, height: 400))
        XCTAssertEqual(size, CGSize(width: 400, height: 200))
        let image = try XCTUnwrap(QuickLookRendering.image(for: spectrum, within: CGSize(width: 400, height: 400)))
        XCTAssertEqual(image.width, 400); XCTAssertEqual(image.height, 200)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertGreaterThan(data.filter { $0 > 128 }.count, 100, "the trace is bright")
        XCTAssertGreaterThan(data.filter { $0 == 0 }.count, 10_000, "on a black ground")
    }

    func testTheFitIsTheLargestSizeWithTheFramesAspect() {
        let wide = frame(40, 10) { _, _ in 1 }
        XCTAssertEqual(QuickLookRendering.fittedSize(for: wide, within: CGSize(width: 100, height: 100)), CGSize(width: 100, height: 25))
        XCTAssertEqual(QuickLookRendering.fittedSize(for: wide, within: CGSize(width: 0, height: 100)), .zero)
    }

    func testTheCardListsWhatTheFileSaysAndNothingElse() {
        let fourD = Peek.Summary(format: "py4DSTEM HDF5", signalType: "electron_diffraction", width: 64, height: 48, scanWidth: 310, scanHeight: 205,
                                 pixelSize: 0.5, pixelUnit: "nm", detectorPixelSize: 0.0457, detectorPixelUnit: "A^-1", dataType: "float32")
        let rows = QuickLookCardContent.rows(for: fourD)
        XCTAssertEqual(rows.map(\.label), ["Format", "Signal", "Scan", "Detector", "Scan step", "Detector step", "Data type"])
        XCTAssertEqual(rows.first { $0.label == "Scan" }?.value, "310 \u{00D7} 205 positions")
        XCTAssertEqual(rows.first { $0.label == "Detector" }?.value, "64 \u{00D7} 48 px")
        XCTAssertEqual(rows.first { $0.label == "Detector step" }?.value, "0.0457 A^-1")
        let image = Peek.Summary(format: "Velox EMD", title: "HAADF", width: 215, height: 926, pixelSize: 1.26953125, pixelUnit: "nm",
                                 acquired: "2026-04-20 14:56:03", detector: "HAADF", highTensionKV: 200, cameraLengthMM: 125, magnification: 94000)
        let imageRows = QuickLookCardContent.rows(for: image)
        XCTAssertEqual(imageRows.first { $0.label == "Size" }?.value, "215 \u{00D7} 926 px")
        XCTAssertEqual(imageRows.first { $0.label == "Pixel size" }?.value, "1.2695 nm")
        XCTAssertEqual(imageRows.first { $0.label == "Voltage" }?.value, "200 kV")
        XCTAssertEqual(imageRows.first { $0.label == "Camera length" }?.value, "125 mm")
        XCTAssertEqual(imageRows.first { $0.label == "Magnification" }?.value, "94000\u{00D7}")
        XCTAssertNil(imageRows.first { $0.label == "Scan" })
        XCTAssertEqual(QuickLookCardContent.rows(for: Peek.Summary(format: "TIFF", width: 5, height: 3)).map(\.label), ["Format", "Size"])
    }

    @MainActor func testTheCardRendersToAPNGOfTheStatedSize() throws {
        let summary = Peek.Summary(format: "py4DSTEM HDF5", width: 64, height: 64, scanWidth: 20, scanHeight: 10, pixelSize: 2, pixelUnit: "nm", dataType: "float32")
        let pattern = frame(64, 64, kind: .diffractionPattern) { r, c in
            let d = ((Double(r) - 32) * (Double(r) - 32) + (Double(c) - 32) * (Double(c) - 32)).squareRoot()
            return d < 2 ? 1e5 : (abs(d - 18) < 1.5 ? 400 : 5)
        }
        let data = try XCTUnwrap(QuickLookCard.pngData(summary: summary, frame: pattern, fileName: "demo.h5"))
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1520); XCTAssertEqual(image.height, 800)
        // For the taste check: EMSUITEUI_QL_PNG_DIR names a folder the card is also written to.
        if let dir = ProcessInfo.processInfo.environment["EMSUITEUI_QL_PNG_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("quicklook-card-planted.png"))
        }
        let none = try XCTUnwrap(QuickLookCard.pngData(summary: summary, frame: nil, fileName: "demo.h5"), "a card without an image still renders")
        XCTAssertFalse(none.isEmpty)
    }

    // MARK: The scale bar (new in EMSuiteUI#225)

    func testAnImageGetsANiceBarFromItsPixelSize() throws {
        let summary = Peek.Summary(format: "TIFF", width: 512, height: 512, pixelSize: 0.5, pixelUnit: "nm")
        let plan = try XCTUnwrap(QuickLookScaleBar.plan(summary: summary, frame: frame(512, 512) { _, _ in 1 }))
        // T = min(70, 512 / 4) = 70 px; 0.5 nm x 70 = 35 nm rounds to 50 nm (1-2-5), drawn 100 px.
        XCTAssertEqual(plan.label, "50 nm")
        XCTAssertEqual(plan.lengthPixels, 100, accuracy: 1e-12)
    }

    func testADecimatedFrameCountsEachPixelAsItsStride() throws {
        let summary = Peek.Summary(format: "Velox EMD", width: 1024, height: 1024, pixelSize: 0.5, pixelUnit: "nm")
        let decimated = Peek.Frame(width: 256, height: 256, pixels: [Float](repeating: 1, count: 256 * 256), sourceWidth: 1024,
                                   sourceHeight: 1024, stride: 4, kind: .image, enteredAt: [], source: "planted")
        XCTAssertEqual(QuickLookScaleBar.calibration(summary: summary, frame: decimated)?.scale, 2)
        let plan = try XCTUnwrap(QuickLookScaleBar.plan(summary: summary, frame: decimated))
        // T = min(70, 256 / 4) = 64 px of 2 nm = 128 nm, rounded to 100 nm, drawn 50 px.
        XCTAssertEqual(plan.label, "100 nm")
        XCTAssertEqual(plan.lengthPixels, 50, accuracy: 1e-12)
    }

    func testAFourDPatternTakesTheDetectorStepNotTheScanStep() throws {
        let summary = Peek.Summary(format: "py4DSTEM HDF5", width: 128, height: 128, scanWidth: 20, scanHeight: 10, pixelSize: 2,
                                   pixelUnit: "nm", detectorPixelSize: 0.02, detectorPixelUnit: "1/nm")
        let pattern = frame(128, 128, kind: .diffractionPattern) { _, _ in 1 }
        XCTAssertEqual(QuickLookScaleBar.calibration(summary: summary, frame: pattern)?.scale, 0.02)
        let plan = try XCTUnwrap(QuickLookScaleBar.plan(summary: summary, frame: pattern))
        // T = min(70, 32) = 32 px of 0.02 = 0.64, rounded to 0.5, drawn 25 px.
        XCTAssertEqual(plan.value, 0.5)
        XCTAssertEqual(plan.lengthPixels, 25, accuracy: 1e-12)
        XCTAssertTrue(plan.label.hasPrefix("0.5 "))
        let virtual = frame(20, 10, kind: .virtualImage) { _, _ in 1 }
        XCTAssertEqual(QuickLookScaleBar.calibration(summary: summary, frame: virtual)?.scale, 2, "a virtual image takes the scan step")
    }

    func testNoBarWithoutACalibrationOrForASpectrum() {
        let image = frame(64, 64) { _, _ in 1 }
        XCTAssertNil(QuickLookScaleBar.plan(summary: Peek.Summary(format: "TIFF", width: 64, height: 64), frame: image))
        XCTAssertNil(QuickLookScaleBar.plan(summary: Peek.Summary(format: "TIFF", width: 64, height: 64, pixelSize: 1, pixelUnit: "px"),
                                            frame: image), "pixels are no calibration")
        XCTAssertNil(QuickLookScaleBar.plan(summary: Peek.Summary(format: "TIFF", width: 64, height: 64, pixelSize: .nan, pixelUnit: "nm"),
                                            frame: image))
        let spectrum = frame(200, 1, kind: .spectrum) { _, c in Float(c) }
        XCTAssertNil(QuickLookScaleBar.plan(summary: Peek.Summary(format: "MSA", width: 200, height: 1, pixelSize: 5, pixelUnit: "eV"),
                                            frame: spectrum))
    }

    @MainActor func testTheCardWithABarRendersAtTheSameSize() throws {
        let summary = Peek.Summary(format: "TIFF", width: 300, height: 150, pixelSize: 0.25, pixelUnit: "nm")
        let wide = frame(300, 150) { r, c in Float(r + c) }
        XCTAssertNotNil(QuickLookScaleBar.plan(summary: summary, frame: wide))
        let data = try XCTUnwrap(QuickLookCard.pngData(summary: summary, frame: wide, fileName: "wide.tif"))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1520); XCTAssertEqual(image.height, 800)
        if let dir = ProcessInfo.processInfo.environment["EMSUITEUI_QL_PNG_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("quicklook-card-scale-bar.png"))
        }
    }
}
