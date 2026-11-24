//
//  QuickLookCard.swift
//  Role: the Quick Look preview card as one SwiftUI view turned into a PNG with `ImageRenderer` (a data-based preview: no view
//        controller, no AppKit): the image on the left with its scale bar, on the right a short list of what the file's headers say.
//        The rows and the bar are plain data (`rows(for:)`, `QuickLookScaleBar.plan(summary:frame:)`) so a test reads them; the view
//        only lays them out.
//  Provenance: moved from 4DSTEM Studio's QuickLook/Shared (package target DSTEMQuickLook) with the scale bar added, for both apps'
//        Quick Look extensions (EMSuiteUI#225). The rows are unchanged.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import FormatoPeek
import ImagoCore

public nonisolated enum QuickLookCardContent {
    public struct Row: Sendable, Equatable {
        public let label: String
        public let value: String
    }

    /// What the card lists, in order, skipping what the file does not say. Numbers use a locale-free decimal mark: the card is a picture.
    public static func rows(for s: Peek.Summary) -> [Row] {
        var rows: [Row] = [Row(label: "Format", value: s.format)]
        func add(_ label: String, _ value: String?) { if let value, !value.isEmpty { rows.append(Row(label: label, value: value)) } }
        add("Title", s.title)
        add("Signal", s.signalType)
        if let w = s.scanWidth, let h = s.scanHeight {
            add("Scan", "\(w) \u{00D7} \(h) positions")
            add("Detector", "\(s.width) \u{00D7} \(s.height) px")
        } else {
            add("Size", "\(s.width) \u{00D7} \(s.height) px")
        }
        if let size = s.pixelSize, size.isFinite, size > 0 {
            add(s.scanWidth == nil ? "Pixel size" : "Scan step", number(size) + (s.pixelUnit.map { " " + $0 } ?? ""))
        }
        if let size = s.detectorPixelSize, size.isFinite, size > 0 {
            add("Detector step", number(size) + (s.detectorPixelUnit.map { " " + $0 } ?? ""))
        }
        add("Acquired", s.acquired)
        add("Detector name", s.detector)
        add("Instrument", s.instrument)
        add("Voltage", s.highTensionKV.map { number($0) + " kV" })
        add("Camera length", s.cameraLengthMM.map { number($0) + " mm" })
        add("Magnification", s.magnification.map { number($0) + "\u{00D7}" })
        add("Data type", s.dataType)
        for note in s.notes { add("Note", note) }
        return rows
    }

    private static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.significantDigits(1...5)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// The scale bar of the card's image: ImagoKit's `ScaleBarMath` on the frame's own pixels, each one `stride` source pixels.
public nonisolated enum QuickLookScaleBar {
    /// The calibration one frame pixel carries: the detector step for a diffraction pattern, the pixel size (or scan step) for an
    /// image or a virtual image, times the frame's decimation stride; nil for a spectrum or a file that states no size.
    public static func calibration(summary s: Peek.Summary, frame: Peek.Frame) -> AxisCalibration? {
        var size: Double?, unit: String?
        switch frame.kind {
        case .spectrum:
            return nil
        case .diffractionPattern:
            // A 4D file's pattern takes the detector step; a single pattern (no scan) its own pixel size.
            size = s.detectorPixelSize ?? (s.scanWidth == nil ? s.pixelSize : nil)
            unit = s.detectorPixelSize != nil ? s.detectorPixelUnit : (s.scanWidth == nil ? s.pixelUnit : nil)
        case .image, .virtualImage:
            size = s.pixelSize
            unit = s.pixelUnit
        }
        guard let size, size.isFinite, size > 0, let unit, !unit.isEmpty else { return nil }
        let step = size * Double(max(frame.stride, 1))
        guard step.isFinite else { return nil }
        return AxisCalibration(scale: step, unit: unit)
    }

    /// The bar over the frame (lengths in frame pixels), or nil when there is no calibration, the unit is pixels, or the bar would
    /// not fit. Units are spelled as the apps' panes spell them (a length's canonical spelling, "px" for pixels).
    public static func plan(summary: Peek.Summary, frame: Peek.Frame) -> ScaleBarPlan? {
        guard let cal = calibration(summary: summary, frame: frame), frame.width > 0, frame.height > 0 else { return nil }
        guard let plan = ScaleBarMath.plan(x: cal, y: cal, width: frame.width, height: frame.height, unitLabel: label) else { return nil }
        return plan.unit == "px" ? nil : plan
    }

    private static func label(_ unit: String) -> String {
        if ["px", "pix", "[pix]", "[px]", "pixel", "pixels"].contains(LengthUnit.normalized(unit)) { return "px" }
        return LengthUnit.canonicalReciprocalUnit(unit) ?? LengthUnit.canonicalRealUnit(unit) ?? unit
    }
}

public struct QuickLookCard: View {
    public let rows: [QuickLookCardContent.Row]
    public let image: CGImage?
    public let fileName: String
    /// The bar as a fraction of the image's width, and its label.
    public let scaleBar: (fraction: Double, label: String)?

    public init(rows: [QuickLookCardContent.Row], image: CGImage?, fileName: String, scaleBar: (fraction: Double, label: String)? = nil) {
        self.rows = rows; self.image = image; self.fileName = fileName; self.scaleBar = scaleBar
    }

    static let imageSide: CGFloat = 360

    public var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Group {
                if let image {
                    let fitted = Self.fitted(width: image.width, height: image.height)
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: fitted.width, height: fitted.height)
                        .overlay(alignment: .bottomLeading) {
                            if let scaleBar { bar(scaleBar, imageWidth: fitted.width) }
                        }
                } else {
                    Color.black.opacity(0.85).overlay(Text("No preview image").foregroundStyle(.secondary))
                }
            }
            .frame(width: Self.imageSide, height: Self.imageSide)
            .background(Color.black)
            VStack(alignment: .leading, spacing: 6) {
                Text(fileName).font(.title3.weight(.semibold)).lineLimit(2)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
                        Text(row.value).monospacedDigit().lineLimit(2)
                    }
                    .font(.callout)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: 760, height: 400)
        .background(Color(white: 0.96))
        .environment(\.colorScheme, .light)
    }

    /// The bar on a dark plate at the image's lower left: white, as the panes draw it over an image.
    private func bar(_ bar: (fraction: Double, label: String), imageWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bar.label).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            Rectangle().fill(.white).frame(width: max(1, CGFloat(bar.fraction) * imageWidth), height: 3)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
        .padding(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale bar, \(bar.label)")
    }

    /// The image's size in the card: the largest with its aspect inside the image square.
    static func fitted(width: Int, height: Int) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        let aspect = CGFloat(width) / CGFloat(height)
        let w = min(imageSide, imageSide * aspect)
        return CGSize(width: w, height: w / aspect)
    }

    /// The card as PNG data (2x), or nil when rendering fails. Main actor: `ImageRenderer`.
    @MainActor public static func pngData(summary: Peek.Summary, frame: Peek.Frame?, fileName: String) -> Data? {
        let image = frame.flatMap { QuickLookRendering.image(for: $0, within: CGSize(width: 720, height: 720)) }
        let plan = frame.flatMap { QuickLookScaleBar.plan(summary: summary, frame: $0) }
        let bar = zip2(plan, frame).map { (fraction: $0.lengthPixels / Double($1.width), label: $0.label) }
        let card = QuickLookCard(rows: QuickLookCardContent.rows(for: summary), image: image, fileName: fileName, scaleBar: bar)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    public static let contentSize = CGSize(width: 760, height: 400)
}
