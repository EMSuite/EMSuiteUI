//
//  AddPhaseModelTests.swift
//  EMSuiteUI#189: what the Add Phase sheet searches, says and adds, on a stub transport (no network in any test). The entry
//  fixture is DiffractoKit's recorded OPTIMADE answer for mp-134 (Al, served as the primitive fcc cell), copied unchanged
//  from DiffractoKit 0.20.0 Tests/DiffractoCoreTests/Fixtures/mp-optimade/.
//

import DiffractoCore
import Foundation
import XCTest
@testable import ShellPhaseLibrary

/// A key store that holds what the test gives it.
final class FixedKeyStore: APIKeyStore, @unchecked Sendable {
    var key: String?
    init(_ key: String? = nil) { self.key = key }
    func load() throws -> String? { key }
    func save(_ key: String) throws { self.key = key }
    func delete() throws { key = nil }
}

final class AddPhaseModelTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "AddPhaseModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    nonisolated static let twoAluminiumRows = Data("""
    {"data":[
      {"id":"mp-998860","type":"structures","attributes":{"nsites":4,"chemical_formula_reduced":"Al","_mp_stability":{"r2scan":{"energy_above_hull":0.09}}}},
      {"id":"mp-134","type":"structures","attributes":{"nsites":1,"chemical_formula_reduced":"Al","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}}
    ],"meta":{"data_available":154387,"more_data_available":false}}
    """.utf8)
    nonisolated static let noRows = Data(#"{"data":[],"meta":{"data_available":154387,"more_data_available":false}}"#.utf8)
    nonisolated static let serviceEmpty = Data(#"{"data":[],"meta":{"data_available":0,"more_data_available":false}}"#.utf8)

    nonisolated static func entry() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "entry-mp-134", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @MainActor private func make(_ stub: StubTransport, key: String? = nil) -> (AddPhaseModel, PhaseLibrary) {
        let clock = FakeClock()
        let client = MaterialsProjectClient(transport: stub, now: { clock.now }, sleep: { clock.sleep($0) })
        let library = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        let model = AddPhaseModel(library: library, client: client, keyStore: FixedKeyStore(key),
                                  now: { Date(timeIntervalSince1970: 1_795_000_000) })
        return (model, library)
    }

    // MARK: What the text asks for

    func testTheTextIsAFormulaWhenItHasADigitAndElementsOtherwise() {
        XCTAssertNil(AddPhaseModel.query(for: "  ", only: false))
        XCTAssertEqual(AddPhaseModel.query(for: "Al2Cu", only: false), .formula("Al2Cu"))
        XCTAssertEqual(AddPhaseModel.query(for: "Al 2 Cu", only: false), .formula("Al2Cu"))
        XCTAssertEqual(AddPhaseModel.query(for: "Al Cu", only: false), .elements(["Al", "Cu"], only: false))
        XCTAssertEqual(AddPhaseModel.query(for: "al, cu", only: true), .elements(["Al", "Cu"], only: true))
        XCTAssertEqual(AddPhaseModel.query(for: "AlCu", only: false), .elements(["Al", "Cu"], only: false))
        XCTAssertEqual(AddPhaseModel.query(for: "Mg-Si", only: false), .elements(["Mg", "Si"], only: false))
    }

    // MARK: Search

    @MainActor func testNothingTypedSendsNothingAndSaysWhatToType() async {
        let stub = StubTransport()
        let (model, _) = make(stub)
        await model.search()
        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(stub.sent.count, 0)
        XCTAssertEqual(model.statusMessage?.next.contains("Al2Cu"), true)
    }

    @MainActor func testASearchIsKeylessEvenWithAKeyAndShowsTheMostStableFirst() async throws {
        let stub = StubTransport { _ in (Self.twoAluminiumRows, 200, [:]) }
        let (model, _) = make(stub, key: "my-key")
        model.text = "Al"
        await model.search()
        guard case .results(let rows, let more) = model.status else { return XCTFail("\(model.status)") }
        XCTAssertEqual(rows.map(\.materialID), ["mp-134", "mp-998860"])
        XCTAssertFalse(more)
        XCTAssertNil(model.statusMessage)
        let sent = try XCTUnwrap(stub.sent.first)
        XCTAssertEqual(sent.url?.host, "optimade.materialsproject.org")
        XCTAssertNil(sent.value(forHTTPHeaderField: MaterialsProjectClient.keyHeader))
    }

    @MainActor func testTheSameTextIsAnsweredOnceAndRetrySearchesAgain() async {
        let stub = StubTransport { _ in throw URLError(.notConnectedToInternet) }
        let (model, _) = make(stub)
        model.text = "Si"
        await model.search()
        await model.search()
        XCTAssertEqual(stub.sent.count, 1, "a view that appears again sends nothing new")
        XCTAssertEqual(model.status, .offline)
        model.retry()
        await model.search()
        XCTAssertEqual(stub.sent.count, 2)
    }

    @MainActor func testNoResultsAndAnEmptyServiceAreToldApart() async {
        let empty = StubTransport { _ in (Self.noRows, 200, [:]) }
        let (a, _) = make(empty)
        a.text = "Xe Kr"
        a.onlyTheseElements = true
        await a.search()
        XCTAssertEqual(a.status, .noResults)
        XCTAssertEqual(a.statusMessage?.next.contains("Only These Elements"), true)

        let down = StubTransport { _ in (Self.serviceEmpty, 200, [:]) }
        let (b, _) = make(down)
        b.text = "Si"
        await b.search()
        XCTAssertEqual(b.status, .serviceEmpty)
        XCTAssertEqual(b.statusMessage?.next.contains("Try again later"), true)
    }

    @MainActor func testEveryStateWithoutRowsSaysWhatToDoNext() async {
        let cases: [(any Error)?] = [URLError(.notConnectedToInternet), URLError(.timedOut), nil]
        for error in cases {
            let stub = StubTransport { _ in
                if let error { throw error }
                return (Data(), 429, ["Retry-After": "20"])
            }
            let (model, _) = make(stub)
            model.text = "Si"
            await model.search()
            let message = model.statusMessage
            XCTAssertNotNil(message, "\(model.status)")
            XCTAssertFalse(message?.title.isEmpty ?? true)
            XCTAssertFalse(message?.next.isEmpty ?? true)
        }
    }

    @MainActor func testAnUnknownSymbolIsRefusedBeforeAnythingIsSent() async {
        let stub = StubTransport()
        let (model, _) = make(stub)
        model.text = "Al Xq"
        await model.search()
        guard case .problem(let title, _) = model.status else { return XCTFail("\(model.status)") }
        XCTAssertTrue(title.contains("Xq"), title)
        XCTAssertEqual(stub.sent.count, 0)
    }

    // MARK: Preview and Add

    @MainActor func testWithoutAKeyTheEntryComesFromTheOpenServiceAndAddsOnce() async throws {
        let entry = try Self.entry()
        let stub = StubTransport { request in
            request.url!.path.hasSuffix("/structures/mp-134") ? (entry, 200, [:]) : (Self.twoAluminiumRows, 200, [:])
        }
        let (model, library) = make(stub)
        model.text = "Al"
        await model.search()
        model.selection = "mp-134"
        await model.loadPreview()
        guard case .ready(let preview) = model.preview else { return XCTFail("\(model.preview)") }
        XCTAssertEqual(preview.name, "Al")
        XCTAssertEqual(preview.attribution, "Materials Project · mp-134 · CC BY 4.0")
        XCTAssertTrue(preview.converted, "served as the primitive fcc cell")
        XCTAssertEqual(preview.structure.cell.a, 2.855955 * 2.0.squareRoot(), accuracy: 1e-3)
        XCTAssertEqual(preview.source, entry)
        XCTAssertNil(stub.sent.last?.value(forHTTPHeaderField: MaterialsProjectClient.keyHeader))
        XCTAssertTrue(model.canAdd)

        let added = try XCTUnwrap(try model.add())
        XCTAssertEqual(added.id, "mp-134")
        XCTAssertEqual(added.source.attribution, "Materials Project · mp-134 · CC BY 4.0")
        XCTAssertEqual(library.phases.map(\.id), ["mp-134"])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.sourceFile(of: "mp-134"))), entry)
        XCTAssertTrue(model.isInLibrary)
        XCTAssertFalse(model.canAdd)
        XCTAssertNil(try model.add(), "a second Add adds nothing")
        XCTAssertEqual(library.phases.count, 1)
    }

    @MainActor func testWithAKeyTheEntryComesFromTheKeyedServiceAndAFailureIsSaid() async throws {
        let stub = StubTransport { _ in (Data(#"{"data":[],"errors":[]}"#.utf8), 200, [:]) }
        let (model, _) = make(stub, key: "my-key")
        model.selection = "mp-134"
        await model.loadPreview()
        let sent = try XCTUnwrap(stub.sent.first)
        XCTAssertEqual(sent.url?.host, "api.materialsproject.org")
        XCTAssertEqual(sent.value(forHTTPHeaderField: MaterialsProjectClient.keyHeader), "my-key")
        guard case .failed(let id, let message) = model.preview else { return XCTFail("\(model.preview)") }
        XCTAssertEqual(id, "mp-134")
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(model.canAdd)
    }
}
