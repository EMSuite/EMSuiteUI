import AppKit
import ImageIO
import Metal
import RealityKit
import UniformTypeIdentifiers

/// The still mode: RealityRenderer into a texture, no window. Proves thumbnails and snapshot pictures need no screen.
@MainActor
enum SpikeOffscreen {
    static func render(_ built: SpikeStage.Built, rotation: simd_quatf, cameraScale: Float, size: Int, background: CGColor, to url: URL) async throws -> Double {
        let t0 = Date()
        let renderer = try RealityRenderer()
        let root = built.root.clone(recursive: true)
        if let pivot = root.children.first { pivot.orientation = rotation }
        renderer.entities.append(root)
        let cam = SpikeStage.camera(scale: cameraScale)
        renderer.entities.append(cam)
        renderer.activeCamera = cam
        renderer.cameraSettings.colorBackground = .color(background)
        renderer.cameraSettings.antialiasing = .multisample4X

        guard let device = MTLCreateSystemDefaultDevice() else { throw SpikeError.noMetal }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: size, height: size, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { throw SpikeError.noTexture }
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: tex))
        // A few frames, so meshes and materials are resident before the one we keep.
        for _ in 0..<4 {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in c.resume() })
                } catch { c.resume(throwing: error) }
            }
        }
        let rowBytes = size * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * size)
        tex.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw SpikeError.noImage }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return Date().timeIntervalSince(t0)
    }
}

enum SpikeError: Error { case noMetal, noTexture, noImage }
