//
//  AddPhaseSheetTests.swift
//  EMSuiteUI#189: the Add Phase sheet's order of closing and opening, its row text, and its snapshots in light and dark.
//  EMSuiteUI#195: the preview's still unit-cell picture, what it draws and what VoiceOver says for it.
//  The snapshots compare only on CI's macos-26 leg (SNAPSHOTS=1); a new picture is attached to the pull request and
//  committed under __Snapshots__/AddPhaseSheetTests/ once reviewed. The entry fixture is DiffractoKit 0.20.0's recorded
//  OPTIMADE answer for mp-134 (Al), copied unchanged.
//

import DiffractoCore
import Foundation
import ShellCrystal
import ShellPhaseLibrary
import ShellSnapshotTesting
import simd
import SwiftUI
import XCTest
@testable import ShellPhaseViews

/// Answers from a script; no network.
private nonisolated final class ScriptedTransport: PhaseTransport, @unchecked Sendable {
    let answer: @Sendable (URLRequest) -> Data
    init(_ answer: @escaping @Sendable (URLRequest) -> Data) { self.answer = answer }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (answer(request), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private nonisolated final class NoKey: APIKeyStore, @unchecked Sendable {
    func load() throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}

/// What happened, in order (a box, so the closures share it on the main actor).
@MainActor private final class Order { var steps: [String] = [] }

nonisolated final class AddPhaseSheetTests: XCTestCase {

    @MainActor func testOpenCIFClosesTheSheetBeforeTheFileDialogOpens() async {
        let order = Order()
        let opened = expectation(description: "the file dialog opens")
        AddPhaseSheet.openCIF(dismiss: { order.steps.append("dismiss") }, open: { order.steps.append("open"); opened.fulfill() })
        XCTAssertEqual(order.steps, ["dismiss"], "the dialog waits until the sheet has gone")
        await fulfillment(of: [opened], timeout: 2)
        XCTAssertEqual(order.steps, ["dismiss", "open"])
    }

    @MainActor func testARowSaysStableOnTheHullAndHowFarAboveItOtherwise() {
        XCTAssertEqual(AddPhaseRow.stability(0), "Stable")
        XCTAssertEqual(AddPhaseRow.stability(0.0123), "0.012 eV/atom above hull")
        XCTAssertEqual(AddPhaseRow.stability(nil), "No stability data")
        XCTAssertEqual(AddPhaseRow.sites(1), "1 site")
        XCTAssertEqual(AddPhaseRow.sites(4), "4 sites")
    }

    /// #1115: a row writes its formula as the preview names the entry (GaAs, not the service's AsGa), and its id when it has none.
    /// The row's VoiceOver label is its combined text, so it says the same. Red before: the row showed "AsGa".
    @MainActor func testARowWritesItsFormulaAsThePreviewNamesIt() throws {
        let data = Data("""
        {"data":[
          {"id":"mp-2534","type":"structures","attributes":{"nsites":2,"chemical_formula_reduced":"AsGa"}},
          {"id":"mp-1184232","type":"structures","attributes":{"nsites":4,"chemical_formula_reduced":"AsGa3"}},
          {"id":"mp-12","type":"structures","attributes":{"nsites":2}}
        ],"meta":{"data_available":154387,"more_data_available":false}}
        """.utf8)
        guard case .rows(let rows, _) = try MaterialsProjectOptimade.decodeSearch(data) else { return XCTFail("no rows") }
        // By id: the decoder orders the rows itself, and that order is not this test's subject.
        let titles = Dictionary(uniqueKeysWithValues: rows.map { ($0.materialID, AddPhaseRow.title($0)) })
        XCTAssertEqual(titles, ["mp-2534": "GaAs", "mp-1184232": "Ga3As", "mp-12": "mp-12"])
    }

    /// #1115: the preview says its cell is the Materials Project's computed one.
    @MainActor func testThePreviewSaysTheCellIsComputed() {
        XCTAssertEqual(AddPhasePreview.computedCellNote,
                       "The Materials Project's computed (relaxed) cell; lattice parameters can differ from measured ones by a percent or two.")
    }

    // MARK: The unit-cell picture (#195)

    /// The preview of mp-134 (aluminium, served primitive, shown conventional) draws its unit cell: every atom aluminium, the
    /// cell's sites on each face they touch, the cell box, and words for VoiceOver. Red before: the preview had no picture.
    @MainActor func testThePreviewDrawsTheEntrysUnitCellWithWordsForVoiceOver() async throws {
        let model = try makeModel()
        model.text = "Al"
        await model.search()
        model.selection = "mp-134"
        await model.loadPreview()
        guard case .ready(let preview) = model.preview else { return XCTFail("no preview: \(model.preview)") }

        let scene = AddPhaseCrystal.scene(preview.structure)
        XCTAssertNotNil(scene.cell, "the cell box is drawn")
        XCTAssertGreaterThan(scene.atoms.count, preview.structure.sites.count, "a site on a face is drawn on every face it touches")
        XCTAssertTrue(scene.atoms.allSatisfy { $0.atomicNumber == 13 })
        let words = CrystalDescription.value(scene, showsUnitCell: true)
        XCTAssertTrue(words.hasPrefix("\(scene.atoms.count) atoms: \(scene.atoms.count) aluminium"), words)
        XCTAssertTrue(words.hasSuffix("unit cell shown"), words)
        XCTAssertEqual(AddPhaseCrystal.label(name: "Al", materialID: "mp-134", formula: "Al"), "Unit cell of Al (mp-134)")
        XCTAssertEqual(AddPhaseCrystal.label(name: "Corundum", materialID: "mp-1143", formula: "Al2O3"),
                       "Unit cell of Corundum (mp-1143), Al2O3")

        // A still view: a proper rotation, looking down c turned toward a and b, so the box reads in 3D.
        let o = AddPhaseCrystal.orientation(preview.structure)
        XCTAssertEqual(simd_determinant(o), 1, accuracy: 1e-12)
        let c = simd_normalize(preview.structure.cell.realLattice[2])
        XCTAssertGreaterThan(simd_dot(o.columns.2, c), 0.9)
        XCTAssertLessThan(simd_dot(o.columns.2, c), 0.999)
    }

    // MARK: Snapshots

    @MainActor private func makeModel() throws -> AddPhaseModel {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "entry-mp-134", withExtension: "json", subdirectory: "Fixtures"))
        let entry = try Data(contentsOf: url)
        let rows = Data("""
        {"data":[
          {"id":"mp-134","type":"structures","attributes":{"nsites":1,"chemical_formula_reduced":"Al","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}},
          {"id":"mp-998860","type":"structures","attributes":{"nsites":4,"chemical_formula_reduced":"Al","_mp_stability":{"r2scan":{"energy_above_hull":0.0904}}}}
        ],"meta":{"data_available":154387,"more_data_available":false}}
        """.utf8)
        let transport = ScriptedTransport { $0.url!.path.hasSuffix("/structures/mp-134") ? entry : rows }
        let client = MaterialsProjectClient(transport: transport, sleep: { _ in })
        let folder = FileManager.default.temporaryDirectory.appending(path: "AddPhaseSheetTests-\(UUID().uuidString)")
        return AddPhaseModel(library: PhaseLibrary(store: PhaseLibraryStore(folder: folder)), client: client, keyStore: NoKey())
    }

    @MainActor private func check(_ name: String, _ model: AddPhaseModel, file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(Snapshot.isEnabled, "snapshots are compared only where SNAPSHOTS=1 is set (CI's macos-26 leg)")
        let view = AddPhaseSheet(model: model, onOpenCIF: {})
        for appearance in SnapshotAppearance.allCases {
            let result = Snapshot.verify(view, named: name, size: CGSize(width: 720, height: 500), appearance: appearance,
                                         testFile: file)
            if let failure = result.failure { XCTFail(failure, file: file, line: line) }
        }
    }

    @MainActor func testSnapshotEmpty() async throws {
        let model = try makeModel()
        await model.search()
        try check("add-phase-empty", model)
    }

    @MainActor func testSnapshotResultsWithAPreview() async throws {
        let model = try makeModel()
        model.text = "Al"
        await model.search()
        model.selection = "mp-134"
        await model.loadPreview()
        try check("add-phase-results", model)
    }
}
