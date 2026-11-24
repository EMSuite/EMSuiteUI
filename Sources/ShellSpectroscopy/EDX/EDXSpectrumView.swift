//
//  EDXSpectrumView.swift
//  Role: the EDX room's spectrum: the region's counts against energy, the picked elements' alpha lines marked, and, once
//        the fit has run, the fitted continuum and the model on the fit's own energy axis. One `Canvas`. Zoom is a pinch
//        about the pointer or the scroll wheel, pan is a drag in the plot, a drag along an axis zooms that axis, a double click returns to the automatic window (`EDXRoomState.window`, `yZoom`).
//        Presentation only: the numbers are `EDXSession.plot`'s; the window rules are `EDXSpectrumWindow` (pure).
//

import ShellControls
import SwiftUI
import ShellEDXModel

/// The energy window's arithmetic, pure: it always stays inside the spectrum's range and never gets narrower than two channels.
public nonisolated enum EDXSpectrumWindow {
    public static func clamp(_ w: ClosedRange<Double>, domain: ClosedRange<Double>, minimumSpan: Double) -> ClosedRange<Double> {
        let full = domain.upperBound - domain.lowerBound
        let span = min(max(w.upperBound - w.lowerBound, minimumSpan), full)
        let lo = min(max(w.lowerBound, domain.lowerBound), domain.upperBound - span)
        return lo...(lo + span)
    }

    /// Zoom by `factor` (> 1 shows less) about the fraction `anchor` (0...1) of the window.
    public static func zoomed(_ w: ClosedRange<Double>, factor: Double, anchor: Double, domain: ClosedRange<Double>, minimumSpan: Double) -> ClosedRange<Double> {
        guard factor.isFinite, factor > 0 else { return w }
        let span = (w.upperBound - w.lowerBound) / factor
        let pivot = w.lowerBound + anchor * (w.upperBound - w.lowerBound)
        let lo = pivot - anchor * span
        return clamp(lo...(lo + span), domain: domain, minimumSpan: minimumSpan)
    }

    /// Pan by a fraction of the window (positive moves the window to higher energy).
    public static func panned(_ w: ClosedRange<Double>, byFraction f: Double, domain: ClosedRange<Double>, minimumSpan: Double) -> ClosedRange<Double> {
        let d = f * (w.upperBound - w.lowerBound)
        return clamp((w.lowerBound + d)...(w.upperBound + d), domain: domain, minimumSpan: minimumSpan)
    }

    /// One keyboard or VoiceOver step on the window (EMSuiteUI#126: the spectrum's zoom and pan were pointer-only): zoom in or out by
    /// 1.5 about the middle, pan by a tenth of the window. The same rules as the pointer's, so the window stays inside the spectrum.
    public nonisolated enum Step: Sendable, CaseIterable {
        case zoomIn, zoomOut, panToLower, panToHigher

        public var name: String {
            switch self {
            case .zoomIn: "Zoom In"
            case .zoomOut: "Zoom Out"
            case .panToLower: "Show Lower Energies"
            case .panToHigher: "Show Higher Energies"
            }
        }
    }

    public static func stepped(_ w: ClosedRange<Double>, _ step: Step, domain: ClosedRange<Double>, minimumSpan: Double) -> ClosedRange<Double> {
        switch step {
        case .zoomIn: zoomed(w, factor: 1.5, anchor: 0.5, domain: domain, minimumSpan: minimumSpan)
        case .zoomOut: zoomed(w, factor: 1 / 1.5, anchor: 0.5, domain: domain, minimumSpan: minimumSpan)
        case .panToLower: panned(w, byFraction: -0.1, domain: domain, minimumSpan: minimumSpan)
        case .panToHigher: panned(w, byFraction: 0.1, domain: domain, minimumSpan: minimumSpan)
        }
    }

    /// Channels below this energy are the detector's strobe peak and do not set the count axis' scale.
    public static let strobeCeilingKeV = 0.1

    /// Tick positions inside `w`: a step of 1, 2 or 5 times a power of ten giving about six ticks.
    public static func ticks(in w: ClosedRange<Double>) -> [Double] {
        let span = w.upperBound - w.lowerBound
        guard span > 0 else { return [] }
        let raw = span / 6
        let mag = pow(10, floor(log10(raw)))
        let step = [1.0, 2, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? 10 * mag
        var out: [Double] = []
        var t = (w.lowerBound / step).rounded(.up) * step
        while t <= w.upperBound + 1e-9 { out.append(t); t += step }
        return out
    }
}

/// What a drag on the spectrum does, decided by where it starts (pure): under the plot the energy axis, left of it the counts axis, inside it a pan.
public nonisolated enum EDXSpectrumDrag {
    public enum Zone: Equatable { case energyAxis, countsAxis, plot }

    public static func zone(start: CGPoint, size: CGSize) -> Zone {
        if start.y > size.height - EDXSpectrumView.bottom { return .energyAxis }
        if start.x < EDXSpectrumView.left { return .countsAxis }
        return .plot
    }

    /// The counts axis' zoom after a vertical drag of `dy` points from `start` (up, negative dy, zooms in), within 1...1000.
    public static func yZoom(start: Double, dy: Double) -> Double { min(max(start * exp(-dy / 150), 1), 1000) }
}

/// The spectrum's curves once the fit has run, each told by its shape and named in the legend under the plot, never by colour alone
/// (EMSuiteUI Q8): the measured spectrum is a filled line, the continuum a dashed line, the fit a solid line.
public nonisolated enum EDXSpectrumSeries: CaseIterable, Sendable {
    case spectrum, continuum, fit

    public var title: String {
        switch self {
        case .spectrum: "spectrum"
        case .continuum: "continuum"
        case .fit: "fit"
        }
    }

    /// The line's dash; empty is solid.
    public var dash: [CGFloat] { self == .continuum ? [4, 3] : [] }
    /// Whether the area under the line is filled.
    public var isFilled: Bool { self == .spectrum }
    /// The lines' width: Increase Contrast thickens them.
    public static func lineWidth(increasedContrast: Bool) -> CGFloat { increasedContrast ? 1.75 : 1 }

    var color: Color {
        switch self {
        case .spectrum: .accentColor
        case .continuum: .orange
        case .fit: .red
        }
    }
}

struct EDXSpectrumView: View {
    let plot: EDXPlot
    let markers: [EDXMarker]
    let hasFit: Bool
    /// The regions' spectra drawn over the selected one (and the pointer's pixel).
    var layers: [SpectrumLayer] = []
    @Bindable var state: EDXRoomState

    @State private var pinchStart: ClosedRange<Double>?
    @State private var panStart: ClosedRange<Double>?
    @State private var yStart: Double?
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var domain: ClosedRange<Double> {
        let end = plot.energyStart + plot.energyStep * Double(plot.data.count)
        return plot.energyStart...max(end, plot.energyStart + plot.energyStep)
    }
    private var minimumSpan: Double { 2 * plot.energyStep }
    private var window: ClosedRange<Double> {
        EDXSpectrumWindow.clamp(state.window ?? EDXRoomFormat.autoWindow(plot: plot, markers: markers), domain: domain, minimumSpan: minimumSpan)
    }

    var body: some View {
        // Both are read here, in the body, so a change redraws the canvas while the pointer moves; `draw` takes them as values.
        let w = window
        let yZoom = state.yZoom
        GeometryReader { geo in
            let plotWidth = max(geo.size.width - Self.left - Self.right, 1)
            // The canvas is a view of its own with the window and the counts zoom as stored values: a change of either is a change of the view.
            EDXSpectrumCanvas(window: w, yZoom: yZoom, increasedContrast: contrast == .increased, spectrum: self)
                .contentShape(Rectangle())
                .gesture(MagnifyGesture()
                    .onChanged { v in
                        let start = pinchStart ?? w
                        if pinchStart == nil { pinchStart = start }
                        let anchor = min(max((v.startLocation.x - Self.left) / plotWidth, 0), 1)
                        state.window = EDXSpectrumWindow.zoomed(start, factor: v.magnification, anchor: anchor, domain: domain, minimumSpan: minimumSpan)
                    }
                    .onEnded { _ in pinchStart = nil })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        guard p.x >= Self.left, p.x <= geo.size.width - Self.right, plot.energyStep > 0 else { state.readout = nil; return }
                        let e = w.lowerBound + Double((p.x - Self.left) / plotWidth) * (w.upperBound - w.lowerBound)
                        let i = Int(((e - plot.energyStart) / plot.energyStep).rounded(.down))
                        state.readout = plot.data.indices.contains(i) ? "\(Num.sig(e, 4)) keV · \(EDXRoomFormat.counts(plot.data[i])) counts" : nil
                    case .ended: state.readout = nil
                    }
                }
                .onScrollWheel { event in
                    let anchor = min(max((event.location.x - Self.left) / plotWidth, 0), 1)
                    state.window = EDXSpectrumWindow.zoomed(w, factor: ScrollZoom.factor(delta: event.delta, isPrecise: event.isPrecise), anchor: anchor, domain: domain, minimumSpan: minimumSpan)
                }
                // High priority: as a plain `.gesture`, a vertical drag on the counts axis reached `onChanged` only on release (measured on screen,
                // drive 2026-10-23: the energy axis was live, the counts axis jumped at the end).
                .highPriorityGesture(DragGesture(minimumDistance: 3)
                    .onChanged { v in
                        switch EDXSpectrumDrag.zone(start: v.startLocation, size: geo.size) {
                        case .energyAxis:
                            // Along the energy axis: right zooms in about where the drag began.
                            let start = panStart ?? w
                            if panStart == nil { panStart = start }
                            let anchor = min(max((v.startLocation.x - Self.left) / plotWidth, 0), 1)
                            state.window = EDXSpectrumWindow.zoomed(start, factor: exp(Double(v.translation.width) / 150), anchor: anchor, domain: domain, minimumSpan: minimumSpan)
                        case .countsAxis:
                            // Along the counts axis: up zooms in.
                            let start = yStart ?? state.yZoom
                            if yStart == nil { yStart = start }
                            state.yZoom = EDXSpectrumDrag.yZoom(start: start, dy: Double(v.translation.height))
                        case .plot:
                            let start = panStart ?? w
                            if panStart == nil { panStart = start }
                            state.window = EDXSpectrumWindow.panned(start, byFraction: -v.translation.width / plotWidth, domain: domain, minimumSpan: minimumSpan)
                        }
                    }
                    .onEnded { _ in panStart = nil; yStart = nil })
                .onTapGesture(count: 2) { state.window = nil; state.yZoom = 1 }
                // The keyboard's route to what the pointer does (EMSuiteUI#126): + and − zoom about the middle, ← and → pan, 0 returns to
                // the automatic window, as the double click does. A click focuses the spectrum.
                .focusable()
                .focused($focused)
                .onKeyPress(characters: CharacterSet(charactersIn: "+=-0")) { press in
                    switch press.characters {
                    case "+", "=": step(.zoomIn, from: w)
                    case "-": step(.zoomOut, from: w)
                    default: state.window = nil; state.yZoom = 1
                    }
                    return .handled
                }
                .onKeyPress(.leftArrow) { step(.panToLower, from: w); return .handled }
                .onKeyPress(.rightArrow) { step(.panToHigher, from: w); return .handled }
                .accessibilityElement()
                .accessibilityLabel("Spectrum, \(String(format: "%.2f", w.lowerBound)) to \(String(format: "%.2f", w.upperBound)) keV"
                    + (hasFit && !plot.model.isEmpty ? ", with the fitted continuum and fit" : "")
                    + (markers.isEmpty ? "" : ", lines: " + EDXRoomFormat.lines(markers)))
                .accessibilityIdentifier("edx.spectrum")
                .accessibilityAction(named: EDXSpectrumWindow.Step.zoomIn.name) { step(.zoomIn, from: w) }
                .accessibilityAction(named: EDXSpectrumWindow.Step.zoomOut.name) { step(.zoomOut, from: w) }
                .accessibilityAction(named: EDXSpectrumWindow.Step.panToLower.name) { step(.panToLower, from: w) }
                .accessibilityAction(named: EDXSpectrumWindow.Step.panToHigher.name) { step(.panToHigher, from: w) }
                .accessibilityAction(named: "Show Whole Spectrum") { state.window = nil; state.yZoom = 1 }
        }
    }

    private func step(_ step: EDXSpectrumWindow.Step, from w: ClosedRange<Double>) {
        state.window = EDXSpectrumWindow.stepped(w, step, domain: domain, minimumSpan: minimumSpan)
    }

    nonisolated static let left: CGFloat = 52, bottom: CGFloat = 36, top: CGFloat = 16, right: CGFloat = 8   // read by the nonisolated gesture rule (macTEM's module is nonisolated by default)

    fileprivate func draw(_ context: inout GraphicsContext, size: CGSize, window w: ClosedRange<Double>, yZoom: Double, increasedContrast: Bool = false) {
        let lineWidth = EDXSpectrumSeries.lineWidth(increasedContrast: increasedContrast)
        let showsFit = hasFit && !plot.model.isEmpty
        let area = CGRect(x: Self.left, y: Self.top, width: max(size.width - Self.left - Self.right, 1),
                          height: max(size.height - Self.top - Self.bottom, 1))
        let span = w.upperBound - w.lowerBound
        func x(_ e: Double) -> CGFloat { area.minX + CGFloat((e - w.lowerBound) / span) * area.width }

        // The channels inside the window; one point per pixel column (the column's maximum), so a 4096-channel
        // spectrum draws the same lines at any width.
        func channels(of start: Double, step: Double, count: Int) -> Range<Int> {
            guard step > 0, count > 0 else { return 0..<0 }
            let lo = max(Int(((w.lowerBound - start) / step).rounded(.down)), 0)
            let hi = min(Int(((w.upperBound - start) / step).rounded(.up)) + 1, count)
            return lo < hi ? lo..<hi : 0..<0
        }
        let dataRange = channels(of: plot.energyStart, step: plot.energyStep, count: plot.data.count)
        // The detector's strobe (zero-energy) peak is electronics, not X-rays, and is often the tallest thing in the file: it
        // does not set the scale, or every real line is a few pixels high. It is still drawn, clipped at the top.
        var top = 1.0
        for i in dataRange where plot.energyStart + Double(i) * plot.energyStep >= EDXSpectrumWindow.strobeCeilingKeV { top = max(top, plot.data[i]) }
        if let peak = SpectrumLayerPlot.peak(of: layers, in: w, scale: .linear) { top = max(top, peak) }
        top = top * 1.08 / yZoom
        func y(_ v: Double) -> CGFloat { area.maxY - CGFloat(min(max(v / top, 0), 1)) * area.height }

        // Axes: horizontal grid at the ticks, x labels in keV, y labels in counts.
        for t in EDXSpectrumWindow.ticks(in: w) {
            var p = Path(); p.move(to: CGPoint(x: x(t), y: area.minY)); p.addLine(to: CGPoint(x: x(t), y: area.maxY))
            context.stroke(p, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            context.draw(Text(Num.sig((t * 1000).rounded() / 1000, 6)).font(.caption2).foregroundStyle(.secondary),
                         at: CGPoint(x: x(t), y: area.maxY + 10))
        }
        // Round counts (1, 2 or 5 times a power of ten), as on the energy axis; they were quarters of the tallest channel
        // ("3 582", "1 194"), and seven-digit labels ran out of the margin on the left.
        let countTicks = EDXSpectrumWindow.ticks(in: 0...(top / 1.08))
        let countStep = countTicks.count > 1 ? countTicks[1] - countTicks[0] : top
        for v in countTicks {
            var p = Path(); p.move(to: CGPoint(x: area.minX, y: y(v))); p.addLine(to: CGPoint(x: area.maxX, y: y(v)))
            context.stroke(p, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            context.draw(Text(EDXRoomFormat.axisCounts(v, step: countStep)).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: area.minX - 4, y: y(v)), anchor: .trailing)
        }
        // The axes are named outside the plot: the energy under the ticks, the unit of the counts over their labels.
        // With a fit the legend takes the row's leading end and the axis name moves to its trailing end; a legend that would meet
        // the axis name is left out (VoiceOver's label names the curves either way).
        let axisName = Text("energy (keV)").font(.caption2).foregroundStyle(.secondary)
        if showsFit {
            let axisWidth = context.resolve(axisName).measure(in: CGSize(width: 200, height: 20)).width
            context.draw(axisName, at: CGPoint(x: area.maxX, y: area.maxY + 25), anchor: .trailing)
            Self.drawLegend(&context, at: CGPoint(x: area.minX, y: area.maxY + 25), limit: area.maxX - axisWidth - 12, lineWidth: lineWidth)
        } else {
            context.draw(axisName, at: CGPoint(x: area.midX, y: area.maxY + 25))
        }
        context.draw(Text("counts").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: area.minX - 4, y: area.minY - 8), anchor: .trailing)

        // The line of one series, one point per pixel column.
        func path(_ values: [Double], start: Double, step: Double, offset: Int = 0) -> Path {
            var p = Path()
            let range = channels(of: start, step: step, count: values.count)
            guard !range.isEmpty else { return p }
            var column = Int.min
            var colMax = 0.0
            var first = true
            func flush(_ c: Int, _ v: Double) {
                let pt = CGPoint(x: area.minX + CGFloat(c) + 0.5, y: y(v))
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            }
            for i in range {
                let c = Int(x(start + step * Double(i)) - area.minX)
                if c != column { if column != Int.min { flush(column, colMax) }; column = c; colMax = values[i] } else { colMax = max(colMax, values[i]) }
            }
            if column != Int.min { flush(column, colMax) }
            return p
        }
        let line = path(plot.data, start: plot.energyStart, step: plot.energyStep)
        var fill = line
        if !fill.isEmpty {
            fill.addLine(to: CGPoint(x: area.maxX, y: area.maxY)); fill.addLine(to: CGPoint(x: area.minX, y: area.maxY)); fill.closeSubpath()
            context.fill(fill, with: .color(.accentColor.opacity(0.12)))
        }
        context.stroke(line, with: .color(EDXSpectrumSeries.spectrum.color), lineWidth: lineWidth)
        if showsFit {
            // The fitted curves cover the fitted channels only.
            func clipped(_ values: [Double]) -> Path {
                let part = plot.fitted(values)
                return path(part.values, start: part.start, step: plot.energyStep)
            }
            if !plot.background.isEmpty {
                context.stroke(clipped(plot.background), with: .color(EDXSpectrumSeries.continuum.color),
                               style: StrokeStyle(lineWidth: lineWidth, dash: EDXSpectrumSeries.continuum.dash))
            }
            context.stroke(clipped(plot.model), with: .color(EDXSpectrumSeries.fit.color),
                           style: StrokeStyle(lineWidth: lineWidth, dash: EDXSpectrumSeries.fit.dash))
        }

        SpectrumLayerPlot.draw(layers, in: &context, rect: area, xRange: w, top: top, scale: .linear)

        // The picked elements' alpha lines: a dashed rule and the name, quantified ones in the primary colour.
        // Each label goes on the first of four rows where it clears the one before (measured, not estimated), so neighbouring lines at low
        // energy (Mg, Al, Si within 0.3 keV) stack instead of printing over each other; a label that fits no row is left to its rule and
        // to the Elements list.
        var rowEnds = [CGFloat](repeating: -.infinity, count: 4)
        for m in markers.sorted(by: { $0.energy < $1.energy }) where w.contains(m.energy) {
            let text = Text(m.label).font(.caption2).foregroundStyle(m.quantified ? .primary : .secondary)
            let width = context.resolve(text).measure(in: CGSize(width: 200, height: 20)).width
            let left = min(max(x(m.energy) - width / 2, area.minX), area.maxX - width)
            guard let row = rowEnds.firstIndex(where: { left >= $0 + 4 }) else { continue }
            rowEnds[row] = left + width
            var p = Path(); p.move(to: CGPoint(x: x(m.energy), y: area.minY + 10 + CGFloat(row) * 11)); p.addLine(to: CGPoint(x: x(m.energy), y: area.maxY))
            context.stroke(p, with: .color(m.quantified ? .primary.opacity(0.5) : .secondary.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            context.draw(text, at: CGPoint(x: left + width / 2, y: area.minY + 4 + CGFloat(row) * 11))
        }
        context.stroke(Path(area), with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
    }
}

extension EDXSpectrumView {
    /// The legend: a short sample of each curve, drawn as the curve is, and its name, left to right from `origin` (the row's
    /// vertical middle). Nothing is drawn when the whole legend would pass `limit`.
    fileprivate static func drawLegend(_ context: inout GraphicsContext, at origin: CGPoint, limit: CGFloat, lineWidth: CGFloat) {
        let sample: CGFloat = 16, gap: CGFloat = 4, spacing: CGFloat = 12
        let entries = EDXSpectrumSeries.allCases.map { series in
            (series, context.resolve(Text(series.title).font(.caption2).foregroundStyle(.secondary)))
        }
        let total = entries.reduce(CGFloat(0)) { sum, entry in
            sum + sample + gap + entry.1.measure(in: CGSize(width: 200, height: 20)).width + spacing
        } - spacing
        guard origin.x + total <= limit else { return }
        var x = origin.x
        for (series, text) in entries {
            var p = Path(); p.move(to: CGPoint(x: x, y: origin.y)); p.addLine(to: CGPoint(x: x + sample, y: origin.y))
            if series.isFilled {
                context.fill(Path(CGRect(x: x, y: origin.y, width: sample, height: 4)), with: .color(series.color.opacity(0.12)))
            }
            context.stroke(p, with: .color(series.color), style: StrokeStyle(lineWidth: lineWidth, dash: series.dash))
            x += sample + gap
            context.draw(text, at: CGPoint(x: x, y: origin.y), anchor: .leading)
            x += text.measure(in: CGSize(width: 200, height: 20)).width + spacing
        }
    }
}

/// The spectrum's drawing, with the window and the counts zoom as stored values (see the call site).
private struct EDXSpectrumCanvas: View {
    let window: ClosedRange<Double>
    let yZoom: Double
    let increasedContrast: Bool
    let spectrum: EDXSpectrumView

    var body: some View {
        Canvas { context, size in spectrum.draw(&context, size: size, window: window, yZoom: yZoom, increasedContrast: increasedContrast) }
    }
}
