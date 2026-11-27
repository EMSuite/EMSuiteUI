import SwiftUI

/// What the histogram's footer says about the data: the extremes and the mean of the finite values, in the pixels' own units.
public nonisolated struct HistogramStatistics: Sendable, Equatable {
    public var minimum: Float
    public var maximum: Float
    public var mean: Float

    public init(minimum: Float, maximum: Float, mean: Float) {
        self.minimum = minimum
        self.maximum = maximum
        self.mean = mean
    }
}

/// A pure drawing of an intensity histogram: the bars, two draggable contrast-window handles over dimmed tails, the data's
/// min · mean · max (always those words, always the data's own numbers), the window's two edges beneath them (click one to type
/// it), and a footer with the Log y-axis switch and, while the window is narrowed, Reset Range (EMSuiteUI#253). It counts
/// nothing and knows no app: the bins and the statistics come from the caller (computed once per image, off the main actor),
/// the window is two bindings, and the number text is a closure.
///
/// The window is held as FRACTIONS of the data range in [0, 1] (`rangeLo`, `rangeHi`), as a contrast window is applied to the
/// image; a caller that keeps raw values passes a Binding that maps them. The log toggle only scales the BAR HEIGHTS, so the two
/// interact freely: handle positions are intensity-axis fractions either way.
public struct HistogramChart: View {
    let counts: [Int]
    let statistics: HistogramStatistics?
    let rangeLo: Binding<Float>
    let rangeHi: Binding<Float>
    let scale: Float
    let valueText: (Float) -> String
    let reset: (() -> Void)?

    private static let barHeight: CGFloat = 100
    /// The handles' dark halo (the aperture handles' vocabulary): the bars are the accent colour, so an accent handle disappeared
    /// into them.
    private static let haloOpacity = 0.6

    // Owner decision (R26): linear counts by default — log counts on
    // startup would be unusual; log stays one toggle away.
    @State private var useLog = false
    /// Which window edge is being typed (true = low), nil when none.
    @State private var editingLow: Bool?
    /// Which handle the current drag is moving (nil between drags).
    @State private var draggingHiHandle: Bool?

    /// - `counts`: the bins, low to high; empty draws no bars.
    /// - `statistics`: nil when there is no finite value (no readouts).
    /// - `rangeLo`, `rangeHi`: the contrast window as fractions of the range.
    /// - `scale`: the value a pixel of 1.0 stands for (counts at the tile's maximum, say): the readouts show `value * scale` and
    ///   the window edges are typed in the same units. 1 keeps the pixels' own units.
    /// - `valueText`: the readouts' text for a RAW value (apply `scale` yourself); nil takes `defaultValueText`.
    /// - `reset`: what "Reset Range" does; nil sets the window to the full range.
    public init(counts: [Int], statistics: HistogramStatistics?, rangeLo: Binding<Float>, rangeHi: Binding<Float>,
                scale: Float = 1, valueText: ((Float) -> String)? = nil, reset: (() -> Void)? = nil) {
        self.counts = counts
        self.statistics = statistics
        self.rangeLo = rangeLo
        self.rangeHi = rangeHi
        self.scale = scale
        self.valueText = valueText ?? { HistogramChart.defaultValueText($0, scale: scale) }
        self.reset = reset
    }

