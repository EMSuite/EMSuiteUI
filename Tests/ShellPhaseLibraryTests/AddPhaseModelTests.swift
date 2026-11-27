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

    /// Electron-Microscopy-Studio#1029: "Si" listed ternaries first and elemental Si not at all (the service's page of every entry
    /// holding Si did not reach it). The exact system is searched first and the rows are ranked: the exact match, then fewer
    /// elements, then the most stable. Red before: one search, and the rows in the kit's stability order only.
    @MainActor func testASingleElementListsItsElementFirstThenFewerElementsThenTheMostStable() async throws {
        let broad = Data("""
        {"data":[
          {"id":"mp-1","type":"structures","attributes":{"nsites":4,"chemical_formula_reduced":"SiU3","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}},
          {"id":"mp-2","type":"structures","attributes":{"nsites":5,"chemical_formula_reduced":"Co2ErSi2","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}},
          {"id":"mp-3","type":"structures","attributes":{"nsites":3,"chemical_formula_reduced":"NiSi2","_mp_stability":{"r2scan":{"energy_above_hull":0.2}}}}
        ],"meta":{"data_available":154387,"more_data_available":true}}
        """.utf8)
        let exact = Data("""
        {"data":[
          {"id":"mp-165","type":"structures","attributes":{"nsites":2,"chemical_formula_reduced":"Si","_mp_stability":{"r2scan":{"energy_above_hull":0.3}}}},
          {"id":"mp-149","type":"structures","attributes":{"nsites":2,"chemical_formula_reduced":"Si","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}}
        ],"meta":{"data_available":154387,"more_data_available":false}}
        """.utf8)
        // The exact search's filter holds the element count (OPTIMADE's nelements); the broad one does not.
        let stub = StubTransport { request in
            (request.url!.absoluteString.contains("nelements") ? exact : broad, 200, [:])
        }
        let (model, _) = make(stub)
        model.text = "Si"
        await model.search()
        guard case .results(let rows, let more) = model.status else { return XCTFail("\(model.status)") }
        XCTAssertEqual(rows.map(\.materialID), ["mp-149", "mp-165", "mp-1", "mp-3", "mp-2"])
        XCTAssertTrue(more)
        XCTAssertEqual(stub.sent.count, 2)

        // Only These Elements is one search, as before.
        let only = StubTransport { _ in (exact, 200, [:]) }
        let (narrow, _) = make(only)
        narrow.text = "Si"
        narrow.onlyTheseElements = true
        await narrow.search()
        XCTAssertEqual(only.sent.count, 1)
    }

    func testTheRankingIsExactThenFewerElementsThenStability() throws {
        let data = Data("""
        {"data":[
          {"id":"mp-11","type":"structures","attributes":{"nsites":6,"chemical_formula_reduced":"Al2Cu3Mg","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}},
          {"id":"mp-12","type":"structures","attributes":{"nsites":2}},
          {"id":"mp-13","type":"structures","attributes":{"nsites":3,"chemical_formula_reduced":"CuAl2","_mp_stability":{"r2scan":{"energy_above_hull":0.1}}}},
          {"id":"mp-14","type":"structures","attributes":{"nsites":1,"chemical_formula_reduced":"Al","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}},
          {"id":"mp-15","type":"structures","attributes":{"nsites":3,"chemical_formula_reduced":"Al2Cu","_mp_stability":{"r2scan":{"energy_above_hull":0.0}}}}
        ],"meta":{"data_available":154387,"more_data_available":false}}
        """.utf8)
        guard case .rows(let rows, _) = try MaterialsProjectOptimade.decodeSearch(data) else { return XCTFail("no rows") }
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(AddPhaseModel.ranked(rows, for: .elements(["Al", "Cu"], only: false)).map(\.materialID), ["mp-15", "mp-13", "mp-14", "mp-11", "mp-12"])
        XCTAssertEqual(AddPhaseModel.ranked(rows + [rows[0]], for: .formula("Al2Cu")).map(\.materialID), ["mp-15", "mp-13", "mp-14", "mp-11", "mp-12"],
                       "a row listed twice is kept once")
        XCTAssertEqual(AddPhaseModel.elements(ofFormula: "Co2ErSi2"), ["Co", "Er", "Si"])
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

    /// A phase added by its id with no search (the agent door's add_phase) is named by its reduced formula, not "mp-134", and the
    /// id stays in the source. Mutation: the name back to `structure.name` (the id) - red.
    @MainActor func testAPhaseAddedByIdWithoutASearchIsNamedByItsFormula() async throws {
        let entry = try Self.entry()
        let stub = StubTransport { _ in (entry, 200, [:]) }
        let (model, library) = make(stub)
        model.selection = "mp-134"
        await model.loadPreview()
        guard case .ready(let preview) = model.preview else { return XCTFail("\(model.preview)") }
        XCTAssertEqual(preview.name, "Al")
        let added = try XCTUnwrap(try model.add())
        XCTAssertEqual(added.name, "Al")
        XCTAssertEqual(added.id, "mp-134")
        XCTAssertEqual(added.source.attribution, "Materials Project · mp-134 · CC BY 4.0")
        XCTAssertEqual(library.phases.map(\.name), ["Al"])
    }

    /// One name for both paths: after a search whose row spells the formula another way, the name is still the structure's.
    /// Mutation: the row's formula preferred - red.
    @MainActor func testTheNameComesFromTheStructureEvenAfterASearch() async throws {
        let entry = try Self.entry()
        let rows = Data(#"{"data":[{"id":"mp-134","type":"structures","attributes":{"nsites":1,"chemical_formula_reduced":"O2Si"}}],"meta":{"data_available":1,"more_data_available":false}}"#.utf8)
        let stub = StubTransport { request in request.url!.path.hasSuffix("/structures/mp-134") ? (entry, 200, [:]) : (rows, 200, [:]) }
        let (model, _) = make(stub)
        model.text = "Al"
        await model.search()
        model.selection = "mp-134"
        await model.loadPreview()
        guard case .ready(let preview) = model.preview else { return XCTFail("\(model.preview)") }
        XCTAssertEqual(preview.name, "Al")
    }

    /// Where another phase of the library has the formula, the new one carries its space-group symbol; the one already there keeps
    /// its name. Mutation: the symbol added to every phase, or never - red.
    @MainActor func testASecondPhaseOfTheSameFormulaCarriesItsSpaceGroup() async throws {
        let entry = try Self.entry()
        let stub = StubTransport { _ in (entry, 200, [:]) }
        let (model, library) = make(stub)
        let before = Phase(id: "mp-other", name: "Al", source: .materialsProject(id: "mp-other", fetched: Date()), structure: CrystalPresets.aluminum)
        try library.add(before, source: Data("{}".utf8), sourceExtension: "json")
        model.selection = "mp-134"
        await model.loadPreview()
        let added = try XCTUnwrap(try model.add())
        XCTAssertTrue(added.name.hasPrefix("Al ("), added.name)
        XCTAssertEqual(library.phases.first { $0.id == "mp-other" }?.name, "Al", "existing names are not migrated")
    }

    func testTheReducedFormulaAndTheLibraryName() {
        XCTAssertEqual(AddPhaseModel.libraryName(formula: "Si", symbol: "Fd-3m", id: "mp-149", existing: []), "Si")
        XCTAssertEqual(AddPhaseModel.libraryName(formula: "Si", symbol: "Fd-3m", id: "mp-149", existing: ["Al", "Si Nitride"]), "Si",
                       "another formula that starts the same is no clash")
        XCTAssertEqual(AddPhaseModel.libraryName(formula: "Si", symbol: "P6_3/mmc", id: "mp-1", existing: ["Si"]), "Si (P6_3/mmc)")
        XCTAssertEqual(AddPhaseModel.libraryName(formula: "Si", symbol: "P6_3/mmc", id: "mp-1", existing: ["Si", "Si (P6_3/mmc)"]),
                       "Si (mp-1)", "the same symbol twice falls back to the id")
        XCTAssertEqual(AddPhaseModel.libraryName(formula: "Si", symbol: nil, id: "mp-1", existing: ["Si"]), "Si (mp-1)")
        XCTAssertEqual(AddPhaseModel.libraryName(formula: "mp-1", symbol: "Fm-3m", id: "mp-1", existing: ["mp-1"]), "mp-1")
        XCTAssertEqual(AddPhaseModel.reducedFormula(of: CrystalPresets.silicon), "Si")
    }

    /// The elements come in pymatgen's `reduced_formula` order, by increasing electronegativity, counts reduced. Mutation: alphabetical
    /// order ("O2Si") - red.
    func testTheFormulaIsOrderedByElectronegativityAsPymatgenWritesIt() {
        func structure(_ counts: [(Int, Int)]) -> CrystalStructure {
            let sites = counts.flatMap { z, n in (0 ..< n).map { i in AtomSite(z: z, fractional: SIMD3(Double(i) / 10, 0, 0)) } }
            return CrystalStructure(cell: UnitCell(a: 5, b: 5, c: 5, alphaDeg: 90, betaDeg: 90, gammaDeg: 90), sites: sites, operations: [.identity])
        }
        XCTAssertEqual(AddPhaseModel.reducedFormula(of: structure([(14, 4), (8, 8)])), "SiO2")
        XCTAssertEqual(AddPhaseModel.reducedFormula(of: structure([(26, 4), (8, 6)])), "Fe2O3")
        XCTAssertEqual(AddPhaseModel.reducedFormula(of: structure([(30, 2), (8, 2)])), "ZnO")
        XCTAssertEqual(AddPhaseModel.reducedFormula(of: structure([(13, 2), (8, 3)])), "Al2O3")
        XCTAssertEqual(AddPhaseModel.reducedFormula(of: structure([(31, 2), (7, 2)])), "GaN")
    }

    /// #1115: a search row writes the service's alphabetical formula in the order of the preview's name, so "GaAs" lists as GaAs, not
    /// AsGa. Red before: the rows showed the service's form.
    func testARowsFormulaIsWrittenInThePreviewNamesOrder() {
        XCTAssertEqual(AddPhaseModel.displayFormula("AsGa"), "GaAs")
        XCTAssertEqual(AddPhaseModel.displayFormula("AsGa3"), "Ga3As")
        XCTAssertEqual(AddPhaseModel.displayFormula("O2Si"), "SiO2")
        XCTAssertEqual(AddPhaseModel.displayFormula("Fe2O3"), "Fe2O3")
        XCTAssertEqual(AddPhaseModel.displayFormula("FeO3Ti"), "TiFeO3")
        XCTAssertEqual(AddPhaseModel.displayFormula("Au"), "Au")
        XCTAssertEqual(AddPhaseModel.displayFormula("Al2Cu3Mg"), "MgAl2Cu3")
        for garbage in ["", "mp-149", "asga", "Ga As", "GaGa", "Ga0As", "3Ga", "GaAs!"] {
            XCTAssertEqual(AddPhaseModel.displayFormula(garbage), garbage, "not a formula: shown as it came")
        }
    }

    /// The row and the preview's name agree for the same entry: the same element counts through `reducedFormula(of:)` (the
    /// preview) and through the service's alphabetical formula (the row) give one text.
    func testTheRowAndThePreviewNameAgree() {
        func structure(_ counts: [(Int, Int)]) -> CrystalStructure {
            let sites = counts.flatMap { z, n in (0 ..< n).map { i in AtomSite(z: z, fractional: SIMD3(Double(i) / 10, 0, 0)) } }
            return CrystalStructure(cell: UnitCell(a: 5, b: 5, c: 5, alphaDeg: 90, betaDeg: 90, gammaDeg: 90), sites: sites, operations: [.identity])
        }
        let cases: [(served: String, counts: [(Int, Int)])] = [
            ("AsGa", [(31, 4), (33, 4)]), ("AsGa3", [(31, 3), (33, 1)]), ("O2Si", [(14, 4), (8, 8)]),
            ("FeO3Ti", [(26, 2), (8, 6), (22, 2)]), ("Al2Cu3Mg", [(13, 2), (29, 3), (12, 1)]),
        ]
        for (served, counts) in cases {
            XCTAssertEqual(AddPhaseModel.displayFormula(served), AddPhaseModel.reducedFormula(of: structure(counts)), served)
        }
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

/// EMSuiteUI#283: the search answer is decoded off the main actor, since the kit now reads each row's space group from its atoms
/// (a symmetry detection per row, up to 500 rows). Red before: the model, which is `@MainActor`, decoded inline.
nonisolated final class AddPhaseModelDecodeOffMainTests: XCTestCase {
    func testTheSearchIsDecodedOffTheMainActor() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: root.appendingPathComponent("Sources/ShellPhaseLibrary/AddPhaseModel.swift"), encoding: .utf8)
        XCTAssertTrue(model.contains("@concurrent nonisolated static func decodeSearch(_ data: Data) async throws"))
        XCTAssertFalse(model.contains("try MaterialsProjectOptimade.decodeSearch(try await"), "an inline decode on the main actor")
    }
}
