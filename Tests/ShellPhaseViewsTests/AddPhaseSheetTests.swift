//
//  AddPhaseSheetTests.swift
//  EMSuiteUI#189: the Add Phase sheet's order of closing and opening, its row text, and its snapshots in light and dark.
//  The snapshots compare only on CI's macos-26 leg (SNAPSHOTS=1); a new picture is attached to the pull request and
//  committed under __Snapshots__/AddPhaseSheetTests/ once reviewed. The entry fixture is DiffractoKit 0.20.0's recorded
//  OPTIMADE answer for mp-134 (Al), copied unchanged.
//

import DiffractoCore
import Foundation
import ShellPhaseLibrary
import ShellSnapshotTesting
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
