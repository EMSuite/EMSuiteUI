//
//  Colormaps.metal
//  Role: GPU-side image display. A fullscreen-triangle vertex shader (no vertex
//        buffer — positions come from vertex_id) plus a fragment shader that
//        reads a single-channel, already-normalized result buffer and looks up
//        its color in a 1D colormap LUT texture. Zoom, pan, rotation and mirroring
//        come from one affine map (pane-normalised position -> image uv).
//
//  Both the diffraction viewer and the real-space result viewer render through
//  this pipeline (see MetalImageView.swift).
//

#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

// Parameters cross as plain float4 buffers (MetalImageView sets them with SIMD4<Float>). A parameter struct added here must
// stay byte-identical to its Swift twin (all 4-byte fields) and get a MemoryLayout test; none exists yet.
//
// xf = two rows (A00, A01, t0, 0), (A10, A11, t1, 0): image uv = A q + t, with q
// the pane-normalised position (0...1, origin top-left). Identity = whole image.
vertex VOut displayVertex(uint vid [[vertex_id]],
                          constant float4 *xf [[buffer(0)]])
{
    // One oversized triangle covering the viewport.
    const float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    // Matching UVs; v flipped so texture row 0 appears at the TOP.
    const float2 uvs[3] = { float2(0.0, 1.0),  float2(2.0, 1.0),  float2(0.0, -1.0) };

    VOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    float2 q = uvs[vid];
    o.uv = float2(dot(xf[0].xy, q) + xf[0].z,
                  dot(xf[1].xy, q) + xf[1].z);
    return o;
}

// How many taps a side a zoomed-out pixel averages (MacEMUI#158). At 1:1 or magnified a pane pixel covers one image pixel
// or less and reads it alone, nearest, so zoomed data pixels stay crisp and exact. Zoomed out it covers `f` image pixels a
// side, and one nearest read per pane pixel skips the rest: a 375-megapixel image fitted to a pane aliased into moiré and
// shimmered as it panned. Instead the pane pixel averages an n × n grid of taps spread over its footprint, n = ceil(f),
// at most 8 (64 taps), as matplotlib antialiases a downsampled image in RGBA. Taps step about f / n image pixels apart, so
// the GPU's cache lines are shared between them and neighbouring pixels: a frame touches about n / f of the image, and no
// mipmap copy of a large image is kept. The 0.05 slack keeps an exact 1:1 frame, whose footprint rounds to a hair over
// one pixel, on the single nearest read.
constant int maxTapsPerSide = 8;

static inline int tapsPerSide(float2 dx, float2 dy) {
    float footprint = max(length(dx), length(dy));
    return clamp(int(ceil(footprint - 0.05)), 1, maxTapsPerSide);
}

// Buffer pixel i as x = its normalised display value (negative or NaN = masked) and y = its raw value, which the log
// transfer reads.
static inline float2 pixelValue(uint i,
                                device const uchar *img,
                                constant float4 &image,
                                constant float4 &transfer)
{
    uint encoding = uint(image.z);
    float raw;
    float value;   // the raw pixel value, for the log transfer
    if (encoding == 0) {
        raw = ((device const float *)img)[i];
        value = transfer.y + raw * transfer.z;
    } else {
        float v = encoding == 1 ? float(img[i]) : float(((device const ushort *)img)[i]);
        raw = image.y > 0.0 ? (v - image.x) / image.y : 0.0;
        value = v;
    }
    return float2(raw, value);
}

