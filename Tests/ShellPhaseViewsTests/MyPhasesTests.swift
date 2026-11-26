//
//  MyPhasesTests.swift
//  EMSuiteUI#191: the lattice fields a room's inspector shows for the phase in use (only the free parameters; an edit marks the
//  phase edited and offers Reset to Source), and My Phases, the Add Phase sheet's second page. Snapshots in light and dark
//  compare only on CI's macos-26 leg (SNAPSHOTS=1); a new picture is attached to the pull request and committed under
//  __Snapshots__/MyPhasesTests/ once reviewed. The entry is DiffractoKit's recorded OPTIMADE answer for mp-134 (Al).
//

import DiffractoCore
import Foundation
import ShellInspector
import ShellPhaseLibrary
import ShellSnapshotTesting
import SwiftUI
import XCTest
@testable import ShellPhaseViews

nonisolated final class MyPhasesTests: XCTestCase {

    @MainActor private func library(edited: Bool) throws -> PhaseLibrary {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "entry-mp-134", withExtension: "json", subdirectory: "Fixtures"))
        let entry = try Data(contentsOf: url)
        let structure = try MaterialsProjectOptimade.structure(from: MaterialsProjectOptimade.decodeEntry(entry)).structure
        let folder = FileManager.default.temporaryDirectory.appending(path: "MyPhasesTests-\(UUID().uuidString)")
        let library = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        let added = Date(timeIntervalSince1970: 1_795_000_000)
        try library.add(Phase(id: "mp-134", name: "Al", notes: "6xxx alloy matrix", source: .materialsProject(id: "mp-134", fetched: added),
                              added: added, structure: structure), source: entry, sourceExtension: "json")
        if edited { try library.setLattice([.a: 4.0495], of: "mp-134") }
        return library
    }

    /// A cubic phase gets one field, a; its help says b and c follow.
    @MainActor func testOnlyTheFreeParametersGetAField() throws {
        let structure = try XCTUnwrap(try library(edited: false).phases.first).structure()
        let free = PhaseLatticeFields.fields(for: structure)
        XCTAssertEqual(free, [.a])
        XCTAssertEqual(PhaseLatticeFields.help(.a, free: free), "Set a; b and c follow it by symmetry")
        XCTAssertEqual(PhaseLatticeFields.value(.a, of: structure.cell), structure.cell.a)
        XCTAssertEqual(PhaseLatticeFields.spoken(.gamma), "Angle gamma")
    }

    /// The fields find the free parameters once per fingerprint, not on every drawing pass, and again after an edit; the values
    /// they show are the stored cell's.
    @MainActor func testTheFreeParametersAreFoundOncePerFingerprint() throws {
        let library = try library(edited: false)
        let before = try XCTUnwrap(library.phases.first).snapshot
        let memo = PhaseLatticeFields.FreeParameters()
        XCTAssertEqual(memo.free(for: before), [.a])
        XCTAssertEqual(memo.free(for: before), [.a])
        XCTAssertEqual(memo.computations, 1)
        try library.setLattice([.a: 4.0495], of: "mp-134")
        let after = try XCTUnwrap(library.phases.first).snapshot
        XCTAssertEqual(memo.free(for: after), [.a])
        XCTAssertEqual(memo.computations, 2)
        XCTAssertEqual(PhaseLatticeFields.value(.a, of: after.cell), 4.0495, accuracy: 1e-9)
    }

    /// The preview and My Phases write a cell the same way.
    func testTheCellReadsAlikeOnBothPages() {
        XCTAssertEqual(LatticeText.lengths(4.0495, 4.0495, 4.0495), "4.0495, 4.0495, 4.0495 Å")
        XCTAssertEqual(LatticeText.angles(90, 90, 120), "90.00°, 90.00°, 120.00°")
    }

    @MainActor func testTheSourceReadsAsItsIdOrFile() {
        XCTAssertEqual(MyPhasesRow.source(.materialsProject(id: "mp-134", fetched: Date())), "mp-134")
        XCTAssertEqual(MyPhasesRow.source(.cif(fileName: "beta.cif")), "beta.cif")
        XCTAssertEqual(PhaseDetails.from(.cif(fileName: "beta.cif")), "CIF file beta.cif")
    }

    // MARK: Snapshots

    @MainActor private func check(_ name: String, _ view: some View, size: CGSize, file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(Snapshot.isEnabled, "snapshots are compared only where SNAPSHOTS=1 is set (CI's macos-26 leg)")
        for appearance in SnapshotAppearance.allCases {
            let result = Snapshot.verify(view, named: name, size: size, appearance: appearance, testFile: file)
            if let failure = result.failure { XCTFail(failure, file: file, line: line) }
        }
    }

    @MainActor func testSnapshotLatticeFieldsEdited() throws {
        let library = try library(edited: true)
        let view = InspectorSection("Phases") { PhaseLatticeFields(library: library, phaseID: "mp-134") }
            .padding(12)
        try check("lattice-fields-edited", view, size: CGSize(width: 300, height: 160))
    }

    @MainActor func testSnapshotMyPhases() throws {
        let library = try library(edited: true)
        try check("my-phases", MyPhasesView(library: library, selection: "mp-134"), size: CGSize(width: 720, height: 640))
    }
}
