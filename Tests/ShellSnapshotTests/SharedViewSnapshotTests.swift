// Snapshots of the shared views, in light and in dark (suite#137). They compare only on CI's macos-26 leg (SNAPSHOTS=1);
// elsewhere they skip. A new or changed picture fails the test and is attached to the pull request by CI; commit it under
// __Snapshots__/SharedViewSnapshotTests/ once it is reviewed (CONTRIBUTING.md, Snapshot tests).

import ShellControls
import ShellInspector
import ShellLayout
import ShellMetal
import ShellSnapshotTesting
import AppKit
import SwiftUI
import XCTest

nonisolated final class SharedViewSnapshotTests: XCTestCase {

    /// Draws `view` in both appearances and fails for each picture that is new or changed.
    @MainActor private func check<V: View>(_ name: String, size: CGSize, file: StaticString = #filePath, line: UInt = #line,
                                           @ViewBuilder _ view: () -> V) throws {
        try XCTSkipUnless(Snapshot.isEnabled, "snapshots are compared only where SNAPSHOTS=1 is set (CI's macos-26 leg)")
        let content = view()
        for appearance in SnapshotAppearance.allCases {
            let result = Snapshot.verify(content, named: name, size: size, appearance: appearance, testFile: file)
            if let failure = result.failure { XCTFail(failure, file: file, line: line) }
        }
    }

    @MainActor func testScaleBar() throws {
        try check("scale-bar", size: CGSize(width: 160, height: 40)) {
            ScaleBar(unitsPerPoint: 0.37, unitLabel: "nm").padding()
        }
    }

    @MainActor func testColorbars() throws {
        try check("colorbars", size: CGSize(width: 220, height: 150)) {
            VStack(alignment: .leading, spacing: 12) {
                Colorbar(colormap: .viridis, low: 0, high: 1250, unitLabel: "counts")
                Colorbar(colormap: .rdbu, low: -0.02, high: 0.02, unitLabel: "strain", marksZero: true)
                Colorbar(colormap: .gray, low: 0, high: 1, unitLabel: "a.u.", gamma: 0.5, showsMasked: true)
            }
            .padding()
        }
    }

    @MainActor func testInspectorSection() throws {
        try check("inspector-section", size: CGSize(width: 280, height: 220)) {
            InspectorSection("Calibration", status: "Read from file") {
                InspectorValueRow("Pixel size", "0.0999 nm⁻¹")
                InspectorValueRow("Camera length", "250 mm")
                InspectorValueRow("Source", "sha256:4f2a9c1e", mono: true)
                InspectorNote("Set from the gold ring standard.")
                InspectorWarning("Not quantitative: the pattern is saturated.")
            }
            .padding()
        }
    }

    @MainActor func testRunProgressBar() throws {
        try check("run-progress-bar", size: CGSize(width: 240, height: 60)) {
            VStack(spacing: 16) {
                RunProgressBar(progress: 0.4)
                RunProgressBar(progress: nil)
            }
            .padding()
        }
    }
}

/// The comparison itself, on planted pictures; runs everywhere (no window, no SNAPSHOTS).
nonisolated final class SnapshotComparisonTests: XCTestCase {

    /// A PNG of `width` x `height` pixels, all `gray` except `changed` pixels set to white.
    private static func png(width: Int = 100, height: Int = 50, gray: UInt8 = 120, changed: Int = 0, by step: UInt8 = 255) -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0 ..< width * height {
            let value = pixel < changed ? UInt8(min(255, Int(gray) + Int(step))) : gray
            bytes[pixel * 4] = value
            bytes[pixel * 4 + 1] = value
            bytes[pixel * 4 + 2] = value
            bytes[pixel * 4 + 3] = 255
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4, bitsPerPixel: 32)!
        bytes.withUnsafeBytes { source in
            rep.bitmapData!.update(from: source.bindMemory(to: UInt8.self).baseAddress!, count: source.count)
        }
        return rep.representation(using: .png, properties: [:])!
    }

    @MainActor func testTheSamePictureMatches() {
        XCTAssertNil(Snapshot.compare(Self.png(), Self.png()))
    }

    @MainActor func testSmallChannelNoiseMatches() {
        XCTAssertNil(Snapshot.compare(Self.png(changed: 5000, by: 6), Self.png()))
    }

    @MainActor func testAFewChangedPixelsMatchAndMoreDiffer() {
        XCTAssertNil(Snapshot.compare(Self.png(changed: 5), Self.png()))
        XCTAssertNotNil(Snapshot.compare(Self.png(changed: 6), Self.png()))
    }

    @MainActor func testAnotherSizeDiffers() {
        XCTAssertNotNil(Snapshot.compare(Self.png(width: 101), Self.png()))
    }

    @MainActor func testSkippedWithoutTheSwitch() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SNAPSHOTS"] == "1", "the switch is set here")
        let result = Snapshot.verify(Text("x"), named: "x", size: CGSize(width: 10, height: 10), appearance: .light)
        XCTAssertNil(result.failure)
        guard case .skipped = result else { return XCTFail("expected .skipped, got \(result)") }
    }
}