// A pixel's colour through the transfer, window, gamma and LUT (or the masked gray), from its `pixelValue`.
static inline float3 valueColor(float2 pixel,
                                constant float4 &display,
                                constant float4 &transfer,
                                texture1d<float> lut)
{
    // rgba8 LUT is filterable → smooth color ramp.
    constexpr sampler lutSampler(address::clamp_to_edge, filter::linear);

    float raw = pixel.x;
    float value = pixel.y;
    // Invalid/masked pixels arrive as a negative sentinel (see
    // FloatImage.invalidDisplayValue). They get a dedicated neutral gray,
    // never a colormap entry — "no data" must not look like a value.
    // A NaN is masked too. Tested on the bits: Metal compiles with fast math, where isnan() may be folded to false.
    if (raw < 0.0 || (as_type<uint>(raw) & 0x7fffffffu) > 0x7f800000u) {
        return float3(0.32, 0.32, 0.34);
    }
    if (transfer.x == 1.0) {
        float lo = log10(1.0 + max(transfer.y, 0.0));
        float hi = log10(1.0 + max(transfer.y + transfer.z, 0.0));
        raw = hi > lo ? (log10(1.0 + max(value, 0.0)) - lo) / (hi - lo) : 0.0;
    }
    float v = clamp(raw, 0.0, 1.0);
    v = clamp((v - display.x) / max(display.y - display.x, 1e-6), 0.0, 1.0);
    v = pow(v, 1.0 / max(display.z, 0.05));
    return lut.sample(lutSampler, v).rgb;
}

// One image pixel's colour through the window, gamma and LUT (or the masked gray), from the row-major buffer at uv: the
// pixel uv falls in, NEAREST (the default, `MetalImageView.Sampling.nearest`).
static inline float3 scalarColor(float2 uv,
                                 constant float4 &display,
                                 device const uchar *img,
                                 constant uint2 &size,
                                 constant float4 &image,
                                 constant float4 &transfer,
                                 texture1d<float> lut)
{
    uint x = min(uint(clamp(uv.x, 0.0, 1.0) * float(size.x)), size.x - 1);
    uint y = min(uint(clamp(uv.y, 0.0, 1.0) * float(size.y)), size.y - 1);
    uint i = y * size.x + x;
    return valueColor(pixelValue(i, img, image, transfer), display, transfer, lut);
}

// True for a value a linear read cannot blend: masked (negative), NaN or infinite. Tested on the bits, as valueColor does.
static inline bool unblendable(float raw) {
    return raw < 0.0 || (as_type<uint>(raw) & 0x7f800000u) == 0x7f800000u;
}

// The colour at uv from the four pixels around it, their VALUES blended bilinearly before the transfer, window, gamma and
// LUT (`MetalImageView.Sampling.linear`, for a coarse simulated scan). Pixel centres sit at (i + 0.5) / size, so the cell is
// floor(uv * size - 0.5) and the weights its fraction; neighbours past an edge clamp to the edge pixel (no wrap, no dark
// border). Mirrored by `MetalImageView.linearTaps` and `linearSample`. A masked or non-finite pixel among the four has no
// value to blend: the read falls back to the nearest pixel, so a mask keeps its edge.
static inline float3 linearScalarColor(float2 uv,
                                       constant float4 &display,
                                       device const uchar *img,
                                       constant uint2 &size,
                                       constant float4 &image,
                                       constant float4 &transfer,
                                       texture1d<float> lut)
{
    float2 p = clamp(uv, float2(0.0), float2(1.0)) * float2(size) - 0.5;
    float2 cell = floor(p);
    float2 w = p - cell;
    int lastX = int(size.x) - 1;
    int lastY = int(size.y) - 1;
    int cx = int(cell.x);
    int cy = int(cell.y);
    uint x0 = uint(clamp(cx, 0, lastX));
    uint x1 = uint(clamp(cx + 1, 0, lastX));
    uint y0 = uint(clamp(cy, 0, lastY));
    uint y1 = uint(clamp(cy + 1, 0, lastY));
    float2 v00 = pixelValue(y0 * size.x + x0, img, image, transfer);
    float2 v10 = pixelValue(y0 * size.x + x1, img, image, transfer);
    float2 v01 = pixelValue(y1 * size.x + x0, img, image, transfer);
    float2 v11 = pixelValue(y1 * size.x + x1, img, image, transfer);
    if (unblendable(v00.x) || unblendable(v10.x) || unblendable(v01.x) || unblendable(v11.x)) {
        return scalarColor(uv, display, img, size, image, transfer, lut);
    }
    float2 top = v00 + (v10 - v00) * w.x;
    float2 bottom = v01 + (v11 - v01) * w.x;
    return valueColor(top + (bottom - top) * w.y, display, transfer, lut);
}

