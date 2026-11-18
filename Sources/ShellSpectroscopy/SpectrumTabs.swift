//
//  SpectrumTabs.swift
//  Role: the profile view of a spectroscopy room's lower block (design 2026-10-22 §2.2): the values along a line drawn on a map, as a chart. The room
//        supplies the series; the chart is shared.
//

import SwiftUI
import Charts

/// One profile along a line: a value per sample, `spacing` apart (in `unit`, e.g. nm, or pixels when the scan is uncalibrated).
public nonisolated struct ProfileSeries: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var color: RegionColor
    public var values: [Double]
    public var spacing: Double

    public init(id: String, name: String, color: RegionColor, values: [Double], spacing: Double) {
        self.id = id; self.name = name; self.color = color; self.values = values; self.spacing = spacing
    }

    /// The distance of sample `i` from the line's start.
    public func distance(of i: Int) -> Double { Double(i) * spacing }

    /// The line's length in `spacing` units: the distance of the last sample.
    public var length: Double { values.isEmpty ? 0 : distance(of: values.count - 1) }

    /// One plotted point: the sample's index and value.
    public struct Point: Equatable, Sendable {
        public var index: Int
        public var value: Double
    }

    /// The samples the chart draws: every sample when there are at most `2 × buckets`, otherwise the lowest and highest sample of each of
    /// `buckets` equal runs, in their order along the line (min-max decimation, as `SpectrumLayerPlot.columns` thins a spectrum), so a
    /// narrow peak or dip is never dropped and a long line costs at most `2 × buckets` marks. NaN samples are skipped in a thinned run.
    public func plotted(buckets: Int = 512) -> [Point] {
        let n = values.count
        guard buckets > 0, n > 2 * buckets else { return values.enumerated().map { Point(index: $0.offset, value: $0.element) } }
        var out: [Point] = []
        out.reserveCapacity(2 * buckets)
        for k in 0..<buckets {
            let from = k * n / buckets, to = (k + 1) * n / buckets   // [from, to)
            var lo: Int?, hi: Int?
            for i in from..<to where !values[i].isNaN {
                if lo.map({ values[i] < values[$0] }) ?? true { lo = i }
                if hi.map({ values[i] > values[$0] }) ?? true { hi = i }
            }
            guard let lo, let hi else { continue }
            for i in lo == hi ? [lo] : [min(lo, hi), max(lo, hi)] { out.append(Point(index: i, value: values[i])) }
        }
        return out
    }
}

/// The profile along a line: one coloured line per series (one per element, say), distance on x. `pointerDistance` marks where the pointer is on the map's line.
public struct ProfileChart: View {
    private let series: [ProfileSeries]
    private let unit: String
    private let valueTitle: String
    private let pointerDistance: Double?

    public init(series: [ProfileSeries], unit: String, valueTitle: String = "Value", pointerDistance: Double? = nil) {
        self.series = series
        self.unit = unit
        self.valueTitle = valueTitle
        self.pointerDistance = pointerDistance
    }

    public var body: some View {
        if series.allSatisfy({ $0.values.isEmpty }) {
            ContentUnavailableView("No profile", systemImage: "chart.xyaxis.line",
                                   description: Text("Draw a line on a map to see the profile along it."))
                .accessibilityIdentifier("profile.empty")
        } else {
            Chart {
                ForEach(series) { s in
                    // A long line is thinned to its per-run extremes: one mark per sample made every redraw cost the line's length.
                    ForEach(s.plotted(), id: \.index) { p in
                        LineMark(x: .value("Distance", s.distance(of: p.index)), y: .value(valueTitle, p.value), series: .value("Series", s.name))
                            .foregroundStyle(s.color.color)
                            .interpolationMethod(.linear)
                    }
                }
                if let pointerDistance {
                    RuleMark(x: .value("Pointer", pointerDistance)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                }
            }
            .chartXAxisLabel("Distance (\(unit))")
            .chartYAxisLabel(valueTitle)
            .chartLegend(.hidden)
            // On macOS a Chart reaches the accessibility tree as a group of its x bins and drops a label or value set on it; one element that
            // ignores the marks carries the summary (EMSuite/EMSuiteUI#68).
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("profile.chart")
            .accessibilityLabel("Profile along the line")
            .accessibilityValue(Self.summary(series, unit: unit, valueTitle: valueTitle))
        }
    }

    /// What VoiceOver reads: the axes with their units, then each series with its range.
    nonisolated static func summary(_ series: [ProfileSeries], unit: String, valueTitle: String = "Value") -> String {
        let ranges = series.compactMap { s -> String? in
            guard let lo = s.values.min(), let hi = s.values.max() else { return nil }
            return "\(s.name): \(lo.formatted(.number.precision(.significantDigits(1...3)))) to \(hi.formatted(.number.precision(.significantDigits(1...3)))) over \(s.length.formatted(.number.precision(.significantDigits(1...3)))) \(unit)"
        }
        return "\(valueTitle) against distance (\(unit)). " + ranges.joined(separator: "; ")
    }
}
