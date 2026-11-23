//
//  CrystalSnapshot.swift
//  Role: the crystal view as a picture, with no window: RealityRenderer draws the same entity tree into a texture. Copy Image uses
//        it, and so do the light and dark snapshot tests on a runner with a Metal device. Returns nil where there is no Metal device.
//

import CoreGraphics
import Metal
import RealityKit
import simd

/// Renders a CrystalScene to an image.
public enum CrystalSnapshot {
    /// The picture of `scene` seen with `orientation`, `pixels` wide and high, on the stage colour.
    public static func image(_ scene: CrystalScene, orientation: simd_double3x3, showsUnitCell: Bool = true,
                             pixels: Int = 1024) async -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice(), pixels > 0 else { return nil }
        do {
            let built = try CrystalEntities.build(scene, showsUnitCell: showsUnitCell, increasedContrast: false)
            let r = CrystalTurn.viewRotation(orientation)
            let m = simd_float3x3(columns: (SIMD3<Float>(r.columns.0), SIMD3<Float>(r.columns.1), SIMD3<Float>(r.columns.2)))
            built.pivot.orientation = simd_normalize(simd_quatf(m))

            let renderer = try RealityRenderer()
            renderer.entities.append(built.root)
            let camera = CrystalEntities.camera(radius: built.radius, aspect: 1)
            renderer.entities.append(camera)
            renderer.activeCamera = camera
            let s = CrystalPalette.stage
            renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: s.x, green: s.y, blue: s.z, alpha: 1))

            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: pixels, height: pixels, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: d) else { return nil }
            let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
            // A few frames, so meshes and materials are resident before the one that is kept.
            for _ in 0..<4 {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    do { try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in c.resume() }) }
                    catch { c.resume(throwing: error) }
                }
            }
            return cgImage(texture, pixels: pixels)
        } catch {
            return nil
        }
    }

    private static func cgImage(_ texture: any MTLTexture, pixels: Int) -> CGImage? {
        let rowBytes = pixels * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * pixels)
        texture.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: space,
                       bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
