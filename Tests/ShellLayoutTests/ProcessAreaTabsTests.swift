// The process area's tabs style (EMSuite/Electron-Microscopy-Studio#1112): a room's tables are tabs of the bottom area
// beside Output, one at full width, with one infobar toggle. The panes style stays the default.

import Foundation
import SwiftUI
import XCTest
@testable import ShellLayout

nonisolated final class ProcessAreaTabsTests: XCTestCase {

    // MARK: - Which tab is drawn

    /// Mutation: return `selected` unconditionally -> a selection the room did not register draws nothing.
    func testTheShownTabIsTheSelectionElseOutputElseTheFirst() {
        let lines = ProcessPaneID("lines")
        let pins = ProcessPaneID("pins")
        XCTAssertEqual(ProcessAreaLayout.shownTab(selected: lines, in: [.output, lines, pins]), lines)
        XCTAssertEqual(ProcessAreaLayout.shownTab(selected: .output, in: [.output, lines]), .output)
        XCTAssertEqual(ProcessAreaLayout.shownTab(selected: pins, in: [.output, lines]), .output,
                       "a selection left from another room falls back to Output")
        XCTAssertEqual(ProcessAreaLayout.shownTab(selected: .output, in: [lines, pins]), lines,
                       "no Output registered: the first")
        XCTAssertNil(ProcessAreaLayout.shownTab(selected: .output, in: []))
    }

    // MARK: - The selection

    @MainActor func testTheSelectionStartsAtOutput() {
        XCTAssertEqual(PanelNavigation().selectedProcessPane, .output)
    }

    /// Mutation: drop the `showProcessArea = true` line -> choosing a tab while the area is shut shows nothing.
    @MainActor func testSelectingATabOpensAShutArea() {
        let lines = ProcessPaneID("lines")
        let navigation = PanelNavigation()
        navigation.lastProcessFraction = 0.4
        XCTAssertFalse(navigation.showProcessArea)
        navigation.selectProcessPane(lines)
        XCTAssertEqual(navigation.selectedProcessPane, lines)
        XCTAssertTrue(navigation.showProcessArea)
        XCTAssertEqual(navigation.processFraction, 0.4, "opens at the last height")
    }

    /// Mutation: set `processFraction` to the ideal in `selectProcessPane` -> red.
    @MainActor func testSelectingATabKeepsAnOpenAreasHeight() {
        let navigation = PanelNavigation()
        navigation.processFraction = 0.55
        navigation.selectProcessPane(ProcessPaneID("lines"))
        XCTAssertEqual(navigation.processFraction, 0.55)
        navigation.selectProcessPane(.output)
        XCTAssertEqual(navigation.selectedProcessPane, .output)
        XCTAssertEqual(navigation.processFraction, 0.55)
    }

    // MARK: - The column

    /// The style is opt-in: a column built as before is the side-by-side panes (4DSTEM Studio's Output and Lineage).
    @MainActor func testTheDefaultStyleIsPanes() {
        let column = WorkspaceColumn(
            navigation: PanelNavigation(), tabs: [], hasDocument: true, statusText: "", isRunning: false
        ) {
            EmptyView()
        } run: {
            EmptyView()
        } glance: {
            EmptyView()
        }
        XCTAssertEqual(column.processAreaStyle, .panes)

        let tabbed = WorkspaceColumn(
            navigation: PanelNavigation(), tabs: [], processAreaStyle: .tabs, hasDocument: true, statusText: "",
            isRunning: false
        ) {
            EmptyView()
        } run: {
            EmptyView()
        } glance: {
            EmptyView()
        }
        XCTAssertEqual(tabbed.processAreaStyle, .tabs)
    }

    /// In tabs style the infobar carries only the area's toggle: the per-pane toggles are drawn behind the panes check
    /// and nowhere else. Red before: they were drawn for every registered pane in every column.
    func testTheTabsStyleDrawsNoPerPaneToggles() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShellLayout/Chrome/WorkspaceColumn.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let infobar = try XCTUnwrap(text.components(separatedBy: "struct Infobar<").last?
            .components(separatedBy: "public struct InfobarRunReadout").first)
        XCTAssertTrue(infobar.contains("if processAreaStyle == .panes { paneToggles }"))
        XCTAssertEqual(infobar.components(separatedBy: "paneToggles").count - 1, 2, "declared once, drawn once, behind the check")
        XCTAssertEqual(text.components(separatedBy: "paneBinding(tab.id)").count - 1, 1, "only the per-pane toggles use it")
        XCTAssertTrue(infobar.contains("Toggle(isOn: processAreaToggleBinding)"), "the area's toggle stays in both styles")
    }

    /// The tabs header is the native segmented picker, labelled for VoiceOver and the UI tests.
    func testTheTabsHeaderIsASegmentedPicker() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShellLayout/Chrome/WorkspaceColumn.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let header = try XCTUnwrap(text.components(separatedBy: "private var tabHeader: some View").last?
            .components(separatedBy: "private var tabSelection").first)
        XCTAssertTrue(header.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(header.contains(".accessibilityLabel(\"Bottom area\")"))
        XCTAssertTrue(header.contains(".accessibilityIdentifier(\"process.tabs\")"))
        XCTAssertTrue(header.contains(".frame(height: LayoutPolicy.paneHeaderHeight)"))
    }
}
