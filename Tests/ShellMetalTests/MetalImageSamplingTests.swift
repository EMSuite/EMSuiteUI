//
//  MetalImageSamplingTests.swift
//  A coarse simulated scan can be drawn smooth (`MetalImageView.Sampling.linear`): the shader blends the four pixel values
//  around a magnified pane pixel before the window and colormap, clamped at the edges. The default stays the nearest read,
//  unchanged, for recorded data. Red before: no `sampling`, and `display.w` was unused, so every image drew as blocks.
//

import XCTest
import Metal
@testable import ShellMetal

nonisolated final class MetalImageSamplingTests: XCTestCase {

    @MainActor func testTheDefaultIsNearestAndAChangeRedraws() {
        let view = MetalImageView(pixels: [0, 1], width: 2, height: 1, contentVersion: 7)
        let sampling: MetalImageView.Sampling = view.sampling
        XCTAssertEqual(sampling, .nearest)
        XCTAssertEqual(view.appliedState.sampling, .nearest)
        let smooth = view.sampling(.linear)
        XCTAssertEqual(smooth.appliedState.sampling, .linear)
        XCTAssertNotEqual(view.appliedState, smooth.appliedState, "a sampling-only change redraws")
        XCTAssertEqual(MetalImageView(pixels: [0, 1], width: 2, height: 1, contentVersion: 7, sampling: .linear).appliedState,
                       smooth.appliedState)
    }

    func testTheSamplingRidesInTheDisplayParametersSpareLane() {
        typealias C = MetalImageView.Coordinator
        XCTAssertEqual(C.displayParameters(range: SIMD2<Float>(0.1, 0.9), gamma: 2, sampling: .nearest),
                       SIMD4<Float>(0.1, 0.9, 2, 0), "the nearest default binds what was bound before")
        XCTAssertEqual(C.displayParameters(range: SIMD2<Float>(0.1, 0.9), gamma: 2, sampling: .linear),
                       SIMD4<Float>(0.1, 0.9, 2, 1))
    }

    /// A 4 × 2 image, so every uv below is exact in Float32.
    private static let pixels: [Float] = [0.0, 0.2, 0.4, 0.8,
                                          1.0, 0.6, 0.3, 0.1]

    private static func uv(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2<Float>(x / 4, y / 2) }

    func testAPixelCentreReadsThatPixel() throws {
        for y in 0..<2 {
            for x in 0..<4 {
                let at = Self.uv(Float(x) + 0.5, Float(y) + 0.5)
                let taps = MetalImageView.linearTaps(uv: at, width: 4, height: 2)
                XCTAssertEqual(taps.wx, 0)
                XCTAssertEqual(taps.wy, 0)
                XCTAssertEqual(try XCTUnwrap(MetalImageView.linearSample(Self.pixels, width: 4, height: 2, uv: at)),
                               Self.pixels[y * 4 + x], "pixel (\(x), \(y))")
            }
        }
    }

    func testMidwayBetweenTwoCentresReadsTheirMean() throws {
        let across = try XCTUnwrap(MetalImageView.linearSample(Self.pixels, width: 4, height: 2, uv: Self.uv(2, 0.5)))
        XCTAssertEqual(across, (0.2 + 0.4) / 2, accuracy: 1e-6)
        let down = try XCTUnwrap(MetalImageView.linearSample(Self.pixels, width: 4, height: 2, uv: Self.uv(0.5, 1)))
        XCTAssertEqual(down, (0.0 + 1.0) / 2, accuracy: 1e-6)
        let corner = try XCTUnwrap(MetalImageView.linearSample(Self.pixels, width: 4, height: 2, uv: Self.uv(1, 1)))
        XCTAssertEqual(corner, (0.0 + 0.2 + 1.0 + 0.6) / 4, accuracy: 1e-6)
    }

    func testTheEdgesClampToTheEdgePixels() throws {
        let topLeft = MetalImageView.linearTaps(uv: SIMD2<Float>(0, 0), width: 4, height: 2)
        XCTAssertEqual(topLeft, MetalImageView.LinearTaps(x0: 0, x1: 0, y0: 0, y1: 0, wx: 0.5, wy: 0.5))
        let bottomRight = MetalImageView.linearTaps(uv: SIMD2<Float>(1, 1), width: 4, height: 2)
        XCTAssertEqual(bottomRight, MetalImageView.LinearTaps(x0: 3, x1: 3, y0: 1, y1: 1, wx: 0.5, wy: 0.5))
        XCTAssertEqual(MetalImageView.linearSample(Self.pixels, width: 4, height: 2, uv: SIMD2<Float>(0, 0)), 0.0,
                       "no dark border: the corner is the corner pixel")
        XCTAssertEqual(MetalImageView.linearSample(Self.pixels, width: 4, height: 2, uv: SIMD2<Float>(1, 1)), 0.1)
        XCTAssertEqual(MetalImageView.linearSample(Self.pixels, width: 4, height: 2, uv: SIMD2<Float>(-3, 7)), 1.0,
                       "outside the image clamps like the nearest read")
        XCTAssertEqual(MetalImageView.linearSample([0.7], width: 1, height: 1, uv: SIMD2<Float>(0.3, 0.9)), 0.7)
    }

    /// Midway between a valid pixel and a masked (negative), NaN or infinite one there is no value to blend: nil, where the
    /// shader reads the nearest pixel.
    func testAMaskedOrNonFiniteNeighbourIsNotBlended() {
        let midway = SIMD2<Float>(0.5, 0.5)
        for other: Float in [-1, .nan, .infinity] {
            XCTAssertNil(MetalImageView.linearSample([0.5, other], width: 2, height: 1, uv: midway), "\(other)")
        }
        XCTAssertEqual(MetalImageView.linearSample([0.5, 0.25], width: 2, height: 1, uv: midway), 0.375)
    }

    /// The shader's nearest read is the one it had, and the linear read is taken only on `display.w == 1`, magnified or 1:1.
    func testTheShaderKeepsItsNearestReadAndGatesTheLinearOne() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShellMetal/Resources/Colormaps.metal")
        let text = try String(contentsOf: file, encoding: .utf8)
        let nearest = try XCTUnwrap(text.components(separatedBy: "static inline float3 scalarColor(").last?
            .components(separatedBy: "static inline bool unblendable").first)
        XCTAssertTrue(nearest.contains("uint x = min(uint(clamp(uv.x, 0.0, 1.0) * float(size.x)), size.x - 1);"))
        XCTAssertTrue(nearest.contains("uint y = min(uint(clamp(uv.y, 0.0, 1.0) * float(size.y)), size.y - 1);"))
        XCTAssertFalse(nearest.contains("display.w"), "the nearest read does not look at the sampling")
        let fragment = try XCTUnwrap(text.components(separatedBy: "fragment float4 colormapFragment(").last?
            .components(separatedBy: "fragment float4 rgbaFragment(").first)
        XCTAssertTrue(fragment.contains("""
                if (n == 1) {
                    if (display.w == 1.0) {
                        return float4(linearScalarColor(in.uv, display, img, size, image, transfer, lut), 1.0);
                    }
                    return float4(scalarColor(in.uv, display, img, size, image, transfer, lut), 1.0);
                }
            """), fragment)
        XCTAssertEqual(fragment.components(separatedBy: "linearScalarColor(").count, 2, "one linear read, behind the gate")
        XCTAssertTrue(fragment.contains("sum += scalarColor("), "zoomed out, the footprint average reads nearest")
        let linear = try XCTUnwrap(text.components(separatedBy: "static inline float3 linearScalarColor(").last?
            .components(separatedBy: "fragment float4 colormapFragment(").first)
        XCTAssertTrue(linear.contains("* float2(size) - 0.5;"))
        XCTAssertTrue(linear.contains("float2 cell = floor(p);"))
        XCTAssertTrue(linear.contains("return scalarColor(uv, display, img, size, image, transfer, lut);"),
                      "a masked neighbour falls back to the nearest read")
    }

    /// On the GPU: a 2 × 1 image of 0 and 1 drawn into 4 × 1 pixels. Nearest is two black and two white pixels; linear is the
    /// `linearSample` values (0, 0.25, 0.75, 1) through the gray LUT, as `Colormaps.sampleRGB` samples it. A masked pixel draws
    /// the same in both.
    @MainActor func testTheShaderBlendsAsTheReferenceDoes() throws {
        let engine = try XCTUnwrap(MetalEngine.available, "no Metal on this machine")
        let lutBytes = Colormaps.lutRGBA(.gray, count: 256)
        let lut = try XCTUnwrap(engine.device.makeLUTTexture(rgba: lutBytes))
        func draw(_ pixels: [Float], _ sampling: MetalImageView.Sampling) throws -> [UInt8] {
            let data = try XCTUnwrap(engine.device.makeImageBuffer(pixels: pixels, width: 2, height: 1))
            return try Self.render(engine, width: 4, height: 1) { encoder in
                var display = MetalImageView.Coordinator.displayParameters(range: SIMD2<Float>(0, 1), gamma: 1, sampling: sampling)
                encoder.setFragmentBytes(&display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setFragmentBuffer(data, offset: 0, index: 1)
                var size = SIMD2<UInt32>(2, 1)
                encoder.setFragmentBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 2)
                var parameters = DisplayImage(buffer: data, width: 2, height: 1, encoding: .normalizedFloat, low: 0, span: 1).parameters
                encoder.setFragmentBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
                var transfer = SIMD4<Float>(0, 0, 1, 0)
                encoder.setFragmentBytes(&transfer, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
                encoder.setFragmentTexture(lut, index: 1)
            }
        }
        XCTAssertEqual(try draw([0, 1], .nearest), [0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255])
        let smooth = try draw([0, 1], .linear)
        for x in 0..<4 {
            let v = try XCTUnwrap(MetalImageView.linearSample([0, 1], width: 2, height: 1,
                                                              uv: SIMD2<Float>((Float(x) + 0.5) / 4, 0.5)))
            let (r, g, b) = Colormaps.sampleRGB(lutBytes, Double(v))
            for (channel, want) in zip(smooth[x * 4..<x * 4 + 3], [b, g, r]) {
                XCTAssertLessThanOrEqual(abs(Int(channel) - Int(want)), 1, "pixel \(x): \(Array(smooth[x * 4..<x * 4 + 4])) for \(v)")
            }
            XCTAssertEqual(smooth[x * 4 + 3], 255)
        }
        XCTAssertNotEqual(smooth[4..<8], smooth[8..<12], "the middle pixels are blended, not one block")
        XCTAssertEqual(try draw([0.5, -1], .linear), try draw([0.5, -1], .nearest), "a masked pixel keeps its edge")
    }

    /// One frame of the scalar pipeline into a `width` × `height` BGRA8 target through the identity transform, read back.
    private static func render(_ engine: MetalEngine, width: Int, height: Int,
                               bind: (MTLRenderCommandEncoder) -> Void) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let target = try XCTUnwrap(engine.device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        let buffer = try XCTUnwrap(engine.queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(buffer.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(engine.displayPSO)
        let identity = MetalDisplayTransform.identity(CGSize(width: width, height: height)).shaderRows()
        var rows = [identity.0, identity.1]
        encoder.setVertexBytes(&rows, length: 2 * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        bind(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        XCTAssertEqual(buffer.status, .completed, "\(String(describing: buffer.error))")
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return out
    }
}
