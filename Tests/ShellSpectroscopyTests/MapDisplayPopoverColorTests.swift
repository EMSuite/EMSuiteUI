//
//  MapDisplayPopoverColorTests.swift
//  The Display popover reads only the appearance a picked colour resolves in, not the whole environment (EMSuite/EMSuiteUI#129): the
//  colour it stores is the same numbers as before.
//

import SwiftUI
import XCTest
@testable import ShellSpectroscopy

nonisolated final class MapDisplayPopoverColorTests: XCTestCase {

    @MainActor func testTheResolvingEnvironmentCarriesTheAppearance() {
        XCTAssertEqual(MapDisplayPopover.resolving(.dark).colorScheme, .dark)
        XCTAssertEqual(MapDisplayPopover.resolving(.light).colorScheme, .light)
    }

    @MainActor func testAPickedSRGBColourKeepsItsNumbers() {
        let picked = Color(.sRGB, red: 0.2, green: 0.5, blue: 0.8, opacity: 1)
        for scheme in [ColorScheme.light, .dark] {
            let stored = RegionColor(picked, resolvedIn: MapDisplayPopover.resolving(scheme))
            XCTAssertEqual(stored.red, 0.2, accuracy: 1e-3)
            XCTAssertEqual(stored.green, 0.5, accuracy: 1e-3)
            XCTAssertEqual(stored.blue, 0.8, accuracy: 1e-3)
        }
    }
}
