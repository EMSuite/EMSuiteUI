import XCTest
@testable import ShellControls

/// Spec 2 lane F: the histogram's editable window edges, and the footer's default text.
nonisolated final class HistogramWindowRulesTests: XCTestCase {
    func testCommitDividesByScale() {
        XCTAssertEqual(HistogramWindowRules.commit(typed: 2060, scale: 4120, other: 1, isLow: true), 0.5, accuracy: 1e-6)
        XCTAssertEqual(HistogramWindowRules.commit(typed: 2060, scale: 4120, other: 0, isLow: false), 0.5, accuracy: 1e-6)
    }

    func testCommitClampsToUnitRange() {
        XCTAssertEqual(HistogramWindowRules.commit(typed: -50, scale: 4120, other: 1, isLow: true), 0)
        XCTAssertEqual(HistogramWindowRules.commit(typed: 9000, scale: 4120, other: 0, isLow: false), 1)
    }

    func testCommitKeepsTheEdgesOrdered() {
        // Low typed above the high edge: stays 0.01 below it.
        XCTAssertEqual(HistogramWindowRules.commit(typed: 4000, scale: 4120, other: 0.5, isLow: true), 0.49, accuracy: 1e-6)
        // High typed below the low edge: stays 0.01 above it.
        XCTAssertEqual(HistogramWindowRules.commit(typed: 100, scale: 4120, other: 0.5, isLow: false), 0.51, accuracy: 1e-6)
    }

    func testCommitMapsThroughTheDataRange() {
        // Data spans 0.2...0.8; the value 0.5 is the middle of the window range.
        XCTAssertEqual(HistogramWindowRules.commit(typed: 0.5, scale: 1, other: 1, isLow: true, dataMin: 0.2, dataMax: 0.8), 0.5, accuracy: 1e-6)
        XCTAssertEqual(HistogramWindowRules.edge(fraction: 0.5, dataMin: 0.2, dataMax: 0.8), 0.5, accuracy: 1e-6)
        XCTAssertEqual(HistogramWindowRules.edge(fraction: 0, dataMin: 0.2, dataMax: 0.8), 0.2, accuracy: 1e-6)
        XCTAssertEqual(HistogramWindowRules.edge(fraction: 1, dataMin: 0.2, dataMax: 0.8), 0.8, accuracy: 1e-6)
    }

    func testNonPositiveScaleIsTreatedAsOne() {
        XCTAssertEqual(HistogramWindowRules.commit(typed: 0.3, scale: 0, other: 1, isLow: true), 0.3, accuracy: 1e-6)
        XCTAssertEqual(HistogramWindowRules.safeScale(-3), 1)
        XCTAssertEqual(HistogramWindowRules.safeScale(0), 1)
        XCTAssertEqual(HistogramWindowRules.safeScale(4120), 4120)
    }

    /// The data's three numbers keep their captions whatever the window (EMSuiteUI#253). Red before: "min" / "max" turned into
    /// "low" / "high" once the window was narrowed, which read as an inconsistency between rooms.
    func testTheStatisticsCaptionsAreFixed() {
        XCTAssertEqual(HistogramWindowRules.statisticsCaptions, ["min", "mean", "max"])
        XCTAssertEqual(HistogramWindowRules.windowCaption, "window")
    }
}

/// The footer showed seven significant digits (macTEM) and "1.23e+03" (mac4DSTEM). The default is four significant digits, whole
/// numbers from 1000, in the reader's decimal mark, never grouped.
nonisolated final class HistogramDefaultTextTests: XCTestCase {
    private let en = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")

    func testFourSignificantDigitsBelowAThousand() {
        XCTAssertEqual(HistogramChart.defaultValueText(0.123456, locale: en), "0.1235")
        XCTAssertEqual(HistogramChart.defaultValueText(0.123456, locale: de), "0,1235")
        XCTAssertEqual(HistogramChart.defaultValueText(12.3456, locale: en), "12.35")
        XCTAssertEqual(HistogramChart.defaultValueText(0, locale: en), "0")
        XCTAssertEqual(HistogramChart.defaultValueText(-0.5, locale: en), "-0.5")
    }

    func testWholeNumbersFromAThousandUpAreNeverRoundedIntoTheIntegerPart() {
        XCTAssertEqual(HistogramChart.defaultValueText(65535, locale: en), "65535")
        XCTAssertEqual(HistogramChart.defaultValueText(4120, locale: de), "4120")
        XCTAssertEqual(HistogramChart.defaultValueText(1234.5678, locale: en), "1235")
    }

    func testScaleAppliesAndANonFiniteValueIsADash() {
        XCTAssertEqual(HistogramChart.defaultValueText(0.5, scale: 4120, locale: en), "2060")
        XCTAssertEqual(HistogramChart.defaultValueText(0.5, scale: -3, locale: en), "0.5", "a non-positive scale is 1")
        XCTAssertEqual(HistogramChart.defaultValueText(.nan, locale: en), "\u{2014}")
    }
}

/// VoiceOver names each contrast-limit readout and reads its value after the name; the switches of the agent door's Settings section
/// carry their row's words (Electron-Microscopy-Studio#1023). Red before: the readouts were announced as a bare "0" or "20109", the
/// switches as a bare switch.
nonisolated final class HistogramAccessibilityTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testTheLimitReadoutsHaveANameAndAValue() throws {
        XCTAssertEqual(HistogramChart.edgeAccessibilityLabel(isLow: true), "Low limit")
        XCTAssertEqual(HistogramChart.edgeAccessibilityLabel(isLow: false), "High limit")
        let chart = try source("Sources/ShellControls/HistogramChart.swift")
        XCTAssertTrue(chart.contains(".accessibilityLabel(Self.edgeAccessibilityLabel(isLow: isLow))\n                .accessibilityValue(valueText(edge))"))
    }

    /// The log switch sits in the footer line beside Reset Range (control-placement §5, EMSuiteUI#253). Red before: it was a
    /// row of its own, "Log y-axis" in a label and a switch, and Reset Range a line beneath it.
    func testTheLogSwitchSitsInTheFooterBesideResetRange() throws {
        let chart = try source("Sources/ShellControls/HistogramChart.swift")
        XCTAssertEqual(HistogramWindowRules.logSwitchTitle, "Log y-axis")
        let footer = try XCTUnwrap(chart.range(of: "HStack(spacing: 8) {\n                Toggle(isOn: $useLog)"))
        let reset = try XCTUnwrap(chart.range(of: "Button(\"Reset Range\")"))
        let between = String(chart[footer.upperBound..<reset.lowerBound])
        XCTAssertFalse(between.contains("HStack"), "Reset Range is on the footer line, not a line of its own")
        XCTAssertTrue(between.contains(".controlSize(.mini)"))
        XCTAssertFalse(chart.contains("Text(\"Log y-axis\")"), "no separate label row")
    }

    func testTheAgentSwitchesAreLabelled() throws {
        let section = try source("Sources/ShellAgentDoor/AgentDoorSettingsSection.swift")
        XCTAssertTrue(section.contains(".accessibilityLabel(\"Let agents on this Mac look at open windows\")"))
        XCTAssertTrue(section.contains(".accessibilityLabel(\"Let agents run analyses\")"))
    }
}
