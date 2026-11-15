//
//  MetalColorSpaceTests.swift
//  The Metal picture's layer is tagged sRGB, as the colormap swatches are, so on a P3 display a colour in the picture is the colour
//  of its swatch (macEMSuite/MacEMUI#129). Red under: the tag dropped, or a different space than the swatch's.
//

import CoreGraphics
import QuartzCore
import XCTest
@testable import ShellMetal

nonisolated final class MetalColorSpaceTests: XCTestCase {

    @MainActor func testThePictureLayerIsTaggedAsTheSwatchesAre() {
        let layer = CAMetalLayer()
        XCTAssertNil(layer.colorspace, "a new layer is untagged: the test sees the tag being set")
        MetalImageView.tagColorSpace(layer)
        XCTAssertEqual(layer.colorspace?.name, CGColorSpace.sRGB)
        let swatch = Colormaps.swatchCGImage(.viridis)
        XCTAssertEqual(swatch.colorSpace?.name, layer.colorspace?.name, "the picture and its swatch share one space")
    }
}