// display = (lo, hi, gamma, sampling) in normalized [0,1] intensity; sampling 0 reads the nearest pixel (the default), 1
// blends the four around a magnified or 1:1 pane pixel (`linearScalarColor`, `MetalImageView.Sampling`). Zoomed out the
// footprint average below already blends pixels and reads them nearest in both modes.
// img = the row-major image, size = (width, height), image = (low, span, encoding, 0) (`DisplayImage` in Swift). A buffer,
// not a texture: a 2D texture is limited to 16384 pixels a side, and larger images must draw (macTEM#562). Read NEAREST, as
// a clamp-to-edge nearest sampler would (or linear, `display.w` above), and averaged over a zoomed-out pixel's footprint
// (`tapsPerSide`). Encoding 0: Float32 display values as given; 1 and 2: whole-number raw values in one or two bytes,
// normalised here as the CPU does, (v - low) / span, 0 for a flat image (`DisplayNormalization`).
// transfer = (kind, rangeLow, rangeSpan, 0) (`MetalImageView.DisplayTransfer`). Kind 0: the normalised value as it is. Kind 1:
// log10(1 + max(v, 0)) of the raw value v, normalised over the same of the raw range, as ImagoKit's
// `DisplayNormalization.normalizedLog` makes a pattern's log display values on the CPU (macEM#580). A Float32 image's raw
// value is rangeLow + n * rangeSpan.
fragment float4 colormapFragment(VOut in [[stage_in]],
                                 constant float4 &display [[buffer(0)]],
                                 device const uchar *img [[buffer(1)]],
                                 constant uint2 &size [[buffer(2)]],
                                 constant float4 &image [[buffer(3)]],
                                 constant float4 &transfer [[buffer(4)]],
                                 texture1d<float> lut [[texture(1)]])
{
    // The footprint, in uv per pane pixel, taken before any branch (derivatives need every pixel of the quad).
    float2 du = dfdx(in.uv);
    float2 dv = dfdy(in.uv);
    float2 imageSize = float2(size);

    // Outside the image (zoomed out, panned, letterboxed) → transparent, so
    // what is behind the view shows.
    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.0);
    }

    int n = tapsPerSide(du * imageSize, dv * imageSize);
    if (n == 1) {
        if (display.w == 1.0) {
            return float4(linearScalarColor(in.uv, display, img, size, image, transfer, lut), 1.0);
        }
        return float4(scalarColor(in.uv, display, img, size, image, transfer, lut), 1.0);
    }
    float3 sum = float3(0.0);
    for (int j = 0; j < n; j++) {
        for (int i = 0; i < n; i++) {
            float2 o = (float2(i, j) + 0.5) / float(n) - 0.5;
            sum += scalarColor(in.uv + o.x * du + o.y * dv, display, img, size, image, transfer, lut);
        }
    }
    return float4(sum / float(n * n), 1.0);
}

// Pre-colored results (DPC color wheel): sample the RGBA texture directly,
// no LUT. Same vertex shader / display transform as the scalar path, and the same footprint average zoomed out.
fragment float4 rgbaFragment(VOut in [[stage_in]],
                             texture2d<float> img [[texture(0)]])
{
    constexpr sampler dataSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

    float2 du = dfdx(in.uv);
    float2 dv = dfdy(in.uv);
    float2 imageSize = float2(img.get_width(), img.get_height());

    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.0);
    }
    int n = tapsPerSide(du * imageSize, dv * imageSize);
    if (n == 1) {
        return float4(img.sample(dataSampler, in.uv).rgb, 1.0);
    }
    float3 sum = float3(0.0);
    for (int j = 0; j < n; j++) {
        for (int i = 0; i < n; i++) {
            float2 o = (float2(i, j) + 0.5) / float(n) - 0.5;
            sum += img.sample(dataSampler, in.uv + o.x * du + o.y * dv).rgb;
        }
    }
    return float4(sum / float(n * n), 1.0);
}
