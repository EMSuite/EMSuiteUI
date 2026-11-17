// The rooms list to accessibility (EMSuiteUI#131): with the list's selection handed to `WorkspaceRoomsSection`, an available room row
// is a button whose press chooses the room, and an unavailable one is left alone. Without it the rows are as before. The press is
// driven through `choose`, the action's one body: SwiftUI builds its accessibility nodes only for a live accessibility client, so a
// unit test cannot reach the hosted row's element (BusyLineAccessibilityTests).

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
}