    /// The footer's default text: `value * scale` in the reader's locale, no grouping; whole numbers from 1000 up (a 16-bit count
    /// prints exactly), else 4 significant digits ("0.1235"). Display only.
    public nonisolated static func defaultValueText(_ value: Float, scale: Float = 1, locale: Locale = .autoupdatingCurrent) -> String {
        let shown = Double(value) * Double(HistogramWindowRules.safeScale(scale))
        guard shown.isFinite else { return "—" }
        if abs(shown) >= 1000 {
            return shown.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0)))
        }
        return shown.formatted(.number.locale(locale).grouping(.never).precision(.significantDigits(1...4)))
    }

    private var isWindowed: Bool { rangeLo.wrappedValue > 0 || rangeHi.wrappedValue < 1 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                draw(context: context, size: size)
            }
            .frame(height: Self.barHeight)
            .overlay { rangeOverlay }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Intensity histogram")
            .accessibilityValue(histogramAccessibilityValue)
            .accessibilityRepresentation {
                VStack {
                    Slider(value: rangeLo, in: 0...max(0, rangeHi.wrappedValue - 0.01))
                        .accessibilityLabel("Lower contrast limit")
                        .accessibilityValue("\(Int(rangeLo.wrappedValue * 100)) percent")
                    Slider(value: rangeHi, in: min(1, rangeLo.wrappedValue + 0.01)...1)
                        .accessibilityLabel("Upper contrast limit")
                        .accessibilityValue("\(Int(rangeHi.wrappedValue * 100)) percent")
                }
            }

            if let statistics {
                // The data's extremes and mean, captioned the same in every room whatever the window (EMSuiteUI#253: the
                // captions used to turn into "low" / "high" while the window was narrowed, which read as two vocabularies).
                HStack {
                    readout(HistogramWindowRules.statisticsCaptions[0], statistics.minimum)
                    Spacer()
                    readout(HistogramWindowRules.statisticsCaptions[1], statistics.mean)
                    Spacer()
                    readout(HistogramWindowRules.statisticsCaptions[2], statistics.maximum)
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

                if statistics.maximum > statistics.minimum {
                    // The window's two edges, under the extremes they start at; a click types one.
                    HStack(alignment: .firstTextBaseline) {
                        edgeReadout(isLow: true, statistics: statistics)
                        Spacer()
                        Text(HistogramWindowRules.windowCaption).foregroundStyle(.tertiary)
                        Spacer()
                        edgeReadout(isLow: false, statistics: statistics)
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                }
            }

            // The footer, under the plot it changes (control-placement §5: "A log switch for the histogram sits in its
            // footer"). One line: the small Log y-axis switch leading, Reset Range trailing while the window is narrowed. As a
            // row of its own it read as a second "Log" beside the picture's (EMSuiteUI#253).
            HStack(spacing: 8) {
                Toggle(isOn: $useLog) {
                    Text(HistogramWindowRules.logSwitchTitle)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("histogram.log")
                Spacer(minLength: 0)
                if isWindowed {
                    Button("Reset Range") {
                        if let reset { reset() } else { rangeLo.wrappedValue = 0; rangeHi.wrappedValue = 1 }
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                    .help("Show the full range of values again")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var histogramAccessibilityValue: String {
        guard let statistics else { return "No finite pixel statistics" }
        return "minimum \(valueText(statistics.minimum)), mean \(valueText(statistics.mean)), maximum \(valueText(statistics.maximum))"
    }

    /// Dimmed excluded tails + two handle markers. Instead of tiny per-handle
    /// hit areas (which clip at the row edges, making the hi handle at x = w
    /// ungrabbable), the WHOLE histogram takes the drag and moves whichever
    /// handle is nearest to the touch point.
    private var rangeOverlay: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = geo.size.height
            let loX = CGFloat(rangeLo.wrappedValue) * w
            let hiX = CGFloat(rangeHi.wrappedValue) * w

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: max(loX, 0), height: h)
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: max(w - hiX, 0), height: h)
                    .offset(x: hiX)
                handleBar(x: min(max(loX, 1), w - 1), height: h)
                handleBar(x: min(max(hiX, 1), w - 1), height: h)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = Float(min(max(value.location.x / w, 0), 1))
                        if draggingHiHandle == nil {
                            draggingHiHandle =
                                abs(f - rangeHi.wrappedValue) < abs(f - rangeLo.wrappedValue)
                        }
                        if draggingHiHandle == true {
                            rangeHi.wrappedValue = max(f, rangeLo.wrappedValue + 0.01)
                        } else {
                            rangeLo.wrappedValue = min(f, rangeHi.wrappedValue - 0.01)
                        }
                    }
                    .onEnded { _ in draggingHiHandle = nil }
            )
        }
    }

    /// White on a dark halo, the aperture handles' vocabulary: the bars are the accent colour, so an accent handle disappeared into
    /// them.
    private func handleBar(x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(Self.haloOpacity))
            .frame(width: 4, height: height)
            .overlay { Rectangle().fill(Color.white).frame(width: 2, height: height) }
            .overlay(alignment: .top) {
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(Self.haloOpacity), lineWidth: 1))
                    .frame(width: 9, height: 9)
                    .offset(y: -4)
            }
            .position(x: x, y: height / 2)
            .allowsHitTesting(false)
    }

    /// The edge readout's spoken name: "Low limit" or "High limit", its value read after it.
    nonisolated static func edgeAccessibilityLabel(isLow: Bool) -> String { isLow ? "Low limit" : "High limit" }

    private func readout(_ label: String, _ value: Float) -> some View {
        VStack(spacing: 1) {
            Text(label).foregroundStyle(.tertiary)
            Text(valueText(value))
        }
    }

    /// One edge of the contrast window, in the readouts' units (the data's min or max while the window is full); a click
    /// turns it into a numeric field in the same units (Return or blur commits, Escape cancels). Shown only with a real span.
    @ViewBuilder
    private func edgeReadout(isLow: Bool, statistics: HistogramStatistics) -> some View {
        let own = isLow ? rangeLo : rangeHi
        let other = isLow ? rangeHi : rangeLo
        let edge = HistogramWindowRules.edge(fraction: own.wrappedValue,
                                             dataMin: statistics.minimum, dataMax: statistics.maximum)
        Group {
            if editingLow == isLow {
                edgeField(edge: edge, own: own, other: other, isLow: isLow, statistics: statistics)
            } else {
                Button {
                    editingLow = isLow
                } label: {
                    Text(valueText(edge))
                }
                .buttonStyle(.plain)
                .help("Click to type the window's \(isLow ? "low" : "high") value")
                // VoiceOver read the bare number ("0", "20109"): the limit's name, its value (Electron-Microscopy-Studio#1023).
                .accessibilityLabel(Self.edgeAccessibilityLabel(isLow: isLow))
                .accessibilityValue(valueText(edge))
                .accessibilityIdentifier(isLow ? "histogram.min" : "histogram.max")
            }
        }
    }

    private func edgeField(edge: Float, own: Binding<Float>, other: Binding<Float>, isLow: Bool,
                           statistics: HistogramStatistics) -> some View {
        let format: FloatingPointFormatStyle<Float> = scale > 1
            ? .number.precision(.fractionLength(0))
            : .number.precision(.significantDigits(1...6))
        return NumberEntryField(title: isLow ? "Window low" : "Window high",
                                value: edge * HistogramWindowRules.safeScale(scale), format: format,
                                focusOnAppear: true, onFinish: { editingLow = nil }) { typed in
            if let typed {
                own.wrappedValue = HistogramWindowRules.commit(
                    typed: typed, scale: scale, other: other.wrappedValue, isLow: isLow,
                    dataMin: statistics.minimum, dataMax: statistics.maximum)
            }
        }
        .labelsHidden()   // the title stays for accessibility; drawn beside the field it wrapped ("Win-dow high")
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .multilineTextAlignment(.trailing)
        .frame(width: NumericFieldMetrics.width)
        .accessibilityIdentifier(isLow ? "histogram.min.field" : "histogram.max.field")
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        guard !counts.isEmpty else { return }
        let maxCount = counts.max() ?? 0
        guard maxCount > 0 else {
            // Flat line for degenerate (all-equal) data.
            let y = size.height - 1
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                with: .color(.secondary),
                lineWidth: 1
            )
            return
        }

        let top = useLog ? log1p(Double(maxCount)) : Double(maxCount)
        let barWidth = size.width / CGFloat(counts.count)

        for (i, count) in counts.enumerated() {
            guard count > 0 else { continue }
            let value = useLog ? log1p(Double(count)) : Double(count)
            let h = CGFloat(value / top) * size.height
            let rect = CGRect(
                x: CGFloat(i) * barWidth,
                y: size.height - h,
                width: max(barWidth - 0.5, 0.5),
                height: h
            )
            context.fill(Path(rect), with: .color(.accentColor))
        }
    }
}

