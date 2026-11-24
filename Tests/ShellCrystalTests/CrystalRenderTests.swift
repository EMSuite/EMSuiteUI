import CoreGraphics
import ImageIO
import Metal
import simd
import XCTest
@testable import ShellCrystal

/// The atom mesh and batching (no GPU), and one rendered picture on a machine with a Metal device.
nonisolated final class CrystalRenderTests: XCTestCase {

    /// The icosphere: 1 280 triangles at 3 subdivisions, every vertex on the unit sphere, every triangle wound outwards
    /// (counter-clockwise seen from outside), so no atom is culled as a back face.
    func testIcosphereIsClosedAndWoundOutwards() {
        let sphere = CrystalMesh.icosphere(subdivisions: CrystalMesh.atomSubdivisions)
        XCTAssertEqual(sphere.triangles.count / 3, 1280)
        XCTAssertEqual(sphere.vertices.count, 642)
        for v in sphere.vertices { XCTAssertEqual(simd_length(v), 1, accuracy: 1e-5) }
        for t in stride(from: 0, to: sphere.triangles.count, by: 3) {
            let a = sphere.vertices[Int(sphere.triangles[t])], b = sphere.vertices[Int(sphere.triangles[t + 1])]
            let c = sphere.vertices[Int(sphere.triangles[t + 2])]
            XCTAssertGreaterThan(simd_dot(simd_cross(b - a, c - a), a + b + c), 0)
        }
        // closed: every edge is shared by exactly two triangles
        var edges: [SIMD2<UInt32>: Int] = [:]
        for t in stride(from: 0, to: sphere.triangles.count, by: 3) {
            let i = Array(sphere.triangles[t..<t + 3])
            for (p, q) in [(i[0], i[1]), (i[1], i[2]), (i[2], i[0])] { edges[SIMD2(min(p, q), max(p, q)), default: 0] += 1 }
        }
        XCTAssertTrue(edges.values.allSatisfy { $0 == 2 })
    }

    /// Batches stay under the triangle limit MU0 measured and cover every instance once.
    func testBatchesStayUnderTheTriangleLimit() {
        let ranges = CrystalMesh.batches(count: 23_171, trianglesPerInstance: 1280)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, 23_171)
        for (r, next) in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(r.upperBound, next.lowerBound) }
        for r in ranges { XCTAssertLessThanOrEqual(r.count * 1280, CrystalMesh.maxTrianglesPerBatch) }
        XCTAssertEqual(CrystalMesh.batches(count: 0, trianglesPerInstance: 1280), [])
        XCTAssertEqual(CrystalMesh.batches(count: 5, trianglesPerInstance: 10_000_000), [0..<1, 1..<2, 2..<3, 3..<4, 4..<5])
    }

    /// The parallel camera frames the scene's sphere on the pane's shorter side (scale is the half-height, MU0).
    func testCameraFramesTheShorterSide() {
        XCTAssertEqual(CrystalEntities.orthographicScale(radius: 1, aspect: 2), 1.08, accuracy: 1e-6)
        XCTAssertEqual(CrystalEntities.orthographicScale(radius: 1, aspect: 0.5), 2.16, accuracy: 1e-6)
    }

    /// Si down [110] renders: the picture is not empty stage, and its atoms carry silicon's colour (an inside-out mesh or a
    /// missing light would leave the stage or black).
    func testSiliconRendersOnTheStage() async throws {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let scene = CrystalGeometryTests.silicon()
        let orientation = CrystalTurn.lookingDown(scene.cell! * [1, 1, 0], up: scene.cell! * [0, 0, 1])
        let rendered = await CrystalSnapshot.image(scene, orientation: orientation, pixels: 256)
        let image = try XCTUnwrap(rendered)
        let pixels = Self.rgb(image)
        let stage = CrystalPalette.stage * 255
        let lit = pixels.filter { simd_length($0 - stage) > 40 }
        XCTAssertGreaterThan(Double(lit.count) / Double(pixels.count), 0.08, "atoms cover part of the pane")
        let si = CrystalPalette.color(z: 14) * 255
        let near = lit.filter { simd_length($0 - si) < 70 }
        XCTAssertGreaterThan(near.count, lit.count / 10, "lit atoms show silicon's colour")
        if let dir = ProcessInfo.processInfo.environment["CRYSTAL_SNAPSHOT_DIR"] { Self.write(image, to: dir + "/si-110.png") }
    }

    static func rgb(_ image: CGImage) -> [SIMD3<Double>] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 0, to: bytes.count, by: 4).map { SIMD3(Double(bytes[$0]), Double(bytes[$0 + 1]), Double(bytes[$0 + 2])) }
    }

    static func write(_ image: CGImage, to path: String) {
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
