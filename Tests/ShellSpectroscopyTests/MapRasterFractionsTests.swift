//
//  MapRasterFractionsTests.swift
//  The map's display fractions are made for the whole map in Accelerate passes (MacEMUI#129, D16), not one `pow` per pixel: they equal the
//  per-pixel `MapAdjustment.apply(v / top clamped)` within float rounding, for windows, gammas, negatives, NaN and infinities, and a value
//  that is not finite stays 0. Red before: no `MapRaster.fractions`.
//

import XCTest
@testable import ShellSpectroscopy

nonisolated final class MapRasterFractionsTests: XCTestCase {
    private func perPixel(_ values: [Double], top: Double, _ adjustment: MapAdjustment) -> [Double] {
        values.map { top > 0 && $0.isFinite ? adjustment.apply(min(max($0 / top, 0), 1)) : 0 }
    }

    func testTheWholeMapPassEqualsTheOnePixelForm() {
        var generator = SystemRandomNumberGenerator()
        var values = (0..<4096).map { _ in Double.random(in: -20...120, using: &generator) }
        values += [0, 100, .nan, .infinity, -.infinity, -0.0, 1e-300]
        let adjustments = [MapAdjustment(), MapAdjustment(low: 0.1, high: 0.8, gamma: 1), MapAdjustment(low: 0, high: 1, gamma: 0.45),
                           MapAdjustment(low: 0.2, high: 0.6, gamma: 2.2), MapAdjustment(low: 0.5, high: 0.5, gamma: 1)]
        for adjustment in adjustments {
            for top in [100.0, 37.5] {
                let fast = MapRaster.fractions(values, top: top, adjustment: adjustment)
                let slow = perPixel(values, top: top, adjustment)
                XCTAssertEqual(fast.count, slow.count)
                for (a, b) in zip(fast, slow) { XCTAssertEqual(a, b, accuracy: 1e-12, "\(adjustment)") }
            }
        }
    }

    func testNothingToScaleIsBlack() {
        XCTAssertEqual(MapRaster.fractions([1, 2, .nan], top: 0, adjustment: MapAdjustment()), [0, 0, 0])
        XCTAssertEqual(MapRaster.fractions([], top: 5, adjustment: MapAdjustment()), [])
        XCTAssertEqual(MapRaster.fractions([.nan, .infinity, 5], top: 5, adjustment: MapAdjustment(low: 0, high: 1, gamma: 0.5)), [0, 0, 1])
    }
}
