import AppKit
import SwiftUI
import XCTest
@testable import ShellLayout

/// The memory glance never reports a minimum narrower than its icon (#139): the infobar sizes the run slot from that minimum, so a
/// floor under the icon put the icon beneath the run's Cancel at a narrow window.
nonisolated final class InfobarGlanceMinimumTests: XCTestCase {
    @MainActor private func width<V: View>(_ view: V, proposed: CGFloat) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: proposed, height: 100)).width
    }

    /// Mutation: the glance's `minWidth` back to `compressibleSlotMinimum` -> red (it reports 0 at a zero proposal).
    @MainActor func testTheGlanceKeepsRoomForItsIcon() {
        let icon = width(Image(systemName: "memorychip").font(.callout).fixedSize(), proposed: 10_000)
        XCTAssertGreaterThan(icon, 0)
        let squeezed = width(InfobarGlance { "Apple M5 Pro · 120 MB · streaming" }, proposed: 0)
        XCTAssertGreaterThanOrEqual(squeezed, icon)
        XCTAssertGreaterThanOrEqual(LayoutPolicy.statusGlanceMinimumWidth, icon)
    }
}

/// The glance shows the longest line that fits whole, never a figure cut mid-number (macEMSuite/macEM#726: a wide inspector left
/// "1(" of "1.2 GB"): the fallbacks drop the trailing facts, then show the chip alone. Red before: one truncating `Text`.
nonisolated final class InfobarGlanceWholeFigureTests: XCTestCase {
    func testTheFallbacksDropWholeFactsThenTheText() {
        XCTAssertEqual(OperationMetricsFormat.runLineFallbacks("1.2 GB"), ["1.2 GB", ""])
        XCTAssertEqual(OperationMetricsFormat.runLineFallbacks("1.4 GB · resident"), ["1.4 GB · resident", "1.4 GB", ""])
    }

    func testTheGlanceDrawsOnlyWholeCandidates() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShellLayout/Chrome/WorkspaceColumn.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let glance = try XCTUnwrap(text.components(separatedBy: "public struct InfobarGlance").last)
        XCTAssertTrue(glance.contains("ForEach(OperationMetricsFormat.runLineFallbacks(full)"))
        XCTAssertFalse(glance.contains(".truncationMode(.tail)"), "no cut figure")
    }
}
