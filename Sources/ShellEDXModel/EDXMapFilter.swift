// The display filter of the quantified maps (wt%, at%, thickness), the kernel mac4DSTEM's Filter row offers: a 3 × 3 average (the default) or a
// Gaussian of σ 1 px, from ImagoKit's `SeparableFilters`. It is applied to the values a tile DRAWS, never to the numbers: the status-line readout, the
// exports and the results use the raw values. A pixel the kit could not make (NaN) is skipped by the kernel (the average of its finite neighbours is
// taken, normalised by the finite weights) and stays NaN itself, drawn as the scale's bottom. The colour scale of a filtered map is a display range, the
// 1st to the 99th percentile of the raw map.
import Foundation
import ImagoFilters
import os

package nonisolated enum EDXMapFilter: String, CaseIterable, Identifiable, Sendable {
    case off, mean3x3, gaussian1px

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .mean3x3: "3 × 3 average"
        case .gaussian1px: "Gaussian σ 1 px"
        }
    }

    /// The kernel as a tile's tag names it.
    package var isOn: Bool { self != .off }

    /// `values` (row-major, `width` × `height`) through the kernel; unchanged when off or when the shape is wrong.
    package func apply(_ values: [Double], width: Int, height: Int) -> [Double] {
        guard isOn, width > 0, height > 0, values.count == width * height else { return values }
        let data = values.map { $0.isFinite ? $0 : 0 }, mask = values.map { $0.isFinite ? 1.0 : 0.0 }
        func smooth(_ a: [Double]) -> [Double]? {
            switch self {
            case .off: a
            case .mean3x3: try? SeparableFilters.uniformFilter(a, rows: height, columns: width, size: (row: 3, column: 3))
            case .gaussian1px: try? SeparableFilters.gaussianFilter(a, rows: height, columns: width, sigma: (row: 1, column: 1))
            }
        }
        guard let num = smooth(data), let den = smooth(mask) else { return values }
        return values.indices.map { values[$0].isFinite && den[$0] > 1e-12 ? num[$0] / den[$0] : .nan }
    }

    /// The `low` to `high` percentiles (fractions, linear between ranks as NumPy does) of the finite values; nil when there are none or no span.
    package static func displayRange(of values: [Double], low: Double = 0.01, high: Double = 0.99) -> ClosedRange<Double>? {
        let sorted = values.filter(\.isFinite).sorted()
        guard let first = sorted.first, let last = sorted.last, last > first else { return nil }
        func percentile(_ q: Double) -> Double {
            let position = q * Double(sorted.count - 1), i = Int(position.rounded(.down)), j = min(i + 1, sorted.count - 1)
            return sorted[i] + (sorted[j] - sorted[i]) * (position - Double(i))
        }
        let lo = percentile(low), hi = percentile(high)
        return hi > lo ? lo...hi : first...last
    }
}

/// The display-filtered values of each map tile and the percentile window of its raw values, made once per tile picture (MacEMUI#158).
/// A tile's picture is made again on every contrast or gamma tick, and the filter and the percentile sort ran again each time (twice a
/// map for a colour mix) though neither depends on the window. Kept by the session, one entry per map symbol: a newer version or another
/// filter replaces it, so what is held is at most one filtered copy of each shown map. Safe from any thread (the pictures are made off
/// the main actor); the work runs outside the lock, so two tiles never wait on each other's filter.
package nonisolated final class EDXFilteredMaps: Sendable {
    package struct Result: Sendable, Equatable {
        /// The values through the filter (the values themselves with the filter off).
        package var values: [Double]
        /// The 1st to 99th percentile of the raw values, with the filter on; nil with it off or with no span.
        package var displayRange: ClosedRange<Double>?

        package init(values: [Double], displayRange: ClosedRange<Double>?) { self.values = values; self.displayRange = displayRange }
    }

    private struct Entry: Sendable {
        var version: Int
        var filter: EDXMapFilter
        var count: Int
        var result: Result
    }

    private let entries = OSAllocatedUnfairLock(initialState: [String: Entry]())
    private let computed = OSAllocatedUnfairLock(initialState: 0)

    package init() {}

    /// How many times a result was made rather than found (tests).
    package var computeCount: Int { computed.withLock { $0 } }

    /// The filtered values and window of map `symbol` at `version`, made from `values` only when this symbol, version and filter were
    /// not asked before. With the filter off nothing is kept: the values are drawn as they are.
    package func result(symbol: String, version: Int, filter: EDXMapFilter, values: [Double], width: Int, height: Int) -> Result {
        guard filter.isOn else { return Result(values: values, displayRange: nil) }
        if let hit = entries.withLock({ entries -> Result? in
            guard let e = entries[symbol], e.version == version, e.filter == filter, e.count == values.count else { return nil }
            return e.result
        }) { return hit }
        let result = Result(values: filter.apply(values, width: width, height: height), displayRange: EDXMapFilter.displayRange(of: values))
        computed.withLock { $0 += 1 }
        entries.withLock { $0[symbol] = Entry(version: version, filter: filter, count: values.count, result: result) }
        return result
    }
}
