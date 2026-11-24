//
//  PhaseEditingTests.swift
//  EMSuiteUI#191: a phase's lattice is edited through DiffractoKit's `editingLattice` (only free parameters; tied ones follow;
//  a refusal changes nothing), an edit marks the phase edited and is on disk, Reset to Source reads the stored source again
//  and clears the mark, and a name and notes are kept. The entry is DiffractoKit's recorded OPTIMADE answer for mp-134 (Al,
//  served as the primitive fcc cell and read as the conventional cubic one). Red before #191: none of these existed.
//

import DiffractoCore
import Foundation
import XCTest
@testable import ShellPhaseLibrary

final class PhaseEditingTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PhaseEditingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    /// The library with Al (mp-134) added from the recorded entry, as Add does.
    @MainActor private func aluminium() async throws -> (PhaseLibrary, Phase) {
        let entry = try AddPhaseModelTests.entry()
        let structure = try MaterialsProjectOptimade.structure(from: MaterialsProjectOptimade.decodeEntry(entry)).structure
        let library = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        let phase = Phase(id: "mp-134", name: "Al", source: .materialsProject(id: "mp-134", fetched: Date(timeIntervalSince1970: 1_795_000_000)),
                          structure: structure)
        try library.add(phase, source: entry, sourceExtension: "json")
        return (library, phase)
    }

    @MainActor func testOnlyAFreeParameterIsEditedAndTheTiedOnesFollow() async throws {
        let (library, phase) = try await aluminium()
        XCTAssertEqual(phase.structure().freeLatticeParameters, [.a], "cubic: a alone")
        XCTAssertFalse(phase.isEdited)

        XCTAssertThrowsError(try library.setLattice([.c: 4.2], of: "mp-134")) { error in
            guard case .lattice(.notFree(.c, _, _)) = error as? PhaseEditError else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(try XCTUnwrap(library.phases.first).isEdited, "a refused edit changes nothing")

        let edited = try library.setLattice([.a: 4.10], of: "mp-134")
        let cell = edited.structure().cell
        XCTAssertEqual(cell.a, 4.10, accuracy: 1e-12)
        XCTAssertEqual(cell.c, 4.10, accuracy: 1e-12, "c follows a")
        XCTAssertTrue(edited.isEdited)
        XCTAssertEqual(library.phases.first, edited)

        let reread = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        await reread.load()
        XCTAssertEqual(try XCTUnwrap(reread.phases.first).structure().cell.a, 4.10, accuracy: 1e-12, "the edit is on disk")
        XCTAssertTrue(try XCTUnwrap(reread.phases.first).isEdited)
    }

    @MainActor func testResetToSourceUndoesTheEdit() async throws {
        let (library, phase) = try await aluminium()
        let a = phase.structure().cell.a
        try library.setLattice([.a: a * 1.02], of: "mp-134")
        let reset = try await library.resetToSource("mp-134")
        XCTAssertFalse(reset.isEdited)
        XCTAssertEqual(reset.structure().cell.a, a, accuracy: 1e-12)
        XCTAssertEqual(reset.snapshot.fingerprint, phase.snapshot.fingerprint)
        XCTAssertEqual(reset.name, "Al", "name and notes stay")
    }

    @MainActor func testANameAndNotesAreKeptAndAnEmptyNameIsRefused() async throws {
        let (library, _) = try await aluminium()
        try library.rename("mp-134", to: "  Aluminium matrix ")
        try library.setNotes("Al-Mg-Si alloy, 6xxx", of: "mp-134")
        XCTAssertThrowsError(try library.rename("mp-134", to: "   ")) { XCTAssertEqual($0 as? PhaseEditError, .emptyName) }
        XCTAssertThrowsError(try library.setNotes("x", of: "mp-1")) { XCTAssertEqual($0 as? PhaseEditError, .notInLibrary("mp-1")) }

        let reread = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        await reread.load()
        XCTAssertEqual(reread.phases.first?.name, "Aluminium matrix")
        XCTAssertEqual(reread.phases.first?.notes, "Al-Mg-Si alloy, 6xxx")
    }

    @MainActor func testAMissingSourceIsSaidNotGuessed() async throws {
        let (library, _) = try await aluminium()
        let source = try XCTUnwrap(library.sourceFile(of: "mp-134"))
        try FileManager.default.removeItem(at: source)
        do {
            _ = try await library.resetToSource("mp-134")
            XCTFail("reset without a source")
        } catch {
            XCTAssertEqual(error as? PhaseEditError, .sourceMissing("mp-134"))
        }
    }
}
