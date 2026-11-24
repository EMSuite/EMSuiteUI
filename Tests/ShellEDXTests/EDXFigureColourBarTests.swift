//
//  EDXFigureColourBarTests.swift
//  A figure cell with a colour bar draws it under its picture: the ramp it was given, between the two end values (Electron-Microscopy-Studio#861,
//  the EELS t/λ and t maps). A cell without one draws none, as before. Rendered offscreen.
//

import XCTest
import SwiftUI
@testable import ShellEDXModel
@testable import ShellSpectroscopy

nonisolated final class EDXFigureColourBarTests: XCTestCase {

    /// A 4 × 4 grey picture, so the only green in the figure is the bar's.
    @MainActor private func cell(bar: EDXFigureColourBar?) -> EDXFigureCell {
        EDXFigureCell(id: "tOverLambda", title: "t/λ", detail: "", rgba: [UInt8](repeating: 128, count: 4 * 4 * 4), width: 4, height: 4, footer: nil,
                      colourBar: bar)
    }

    @MainActor private func figure(_ cell: EDXFigureCell) -> EDXFigureContent {
        EDXFigureContent(title: "planted.dm4", subtitle: "Whole map", tiles: [], region: .wholeMap, nx: 4, ny: 4, bar: nil, cells: [cell])
    }

    /// The rendered image's pixels that are green (red and blue under 0.1, green over 0.9).
    private func greenPixels(_ image: CGImage) throws -> Int {
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var count = 0
        for i in stride(from: 0, to: px.count, by: 4) where px[i] < 26 && px[i + 1] > 230 && px[i + 2] < 26 { count += 1 }
        return count
    }

    /// Black to green, 256 entries: the bar's high end is the only green in the figure. Red under: a cell's bar not drawn (before #861).
    @MainActor func testACellDrawsItsColourBarUnderItsPicture() throws {
        let ramp = (0..<256).flatMap { [UInt8(0), UInt8($0), UInt8(0), UInt8(255)] }
        let bar = EDXFigureColourBar(rgba: ramp, width: 256, low: "0.21", high: "0.85 t/λ")
        let without = try XCTUnwrap(EDXMapsFigure.cgImage(figure(cell(bar: nil))))
        let with = try XCTUnwrap(EDXMapsFigure.cgImage(figure(cell(bar: bar))))
        XCTAssertEqual(try greenPixels(without), 0, "precondition: no green without the bar")
        XCTAssertGreaterThan(try greenPixels(with), 0, "the bar's green end is drawn")
        XCTAssertGreaterThan(with.height, without.height, "the bar takes a line under the picture")
    }
}
