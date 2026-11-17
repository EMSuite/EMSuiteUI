//
//  ProfileThinningTests.swift
//  The profile chart draws at most 2 × buckets marks for a long line and keeps every run's extremes (EMSuite/EMSuiteUI#129): one LineMark per
//  sample made each redraw cost the line's length.
//

import XCTest
@testable import ShellSpectroscopy

nonisolated final class ProfileThinningTests: XCTestCase {

    private func series(_ values: [Double]) -> ProfileSeries {
        ProfileSeries(id: "a", name: "Mg", color: RegionColor(red: 1, green: 0, blue: 0), values: values, spacing: 0.5)
    }

    func testAShortProfileIsDrawnSampleBySample() {
        let values = (0..<1000).map { Double($0 % 7) }
        let points = series(values).plotted(buckets: 512)
        XCTAssertEqual(points.map(\.index), Array(0..<1000))
        XCTAssertEqual(points.map(\.value), values)
    }

    func testALongProfileIsThinnedAndKeepsANarrowPeakAndDip() {
        var values = (0..<20_000).map { sin(Double($0) / 300) }
        values[7_777] = 50
        values[12_345] = -50
        let points = series(values).plotted(buckets: 512)
        XCTAssertLessThanOrEqual(points.count, 1024)
        XCTAssertTrue(points.contains(ProfileSeries.Point(index: 7_777, value: 50)))
        XCTAssertTrue(points.contains(ProfileSeries.Point(index: 12_345, value: -50)))
        XCTAssertEqual(points.map(\.index), points.map(\.index).sorted(), "the points stay in their order along the line")
        XCTAssertEqual(Set(points.map(\.index)).count, points.count, "no sample twice")
        XCTAssertEqual(points.first?.index, 0)
    }

    func testAThinnedRunSkipsNaN() {
        var values = [Double](repeating: 1, count: 4_000)
        for i in 0..<8 { values[i] = .nan }
        let points = series(values).plotted(buckets: 512)
        XCTAssertFalse(points.contains { $0.value.isNaN })
    }
}
