//
//  EDXFigureAsShownTests.swift
//  The maps PNG is the picture on screen (EMSuiteUI#125): each map in the person's colour, contrast window and gamma, made by the same code as
//  the room's tiles; the save panel's bytes go when it closes. On EDXSessionTests' planted two-pixel image.
//

import XCTest
import SpectroCore
@testable import ShellEDXModel
@testable import ShellSpectroscopy

nonisolated final class EDXFigureAsShownTests: XCTestCase {

    /// The figure's raster of a map is the room's tile raster under the same appearance, and a contrast window the person set changes it.
    /// Red under: no rasters handed to the figure (it drew every map in its default colouring, whatever the room showed).
    @MainActor func testTheFiguresMapsAreTheRoomsTilesUnderThePersonsAppearance() async throws {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let tile = try XCTUnwrap(session.shownTiles.first, "precondition: a map to draw")
        let state = EDXRoomState()

        let plain = await EDXRoomState.figureRasters(of: session, appearance: state.appearance, filter: state.mapFilter)
        var appearance = state.appearance
        appearance.adjustments[tile.symbol] = MapAdjustment(low: 0.4, high: 0.6, gamma: 0.3)
        let windowed = await EDXRoomState.figureRasters(of: session, appearance: appearance, filter: state.mapFilter)

        let room = EDXMapTileHost.spec(for: EDXGridItem(id: tile.symbol, kind: .map(tile)), appearance: appearance, filter: state.mapFilter,
                                       width: tile.width, memo: session.filteredMaps).raster()
        XCTAssertEqual(windowed[tile.symbol], room, "the figure's map is the room's tile")
        XCTAssertNotNil(plain[tile.symbol])
        XCTAssertNotEqual(plain[tile.symbol], windowed[tile.symbol], "the person's window changes the exported map")
        XCTAssertNotNil(windowed[EDXFigureContent.mixKey], "the colour mix as the room draws it")
    }

    /// The app's finishing step gets the bytes made, the kind and the session, and what it returns is what is written. Red before:
    /// the bytes were written as made, so the app had no place to put its methods record (Electron-Microscopy-Studio#817).
    @MainActor func testTheAppsFinishingStepShapesTheBytesWritten() async throws {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let state = EDXRoomState()
        var seen: [EDXExportKind] = []
        state.finishExport = { data, kind, _ in
            seen.append(kind)
            return Data("# finished\n".utf8) + data
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("edx-finish-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var said = ""
        await state.export(.spectrum, from: session, directory: dir) { said = $0 }
        XCTAssertEqual(seen, [.spectrum])
        let name = try XCTUnwrap(said.split(separator: " ", maxSplits: 1).last.map(String.init), said)
        let written = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
        XCTAssertEqual(written, "# finished\n" + (session.spectrumCSV ?? ""))
    }

    /// The bytes made for the save panel go when it closes. Red under: `exportData` kept after the save.
    @MainActor func testTheExportsBytesGoWhenThePanelCloses() async {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let state = EDXRoomState()
        await state.export(.spectrum, from: session) { _ in }
        XCTAssertEqual(state.exporting, .spectrum)
        XCTAssertFalse(state.exportData.isEmpty, "setup: the spectrum CSV was made for the panel")
        state.exportFinished()
        XCTAssertNil(state.exporting)
        XCTAssertTrue(state.exportData.isEmpty)
    }
}
