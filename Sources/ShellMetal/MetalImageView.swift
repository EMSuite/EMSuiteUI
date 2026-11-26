import SwiftUI
import MetalKit

/// The one SwiftUI to Metal bridge in UI: a single-channel image already
/// normalised to [0, 1], drawn through `MetalEngine`'s display pipeline
/// (fullscreen triangle + colormap LUT), or packed RGBA8 bytes drawn
/// through the RGBA pipeline.
///
/// **Contract**
/// - `pixels` is already normalised (`FloatImage.normalized` /
///   `DiffractionPattern.normalized`). Masked pixels are the negative
///   `FloatImage.invalidDisplayValue` sentinel and render as neutral gray.
///   With `pixelScale: .raw(range:)` they are the raw values instead, normalised by the view on upload (a large image then
///   needs no full-size normalised copy, macTEM#562).
/// - `contentVersion` MUST change whenever `pixels` or `rgba` changes: the
///   coordinator re-uploads the texture only on a version change, which is
///   what keeps zooming and panning free. Passing a literal `0` here is the
///   defect that froze a comparison panel on the previous product's pixels.
///
/// **Why it is still a platform representable.** Everything else in UI is
/// plain SwiftUI, but there is no SwiftUI view that samples a float texture
/// through a LUT with a display window and gamma in the fragment shader, and
/// the alternative — rasterising to a `CGImage` per frame — would cost the
/// interactive contrast, gamma and colormap the science depends on. The
/// wrapper is deliberately shaped for both platforms: the shared body is
/// `makeMetalView`/`updateMetalView`, and only the two-line platform
/// conformance differs, so an iOS target needs no rewrite.
///
/// A zoomed pane does NOT scale this view with SwiftUI's `scaleEffect`: that
/// raised the hosted layer's scale and the drawable followed it (914² at 1×,
/// 14656² at 16× on a 458 pt pane, 1.3 GB resident, measured 2026-10-12). The
/// view stays pane-sized and untransformed behind the overlay layer, and the
/// vertex shader draws the image through one `MetalDisplayTransform` that
/// inverts the same zoom, offset, rotation and mirroring SwiftUI applies to
/// the overlays. `nil` means the whole image over the view's own bounds.
// AppKit: an NSViewRepresentable over MTKView, because no SwiftUI view samples a float texture through a LUT with window and gamma in the fragment shader (see Why above).
public struct MetalImageView {
    /// A version derived from the pixel VALUES and the dimensions. O(n)
    /// FNV-1a — call it where the pixels are produced, once per image, never
    /// inside a `body`. Dimensions are folded in because the coordinator
    /// short-circuits on the version before it looks at width and height, so
    /// identical pixels at transposed dimensions must still re-upload.
    public nonisolated static func contentVersion(
        of pixels: [Float], width: Int, height: Int
    ) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        hash = (hash ^ UInt64(truncatingIfNeeded: width)) &* 0x0000_0100_0000_01b3
        hash = (hash ^ UInt64(truncatingIfNeeded: height)) &* 0x0000_0100_0000_01b3
        for value in pixels {
            hash = (hash ^ UInt64(value.bitPattern)) &* 0x0000_0100_0000_01b3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    /// Folds packed RGBA bytes into a scalar version. An RGBA payload carries
    /// an all-zero `pixels` array, so hashing the pixels alone gives every
    /// same-sized RGBA product the same version — an IPF map and a DPC colour
    /// wheel of equal size would be indistinguishable and one would keep the
    /// other's texture.
    public nonisolated static func contentVersion(
        of pixels: [Float], rgba: [UInt8]?, width: Int, height: Int
    ) -> Int {
        let base = contentVersion(of: pixels, width: width, height: height)
        guard let rgba else { return base }
        return rgba.withUnsafeBytes { bytes -> Int in
            var hash = UInt64(bitPattern: Int64(base))
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
            return Int(bitPattern: UInt(truncatingIfNeeded: hash))
        }
    }

    public var pixels: [Float]          // normalised [0, 1], row-major (or raw, `pixelScale`)
    /// What `pixels` hold: normalised display values (the default), or the raw values with their finite range, which the view
    /// normalises itself on the GPU side (`MTLDevice.makeDisplayImage`: whole numbers stay one or two bytes a pixel), so the caller keeps no
    /// full-size normalised copy beside its raw pixels. The buffer is the same either way.
    public var pixelScale: PixelScale = .normalized

    public nonisolated enum PixelScale: Equatable, Sendable {
        case normalized
        /// Raw values and their finite range (nil: no finite value, every pixel drawn masked).
        case raw(range: ClosedRange<Float>?)
    }

    /// Raw pixels kept at their own bit depth, drawn instead of `pixels` with `pixelScale: .raw(range:)` (the range of these
    /// values): an 8-bit image is one byte a pixel in the app and on the GPU, as ImageJ, GMS and Velox keep it (macTEM#566).
    public var nativePixels: NativePixels?

    /// How the shader maps a raw value to the colormap before the window and gamma. Applies to raw pixels
    /// (`pixelScale: .raw(range:)`); normalised pixels are drawn as they are.
    public var transfer: DisplayTransfer

    public nonisolated enum DisplayTransfer: Equatable, Sendable {
        /// The value over the raw range, as it is.
        case linear
        /// log10(1 + max(v, 0)) of the raw value, over the same of the raw range: a diffraction pattern's decades, drawn
        /// from the file's own pixels with no log copy of them (ImagoKit's `DisplayNormalization.normalizedLog`; macEM#580).
        case log
    }

    public nonisolated enum NativePixels: Sendable {
        case uint8([UInt8])
        case uint16([UInt16])

        var count: Int {
            switch self {
            case .uint8(let values): values.count
            case .uint16(let values): values.count
            }
        }
    }
    public var width: Int
    public var height: Int
    public var contentVersion: Int
    public var colormap: ColormapKind
    /// When set, these packed RGBA8 bytes (width x height x 4) are drawn
    /// instead of `pixels` + colormap.
    public var rgba: [UInt8]?
    /// Display contrast window in normalised [0, 1] intensity, applied in the
    /// fragment shader — cheap, per frame.
    public var displayLo: Float
    public var displayHi: Float
    public var gamma: Float
    /// Where the image sits in the pane; nil = the whole image over the view.
    public var displayTransform: MetalDisplayTransform?
    /// How a magnified pane pixel reads the image: the nearest pixel (the default, right for recorded data: a pixel is a
    /// pixel), or the values of the four around it blended. Zoomed out, the pane's footprint average is the same in both.
    public var sampling: Sampling = .nearest

    /// How the scalar image is read between pixel centres.
    ///
    /// `.linear` blends the DATA values bilinearly before the transfer, window, gamma and colormap, with pixel centres at
    /// (i + 0.5) / n and the edge pixels clamped (no wrap, no dark border), as abTEM and matplotlib show a coarse simulated
    /// scan sampled at the Nyquist step. A masked or non-finite pixel among the four is not blended: that read stays nearest,
    /// so a mask keeps its edge. Packed RGBA (`rgba`: colour wheels, composites coloured elsewhere) always draws nearest.
    /// The view cannot tell a wrapped phase, a label map or a categorical image from intensities: opt in for intensities only.
    /// A figure export draws its own `FigureRaster` nearest at its own pixels (ShellExport), not this view: it does not follow.
    public nonisolated enum Sampling: Equatable, Sendable {
        case nearest
        case linear
    }

    public func displayTransform(_ transform: MetalDisplayTransform) -> MetalImageView {
        var copy = self
        copy.displayTransform = transform
        return copy
    }

    /// This view drawing its image with `sampling` (`.linear` for a coarse simulated scan).
    public func sampling(_ sampling: Sampling) -> MetalImageView {
        var copy = self
        copy.sampling = sampling
        return copy
    }

    public init(
        pixels: [Float],
        width: Int,
        height: Int,
        contentVersion: Int,
        colormap: ColormapKind = .viridis,
        rgba: [UInt8]? = nil,
        displayLo: Float = 0,
        displayHi: Float = 1,
        gamma: Float = 1,
        pixelScale: PixelScale = .normalized,
        nativePixels: NativePixels? = nil,
        transfer: DisplayTransfer = .linear,
        sampling: Sampling = .nearest
    ) {
        self.sampling = sampling
        self.pixelScale = pixelScale
        self.nativePixels = nativePixels
        self.transfer = transfer
        self.pixels = pixels
        self.width = width
        self.height = height
        self.contentVersion = contentVersion
        self.colormap = colormap
        self.rgba = rgba
        self.displayLo = displayLo
        self.displayHi = displayHi
        self.gamma = gamma
    }

    /// Everything that decides what the pane draws, minus the pixel arrays
    /// (their `contentVersion` stands in for them). `updateMetalView` skips the
    /// redraw when this equals what the coordinator last applied, so a SwiftUI
    /// update that changed nothing the pane shows (a hover or pan tick
    /// elsewhere in the room) does not re-encode a frame.
    struct AppliedState: Equatable {
        var contentVersion: Int
        var width: Int
        var height: Int
        var colormap: ColormapKind
        var displayLo: Float
        var displayHi: Float
        /// The gamma the shader receives (`max(gamma, 0.05)`), not the raw one.
        var effectiveGamma: Float
        var hasRGBA: Bool
        var displayTransform: MetalDisplayTransform?
        /// How the pixels are scaled, and whether they came at their own bit depth: a change of either alone rebuilds the image,
        /// so it must redraw too (without them a scale-only change left the old frame up).
        var pixelScale: PixelScale
        var hasNativePixels: Bool
        /// A change of transfer redraws the same image: nothing is rebuilt.
        var transfer: DisplayTransfer
        /// So is a change of sampling.
        var sampling: Sampling
    }

    /// The state this view asks the coordinator to show.
    var appliedState: AppliedState {
        AppliedState(
            contentVersion: contentVersion, width: width, height: height,
            colormap: colormap, displayLo: displayLo, displayHi: displayHi,
            effectiveGamma: max(gamma, 0.05), hasRGBA: rgba != nil,
            displayTransform: displayTransform, pixelScale: pixelScale, hasNativePixels: nativePixels != nil,
            transfer: transfer, sampling: sampling)
    }

    /// The four pixels and the weights a linear read at image `uv` blends, as `Colormaps.metal`'s `linearScalarColor` takes
    /// them: the cell is floor(uv * n - 0.5) (pixel centres at (i + 0.5) / n), the weights its fraction, and each neighbour
    /// is clamped to [0, n - 1].
    nonisolated struct LinearTaps: Equatable, Sendable {
        var x0: Int
        var x1: Int
        var y0: Int
        var y1: Int
        var wx: Float
        var wy: Float
    }

    /// `LinearTaps` at a finite `uv` in a `width` × `height` image (both at least 1), in the shader's Float32 arithmetic.
    nonisolated static func linearTaps(uv: SIMD2<Float>, width: Int, height: Int) -> LinearTaps {
        let px = min(max(uv.x, 0), 1) * Float(width) - 0.5
        let py = min(max(uv.y, 0), 1) * Float(height) - 0.5
        let cx = px.rounded(.down), cy = py.rounded(.down)
        let ix = Int(cx), iy = Int(cy)
        return LinearTaps(x0: min(max(ix, 0), width - 1), x1: min(max(ix + 1, 0), width - 1),
                          y0: min(max(iy, 0), height - 1), y1: min(max(iy + 1, 0), height - 1),
                          wx: px - cx, wy: py - cy)
    }

    /// The display value a linear read at `uv` blends from row-major `pixels`, the shader's `linearScalarColor` before its
    /// colour; nil when a pixel among the four is masked (negative) or not finite, where the shader reads the nearest pixel.
    nonisolated static func linearSample(_ pixels: [Float], width: Int, height: Int, uv: SIMD2<Float>) -> Float? {
        let t = linearTaps(uv: uv, width: width, height: height)
        let v00 = pixels[t.y0 * width + t.x0], v10 = pixels[t.y0 * width + t.x1]
        let v01 = pixels[t.y1 * width + t.x0], v11 = pixels[t.y1 * width + t.x1]
        guard [v00, v10, v01, v11].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let top = v00 + (v10 - v00) * t.wx
        let bottom = v01 + (v11 - v01) * t.wx
        return top + (bottom - top) * t.wy
    }

    fileprivate func makeMetalView(_ coordinator: Coordinator) -> MTKView {
        // Without Metal the pane is an empty view that says so (MacEMUI#124: the engine no longer traps at start-up).
        let view = ScaleAwareMTKView(frame: .zero, device: MetalEngine.available?.device)
        if case .failure(let error) = MetalEngine.startup { view.show(.noMetal(error.localizedDescription)) }
        view.colorPixelFormat = .bgra8Unorm            // must match displayPSO
        view.clearColor = MTLClearColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        view.framebufferOnly = true
        view.layer?.isOpaque = false                    // outside the image the fragment is transparent
        view.isPaused = true                            // redraw only on demand
        view.enableSetNeedsDisplay = true
        view.delegate = coordinator
        coordinator.view = view
        // The shader samples the data texture nearest, so zoomed data pixels
        // stay crisp; this keeps the layer itself from interpolating either.
        // `.linear` sampling blends in the shader, on a drawable the pane's size, so the layer stays nearest for it too.
        view.layer?.magnificationFilter = .nearest
        Self.tagColorSpace(view.layer as? CAMetalLayer)
        return view
    }

    /// The colour space the drawn bytes are in: the colormap tables and the RGB mixes are sRGB-encoded 8-bit values, as the
    /// swatches' `CGImage` (`Colormaps.swatch`) is tagged. An untagged layer is shown in the display's own space, so on a P3
    /// display the picture and its swatch differed (MacEMUI#129).
    static let drawnColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    /// Tags `layer` with `drawnColorSpace`, so the window server converts it to the display as it does the swatches.
    static func tagColorSpace(_ layer: CAMetalLayer?) {
        layer?.colorspace = drawnColorSpace
    }

    fileprivate func updateMetalView(_ view: MTKView, _ coordinator: Coordinator) {
        coordinator.colormap = colormap
        coordinator.updateContentIfNeeded(
            pixels: pixels, rgba: rgba,
            width: width, height: height, version: contentVersion, scale: pixelScale, native: nativePixels
        )
        coordinator.displayRange = SIMD2<Float>(displayLo, displayHi)
        coordinator.gamma = max(gamma, 0.05)
        coordinator.transfer = transfer
        coordinator.sampling = sampling
        coordinator.displayTransform = displayTransform
        // Redraw only when something the pane shows changed (a size or scale
        // change redraws through `drawableSizeWillChange` and the window hooks).
        let state = appliedState
        guard coordinator.lastApplied != state else { return }
        coordinator.lastApplied = state
        view.needsDisplay = true
    }

    /// An `MTKView` that keeps its layer's `contentsScale` in step with the
    /// window it is in.
    ///
    /// Measured 2026-08-27: inside a SwiftUI sheet the hosted `MTKView`'s
    /// `CAMetalLayer` is left at `contentsScale == 0`, and a layer at scale 0
    /// cannot display a drawable — the pane stays exactly the background
    /// colour while every internal signal (drawable size, render pass,
    /// current drawable, uploaded texture) looks healthy. What writes the 0
    /// was never identified, which is why the `!=` guard matters: this must
    /// not fight whatever does the writing.
    final class ScaleAwareMTKView: MTKView {
        private func matchWindowScale() {
            guard let scale = window?.backingScaleFactor, scale > 0 else { return }
            guard layer?.contentsScale != scale else { return }
            layer?.contentsScale = scale
            needsDisplay = true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            matchWindowScale()
            // An update that arrived before the view had a window drew nothing
            // (and updates no longer redraw unconditionally), so draw on entry.
            if window != nil { needsDisplay = true }
        }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            matchWindowScale()
        }

        /// AppKit: the failure line sits inside the MTKView this representable owns, so every pane that shows an image says why
        /// it cannot, without a SwiftUI wrapper its callers would have to adopt.
        /// True once the failure line exists (it is made the first time there is something to say).
        private var hasFailureLabel = false
        private lazy var failureLabel: NSTextField = {
            hasFailureLabel = true
            let label = NSTextField(wrappingLabelWithString: "")
            label.alignment = .center
            label.textColor = .secondaryLabelColor
            label.font = .preferredFont(forTextStyle: .callout)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
            ])
            return label
        }()

        /// Shows why the pane is empty, or hides the line (nil).
        func show(_ failure: MetalImageFailure?) {
            guard failure != nil || hasFailureLabel else { return }
            failureLabel.stringValue = failure?.text ?? ""
            failureLabel.isHidden = failure == nil
            setAccessibilityLabel(failure?.text)
        }
    }

    // MARK: - Coordinator (the MTKView delegate / renderer)

    public final class Coordinator: NSObject, MTKViewDelegate {
        /// Setting the same colormap again (every SwiftUI update does) must not
        /// rebuild the LUT and allocate a new texture.
        var colormap: ColormapKind = .viridis {
            didSet { if colormap != oldValue { lutDirty = true } }
        }
        /// What the last requested redraw was for; nil until the first update
        /// and again after a draw that could not present, so the next update
        /// draws.
        var lastApplied: AppliedState?
        var displayRange = SIMD2<Float>(0, 1)
        var gamma: Float = 1
        var transfer: DisplayTransfer = .linear
        var sampling: Sampling = .nearest
        var displayTransform: MetalDisplayTransform?

        private var dataImage: DisplayImage?
        /// Counts content updates, so an image built off the main actor lands only if it is still the one asked for.
        private var generation = 0
        weak var view: MTKView?

        /// From this many pixels a raw image is packed off the main actor (the 375-megapixel SEM TIFF), and the pane draws it when it
        /// lands; smaller ones are built at once, so live panes never flicker.
        static let backgroundBuildPixels = 1 << 22
        private var rgbaTexture: MTLTexture?
        private var lutTexture: MTLTexture?
        private(set) var lutDirty = true
        private var version = Int.min
        private var scale: PixelScale = .normalized
        /// The off-main build in flight: a newer update cancels it, so superseded builds of a large image do not pile up.
        private var build: Task<Void, Never>?
        /// Why the pane shows nothing, shown on it; nil when it draws.
        private(set) var failure: MetalImageFailure? {
            didSet { if failure != oldValue { (view as? ScaleAwareMTKView)?.show(failure) } }
        }

        func updateContentIfNeeded(
            pixels: [Float], rgba: [UInt8]?, width: Int, height: Int, version v: Int, scale s: PixelScale = .normalized,
            native: NativePixels? = nil
        ) {
            guard v != version || s != scale else { return }
            version = v
            scale = s
            generation += 1
            build?.cancel()
            build = nil
            // The old resource goes first, so a new large image is not built while the previous one is still held.
            dataImage = nil
            rgbaTexture = nil
            failure = nil
            guard width > 0, height > 0 else { return }
            guard let device = MetalEngine.available?.device else {
                if case .failure(let error) = MetalEngine.startup { failure = .noMetal(error.localizedDescription) }
                return
            }
            let tooLarge = MetalImageFailure.tooLarge(width: width, height: height)
            if let rgba, rgba.count == width * height * 4 {
                rgbaTexture = device.makeRGBATexture(rgba: rgba, width: width, height: height)
                if rgbaTexture == nil { failure = tooLarge }
            } else if let native, native.count == width * height, case .raw(let range) = s {
                if native.count < Self.backgroundBuildPixels {
                    dataImage = device.makeDisplayImage(native: native, width: width, height: height, range: range)
                    if dataImage == nil { failure = tooLarge }
                } else {
                    land(generation, tooLarge) { await Self.displayImageOffMain(native: native, width: width, height: height, range: range) }
                }
            } else if pixels.count == width * height {
                switch s {
                case .normalized where pixels.count < Self.backgroundBuildPixels:
                    dataImage = Self.normalizedImage(device, pixels: pixels, width: width, height: height)
                    if dataImage == nil { failure = tooLarge }
                case .normalized:
                    // A large normalised image is copied off the main actor too (it was built on it at any size).
                    land(generation, tooLarge) { await Self.normalizedImageOffMain(pixels: pixels, width: width, height: height) }
                case .raw(let range) where pixels.count < Self.backgroundBuildPixels:
                    dataImage = device.makeDisplayImage(raw: pixels, width: width, height: height, range: range)
                    if dataImage == nil { failure = tooLarge }
                case .raw(let range):
                    // Off the main actor: a blocked window while a 375-megapixel image packs fails the bar (12 Nov, the SEM TIFF's tab
                    // would not switch for about 40 s while the old per-pixel pack ran on the main thread).
                    land(generation, tooLarge) { await Self.displayImageOffMain(raw: pixels, width: width, height: height, range: range) }
                }
            }
        }

        /// Builds the image off the main actor and, back on it, keeps it and asks the view to draw, unless a newer update came first
        /// (which cancels this build: a cancelled build that has not started never allocates). A build that gives nothing (past
        /// the GPU's buffer limit) shows `failed` on the pane.
        private func land(_ asked: Int, _ failed: MetalImageFailure, _ make: @escaping @Sendable () async -> DisplayImage?) {
            build = Task { @MainActor [weak self] in
                let image = await make()
                guard !Task.isCancelled, let self, self.generation == asked else { return }
                self.dataImage = image
                if image == nil { self.failure = failed }
                self.build = nil
                self.lastApplied = nil   // the next update redraws too, whatever it carries
                self.view?.needsDisplay = true
            }
        }

        nonisolated private static func normalizedImage(_ device: MTLDevice, pixels: [Float], width: Int, height: Int) -> DisplayImage? {
            device.makeImageBuffer(pixels: pixels, width: width, height: height).map {
                DisplayImage(buffer: $0, width: width, height: height, encoding: .normalizedFloat, low: 0, span: 1)
            }
        }

        @concurrent
        nonisolated private static func normalizedImageOffMain(pixels: [Float], width: Int, height: Int) async -> DisplayImage? {
            guard !Task.isCancelled, let device = MetalEngine.available?.device else { return nil }
            return normalizedImage(device, pixels: pixels, width: width, height: height)
        }

        @concurrent
        nonisolated private static func displayImageOffMain(raw: [Float], width: Int, height: Int,
                                                            range: ClosedRange<Float>?) async -> DisplayImage? {
            guard !Task.isCancelled, let device = MetalEngine.available?.device else { return nil }
            return device.makeDisplayImage(raw: raw, width: width, height: height, range: range)
        }

        @concurrent
        nonisolated private static func displayImageOffMain(native: NativePixels, width: Int, height: Int,
                                                            range: ClosedRange<Float>?) async -> DisplayImage? {
            guard !Task.isCancelled, let device = MetalEngine.available?.device else { return nil }
            return device.makeDisplayImage(native: native, width: width, height: height, range: range)
        }

        /// The shader's transfer parameters (kind, rangeLow, rangeSpan, 0): the log transfer needs the raw range, so it applies
        /// to raw pixels with a finite range only; everything else draws linear.
        nonisolated static func transferParameters(_ transfer: DisplayTransfer, scale: PixelScale) -> SIMD4<Float> {
            guard transfer == .log, case .raw(let range?) = scale else { return SIMD4<Float>(0, 0, 1, 0) }
            return SIMD4<Float>(1, range.lowerBound, range.upperBound - range.lowerBound, 0)
        }

        /// The shader's display parameters: (lo, hi, gamma, sampling), sampling 0 for nearest and 1 for linear.
        nonisolated static func displayParameters(range: SIMD2<Float>, gamma: Float, sampling: Sampling) -> SIMD4<Float> {
            SIMD4<Float>(range.x, range.y, gamma, sampling == .linear ? 1 : 0)
        }

        func rebuildLUTIfNeeded() {
            guard lutDirty || lutTexture == nil, let engine = MetalEngine.available else { return }
            lutTexture = engine.device.makeLUTTexture(
                rgba: Colormaps.lutRGBA(colormap, count: 256))
            lutDirty = false
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // `updateMetalView` no longer redraws on every update, so a resize
            // or a backing-scale change asks for its own frame.
            view.needsDisplay = true
        }

        public func draw(in view: MTKView) {
            rebuildLUTIfNeeded()

            guard let engine = MetalEngine.available,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = engine.queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
            else {
                // Nothing was presented (no window or drawable yet): forget the
                // applied state so the next update draws instead of being skipped.
                lastApplied = nil
                return
            }

            if rgbaTexture != nil {
                encoder.setRenderPipelineState(engine.displayRGBAPSO)
            } else if dataImage != nil, lutTexture != nil {
                encoder.setRenderPipelineState(engine.displayPSO)
            } else {
                encoder.endEncoding()
                buffer.present(drawable)
                buffer.commit()
                return
            }

            // Two rows (pane-normalised q -> image uv); identity without a transform.
            let identityRows = (SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0))
            let r = displayTransform?.shaderRows() ?? identityRows
            var rows = [r.0, r.1]
            encoder.setVertexBytes(
                &rows, length: 2 * MemoryLayout<SIMD4<Float>>.stride, index: 0)

            if let rgbaTexture {
                encoder.setFragmentTexture(rgbaTexture, index: 0)
            } else {
                var display = Self.displayParameters(range: displayRange, gamma: gamma, sampling: sampling)
                encoder.setFragmentBytes(
                    &display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                if let dataImage {
                    encoder.setFragmentBuffer(dataImage.buffer, offset: 0, index: 1)
                    var size = SIMD2<UInt32>(UInt32(dataImage.width), UInt32(dataImage.height))
                    encoder.setFragmentBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 2)
                    var parameters = dataImage.parameters
                    encoder.setFragmentBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
                }
                var transferParameters = Self.transferParameters(transfer, scale: scale)
                encoder.setFragmentBytes(&transferParameters, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
                encoder.setFragmentTexture(lutTexture, index: 1)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

extension MetalImageView: NSViewRepresentable {
    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> MTKView { makeMetalView(context.coordinator) }
    public func updateNSView(_ view: MTKView, context: Context) {
        updateMetalView(view, context.coordinator)
    }
}
