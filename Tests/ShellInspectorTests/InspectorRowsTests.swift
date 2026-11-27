import SwiftUI
import XCTest
@testable import ShellInspector
import ShellLayout

/// `AdjustmentSlider.clamp(_:to:)` — the one piece of the inspector's
/// Lightroom-style slider row that is not a view and can be tested without
/// hosting one. It is the sole place a typed `TextField` value can land
/// outside the slider's own `range` before it reaches the bound `value`.
nonisolated final class InspectorRowsTests: XCTestCase {
    @MainActor func testClampLeavesAValueInsideRangeUnchanged() {
        XCTAssertEqual(AdjustmentSlider.clamp(0.5, to: 0.2...3.0), 0.5)
    }

    @MainActor func testClampPullsAValueBelowRangeUpToTheLowerBound() {
        XCTAssertEqual(AdjustmentSlider.clamp(-4, to: 0.2...3.0), 0.2)
    }

    @MainActor func testClampPullsAValueAboveRangeDownToTheUpperBound() {
        XCTAssertEqual(AdjustmentSlider.clamp(99, to: 0.2...3.0), 3.0)
    }

    /// VoiceOver's increment and decrement on the combined adjustment row: one step, else a tenth of the range,
    /// never past either end. Red under: `nudged` ignoring `step`, not clamping, or stepping by the whole range.
    @MainActor func testAnAccessibilityNudgeMovesOneStepOrATenthOfTheRangeWithinIt() {
        XCTAssertEqual(AdjustmentSlider.nudged(1, up: true, step: 0.5, in: 0...3), 1.5)
        XCTAssertEqual(AdjustmentSlider.nudged(1, up: false, step: 0.5, in: 0...3), 0.5)
        XCTAssertEqual(AdjustmentSlider.nudged(1, up: true, step: nil, in: 0...3), 1.3, accuracy: 1e-12)
        XCTAssertEqual(AdjustmentSlider.nudged(2.9, up: true, step: 0.5, in: 0...3), 3)
        XCTAssertEqual(AdjustmentSlider.nudged(0.1, up: false, step: nil, in: 0...3), 0)
        XCTAssertEqual(AdjustmentSlider.nudged(1, up: true, step: 0, in: 0...3), 1.3, accuracy: 1e-12, "a zero step is no step")
    }

    @MainActor func testClampAtEitherBoundReturnsThatBoundExactly() {
        XCTAssertEqual(AdjustmentSlider.clamp(0.2, to: 0.2...3.0), 0.2)
        XCTAssertEqual(AdjustmentSlider.clamp(3.0, to: 0.2...3.0), 3.0)
    }
}

/// `InspectorSection.sceneStorageKey(scope:title:)` — the other piece of the
/// inspector vocabulary that is pure and testable without hosting a view.
/// Two sections that share a title (F1: "Dataset" in the Info tab and
/// "Dataset" among the Settings tab's own actions) must resolve to two
/// different `@SceneStorage` keys once each is given its own `inspectorScope`,
/// or their expansion states collapse together.
nonisolated final class InspectorSectionScopeKeyTests: XCTestCase {
    @MainActor func testTheSameTitleUnderTwoScopesYieldsTwoDifferentKeys() {
        let infoKey = InspectorSection<EmptyView>.sceneStorageKey(scope: "info", title: "Dataset")
        let settingsKey = InspectorSection<EmptyView>.sceneStorageKey(scope: "settings", title: "Dataset")
        XCTAssertNotEqual(infoKey, settingsKey)
    }

    @MainActor func testTheKeyEmbedsScopeAndTitleInOrder() {
        XCTAssertEqual(
            InspectorSection<EmptyView>.sceneStorageKey(scope: "settings.map", title: "Result"),
            "inspector.section.settings.map.Result"
        )
    }
}

/// `InspectorMetrics` repeats numbers the apps read from `LayoutPolicy` (ShellInspector cannot import ShellLayout); the two must not drift.
nonisolated final class InspectorMetricsConsistencyTests: XCTestCase {
    @MainActor func testTheInspectorsNumbersAreLayoutPolicys() {
        XCTAssertEqual(InspectorMetrics.rowSpacing, LayoutPolicy.inspectorRowSpacing)
        XCTAssertEqual(InspectorMetrics.adjustmentValueWidth, LayoutPolicy.adjustmentValueWidth)
        XCTAssertEqual(InspectorMetrics.numericFieldWidth, LayoutPolicy.numericFieldWidth)
    }
}

/// The action row's one layout (MacEMUI#158): buttons side by side at equal shares while their ideal widths fit, a wider button keeping
/// its own width, else stacked (nil). One layout over the same buttons keeps a popover a button owns open when the row flips.
nonisolated final class InspectorActionRowLayoutTests: XCTestCase {
    @MainActor func testEqualSharesWhenEveryButtonFitsItsShare() {
        XCTAssertEqual(InspectorActionRowLayout.rowWidths(ideal: [40, 60], width: 206, spacing: 6), [100, 100])
    }

    @MainActor func testAWideButtonKeepsItsIdealWidth() {
        XCTAssertEqual(InspectorActionRowLayout.rowWidths(ideal: [30, 150, 20], width: 252, spacing: 6), [45, 150, 45])
    }

    @MainActor func testTooWideStacks() {
        XCTAssertNil(InspectorActionRowLayout.rowWidths(ideal: [100, 100], width: 205, spacing: 6))
        XCTAssertEqual(InspectorActionRowLayout.rowWidths(ideal: [100, 100], width: 206, spacing: 6), [100, 100])
    }

    @MainActor func testNoWidthOfferedIsTheIdealRow() {
        XCTAssertEqual(InspectorActionRowLayout.rowWidths(ideal: [40, 60], width: nil, spacing: 6), [40, 60])
        XCTAssertEqual(InspectorActionRowLayout.rowWidths(ideal: [], width: 100, spacing: 6), [])
    }
}

/// One on/off row for both apps (control-placement §3, EMSuiteUI#253): the title once, at the leading edge; a switch with its
/// label hidden; the title its spoken name. Red before: there was no such row, and the apps drew `Aperture ☐ Objective aperture`.
nonisolated final class InspectorSwitchRowTests: XCTestCase {
    @MainActor func testTheRowKeepsItsTitle() {
        XCTAssertEqual(InspectorSwitchRow("Frozen phonons", isOn: .constant(true)).title, "Frozen phonons")
    }

    func testTheSwitchIsASwitchWithItsLabelHiddenAndTheTitleSpoken() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let rows = try String(contentsOf: root.appendingPathComponent("Sources/ShellInspector/InspectorRows.swift"), encoding: .utf8)
        let expected = [
            "        InspectorRow(title) {",
            "            Toggle(title, isOn: isOn)",
            "                .toggleStyle(.switch)",
            "                .labelsHidden()",
            "                .accessibilityLabel(title)",
        ].joined(separator: "\n")
        XCTAssertTrue(rows.contains(expected))
    }
}