/// The window edge a typed value maps to — pure, so the rules are testable without a view. (The readouts' text is the caller's
/// formatter, or `HistogramChart.defaultValueText`.)
public nonisolated enum HistogramWindowRules {
    /// The captions over the data's three numbers, fixed whatever the window (EMSuiteUI#253).
    public static let statisticsCaptions = ["min", "mean", "max"]
    /// The word between the window's two edges.
    public static let windowCaption = "window"
    /// The footer switch's words: it scales the bars' heights, not the picture.
    public static let logSwitchTitle = "Log y-axis"

    /// A non-positive scale is meaningless; 1 stands in.
    public static func safeScale(_ scale: Float) -> Float { scale > 0 ? scale : 1 }

    /// The pixel value at a window fraction of the data range.
    public static func edge(fraction: Float, dataMin: Float, dataMax: Float) -> Float {
        dataMin + fraction * (dataMax - dataMin)
    }

    /// The window fraction a typed value (in `scale` units) stands for, clamped
    /// to 0...1 and kept 0.01 clear of the other edge. `dataMin`/`dataMax`
    /// default to 0...1 (pixels already normalised to the scale).
    public static func commit(typed: Float, scale: Float, other: Float, isLow: Bool,
                              dataMin: Float = 0, dataMax: Float = 1) -> Float {
        let span = dataMax - dataMin
        guard span > 0 else { return isLow ? 0 : 1 }
        let fraction = min(max((typed / safeScale(scale) - dataMin) / span, 0), 1)
        return isLow ? min(fraction, max(other - 0.01, 0))
                     : max(fraction, min(other + 0.01, 1))
    }
}
