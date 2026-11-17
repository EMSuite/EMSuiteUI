// The rooms list to accessibility (EMSuiteUI#131): with the list's selection handed to `WorkspaceRoomsSection`, an available room row
// is a button whose press chooses the room, and an unavailable one is left alone. Without it the rows are as before. The press is
// driven twice: through `choose` (the action's one body) and through the hosted list's own accessibility element, as VoiceOver and
// an AX client press it.

import AppKit
import SwiftUI
import XCTest
@testable import ShellLayout

private nonisolated enum AXRoom: String, CaseIterable, WorkspaceRoom {
    case image, fft, edx

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var symbolName: String { "circle" }
    var subtitle: String { "The \(rawValue) room" }
}

@Observable private final class AXModel {
    var selection: AXRoom? = .image
    var unavailable: Set<AXRoom> = [.edx]
}

private struct AXSidebar: View {
    @Bindable var model: AXModel

    var body: some View {
        WorkspaceSidebarFrame(selection: $model.selection) {
            WorkspaceRoomsSection(rooms: AXRoom.allCases, tag: { $0 }, isAvailable: { !model.unavailable.contains($0) },
                                  selection: $model.selection)
        }
        .frame(width: 220, height: 300)
    }
}

nonisolated final class WorkspaceRowAccessibilityTests: XCTestCase {

    /// The press chooses an available room and leaves an unavailable one; with no selection given nothing is chosen.
    /// Red under: the press ignoring availability; a section without a selection claiming the press.
    @MainActor func testThePressChoosesAnAvailableRoomOnly() {
        var selected: AXRoom? = .image
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let section = WorkspaceRoomsSection(rooms: AXRoom.allCases, tag: { $0 }, isAvailable: { $0 != .edx }, selection: binding)
        XCTAssertTrue(section.choose(.fft))
        XCTAssertEqual(selected, .fft)
        XCTAssertFalse(section.choose(.edx), "an unavailable room is not chosen")
        XCTAssertEqual(selected, .fft)
        let bare = WorkspaceRoomsSection(rooms: AXRoom.allCases, tag: { $0 })
        XCTAssertFalse(bare.choose(.fft), "no selection given: the rows are not buttons")
    }

    /// The hosted list's row element, pressed as VoiceOver presses it, moves the selection. Red under: the rows without the action
    /// (the issue: AXPress answered success and did nothing).
    @MainActor func testPressingTheRowsAccessibilityElementChoosesTheRoom() throws {
        let model = AXModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: AXSidebar(model: model))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let row = try XCTUnwrap(Self.element(identifier: "workspace.fft", in: window.contentView), "no accessibility element for the FFT row")
        XCTAssertTrue(row.accessibilityPerformPress())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(model.selection, .fft)
    }

    /// The first element under `root` whose accessibility identifier is `identifier`, depth first through the accessibility children.
    /// Through `NSObject`'s informal NSAccessibility methods, which every AppKit and SwiftUI element answers.
    @MainActor private static func element(identifier: String, in root: Any?, depth: Int = 0) -> NSObject? {
        guard depth < 40, let node = root as? NSObject else { return nil }
        if node.accessibilityIdentifier() == identifier { return node }
        let children: [Any] = node.accessibilityChildren() ?? []
        for child in children {
            if let found = element(identifier: identifier, in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}
