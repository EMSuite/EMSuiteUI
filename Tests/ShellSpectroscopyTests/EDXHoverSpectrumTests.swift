//
//  EDXHoverSpectrumTests.swift
//  The pointer's pixel spectrum in the EDS room (EMSuiteUI#125): summed off the main actor, so the room draws only the spectrum summed for
//  the pixel the pointer is on now, never one a move left behind.
//

import XCTest
@testable import ShellSpectroscopy

nonisolated final class EDXHoverSpectrumTests: XCTestCase {

    /// The sum lands for its own pixel only: another pixel, or no pointer, draws nothing. Red under: the last sum drawn whatever the pointer.
    @MainActor func testOnlyTheSpectrumOfThePixelUnderThePointerIsDrawn() {
        let here = EDXHoverPixel(x: 3, y: 4), there = EDXHoverPixel(x: 4, y: 4)
        let value = EDXHoverSpectrumValue(pixel: here, spectrum: [1, 2, 3])
        XCTAssertEqual(EDXHoverSpectrumValue.shown(value, for: here), [1, 2, 3])
        XCTAssertNil(EDXHoverSpectrumValue.shown(value, for: there), "the pointer moved on: the old pixel's sum is not drawn")
        XCTAssertNil(EDXHoverSpectrumValue.shown(value, for: nil), "the pointer left the maps")
        XCTAssertNil(EDXHoverSpectrumValue.shown(nil, for: here), "not summed yet")
    }
}
