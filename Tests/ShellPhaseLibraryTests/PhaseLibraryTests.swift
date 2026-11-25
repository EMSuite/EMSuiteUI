//
//  PhaseLibraryTests.swift
//  EMSuiteUI#188: the phase record (snapshot, source, edited state) and the library over its folder.
//

import DiffractoCore
import Foundation
import XCTest
@testable import ShellPhaseLibrary

final class PhaseLibraryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PhaseLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private let fetched = Date(timeIntervalSince1970: 1_795_000_000)
    private var silicon: Phase {
        Phase(id: "mp-149", name: "Si", source: .materialsProject(id: "mp-149", fetched: fetched), added: fetched,
              structure: CrystalPresets.diamond(a: 5.431, z: 14))
    }

    func testARecordSurvivesItsBytesAndNamesItsSource() throws {
        let phase = silicon
        let back = try Phase.decoded(Phase.encoded(phase))
        XCTAssertEqual(back, phase)
        XCTAssertEqual(back.structure().fingerprint, phase.sourceFingerprint)
        XCTAssertEqual(phase.source.attribution, "Materials Project · mp-149 · CC BY 4.0")
        XCTAssertEqual(phase.source.pageURL?.absoluteString, "https://next-gen.materialsproject.org/materials/mp-149")
        XCTAssertNil(PhaseSource.cif(fileName: "Si.cif").attribution)
    }

    func testAnEditShowsAndResetUndoesIt() {
        var phase = silicon
        XCTAssertFalse(phase.isEdited)
        phase.replaceStructure(CrystalPresets.diamond(a: 5.44, z: 14))
        XCTAssertTrue(phase.isEdited)
        phase.resetStructure(to: CrystalPresets.diamond(a: 5.431, z: 14))
        XCTAssertFalse(phase.isEdited)
    }

    func testARecordOfANewerSchemaIsRefusedWithASentence() throws {
        var json = try XCTUnwrap(String(data: Phase.encoded(silicon), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"schemaVersion\" : 1,\n  \"snapshot\"", with: "\"schemaVersion\" : 99,\n  \"snapshot\"")
        XCTAssertThrowsError(try Phase.decoded(Data(json.utf8))) { error in
            XCTAssertEqual(error as? Phase.ReadError, .newerSchema(99))
        }
    }

    @MainActor func testTheLibraryKeepsWhatWasAddedAcrossALoad() async throws {
        let store = PhaseLibraryStore(folder: folder)
        let library = PhaseLibrary(store: store)
        try library.add(silicon, source: Data("{\"id\":\"mp-149\"}".utf8), sourceExtension: "json")
        let aluminium = Phase(id: UUID().uuidString, name: "Al", source: .cif(fileName: "Al.cif"), added: fetched.addingTimeInterval(60),
                              structure: CrystalPresets.aluminum)
        try library.add(aluminium, source: Data("data_Al".utf8), sourceExtension: "cif")
        var renamed = aluminium
        renamed.name = "Aluminium"
        try library.update(renamed)

        let again = PhaseLibrary(store: store)
        await again.load()
        XCTAssertEqual(again.phases.map(\.name), ["Aluminium", "Si"], "newest first")
        XCTAssertEqual(again.phase(materialsProjectID: "mp-149")?.name, "Si")
        XCTAssertEqual(again.sourceFile(of: "mp-149")?.lastPathComponent, "source.json")
        XCTAssertEqual(again.unreadable, [])

        try again.remove(id: "mp-149")
        XCTAssertNil(again.phase(materialsProjectID: "mp-149"))
    }

    @MainActor func testAPhaseNamedByItsBareIDIsNamedByItsFormulaOnLoad() async throws {
        let store = PhaseLibraryStore(folder: folder)
        let library = PhaseLibrary(store: store)
        var bare = silicon
        bare.name = "mp-149"
        try library.add(bare, source: Data("{}".utf8), sourceExtension: "json")
        let gold = Phase(id: "mp-81", name: "My gold", source: .materialsProject(id: "mp-81", fetched: fetched),
                         added: fetched.addingTimeInterval(60), structure: CrystalPresets.gold)
        try library.add(gold, source: Data("{}".utf8), sourceExtension: "json")

        let again = PhaseLibrary(store: store)
        await again.load()
        XCTAssertEqual(again.phase(materialsProjectID: "mp-149")?.name, "Si", "the bare id takes the formula")
        XCTAssertEqual(again.phase(materialsProjectID: "mp-81")?.name, "My gold", "a typed name stays")

        let third = PhaseLibrary(store: store)
        await third.load()
        XCTAssertEqual(third.phase(materialsProjectID: "mp-149")?.name, "Si", "the new name was written back")
    }
}
