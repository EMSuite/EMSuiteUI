//
//  AddPhaseModel.swift
//  Role: what the Add Phase sheet shows and does (EMSuiteUI#189, plan section 5.2): a search of the Materials Project as the
//        person types, a preview of the chosen entry, and Add into the library. The search is always the open (keyless)
//        OPTIMADE service; the download uses the person's own key when there is one, the open service otherwise, so the
//        sheet works without a key. Every request and answer is DiffractoKit's (`MaterialsProjectOptimade`,
//        `MaterialsProjectImport`); this model sends them through `MaterialsProjectClient` and says what came back.
//

import DiffractoCore
import Foundation
import Observation

@MainActor
@Observable
public final class AddPhaseModel {

    /// What the results area shows.
    public enum Status: Equatable, Sendable {
        /// Nothing typed yet.
        case empty
        case searching
        /// Matches in `ranked` order (the exact match, fewer elements, the most stable); `more`: the service holds more than it returned.
        case results([MaterialsProjectOptimade.Row], more: Bool)
        /// The service holds structures and none matches.
        case noResults
        /// The service answered with no structures at all (its data is missing for now).
        case serviceEmpty
        case offline
        /// Anything else that went wrong, with what to say (`title`) and what to do (`next`).
        case problem(title: String, next: String)
    }

    /// The chosen entry, downloaded and read into the kit's structure.
    public struct Preview: Equatable, Sendable {
        public let materialID: String
        public let name: String
        public let structure: CrystalStructure
        /// The served cell was a centred primitive cell and the kit converted it to the conventional one.
        public let converted: Bool
        /// The bytes as they came, kept beside the phase in the library.
        public let source: Data

        public var attribution: String { "Materials Project · \(materialID) · CC BY 4.0" }
    }

    public enum PreviewState: Equatable, Sendable {
        case none
        case loading(String)
        case ready(Preview)
        case failed(String, message: String)
    }

    /// What the search field holds.
    public var text = ""
    /// Elements only: entries with these elements and no other.
    public var onlyTheseElements = false
    public private(set) var status: Status = .empty
    /// The chosen row's material id.
    public var selection: String?
    public private(set) var preview: PreviewState = .none

    /// Changes whenever a new search is due: the view runs `search()` in a task keyed on it.
    public var searchKey: SearchKey { SearchKey(text: text, only: onlyTheseElements, attempt: attempt) }

    public struct SearchKey: Hashable, Sendable {
        let text: String
        let only: Bool
        let attempt: Int
    }

    /// The library Add writes to (My Phases shows it).
    @ObservationIgnored public let library: PhaseLibrary
    @ObservationIgnored private let client: MaterialsProjectClient
    @ObservationIgnored private let keyStore: any APIKeyStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var answered: SearchKey?
    private var attempt = 0

    public init(library: PhaseLibrary, client: MaterialsProjectClient, keyStore: any APIKeyStore,
                now: @escaping () -> Date = Date.init) {
        self.library = library
        self.client = client
        self.keyStore = keyStore
        self.now = now
    }

    // MARK: Search

    /// The query the text asks for: a formula when it has a digit ("Al2Cu"), else element symbols ("Al Cu", "al, cu",
    /// "AlCu"); nil when nothing is typed. The kit checks the symbols and the formula.
    public nonisolated static func query(for text: String, only: Bool) -> MaterialsProjectOptimade.Query? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(where: \.isNumber) {
            return .formula(trimmed.filter { !$0.isWhitespace })
        }
        var symbols: [String] = []
        for token in trimmed.split(whereSeparator: { !$0.isLetter }) {
            if token.allSatisfy(\.isLowercase) {
                symbols.append(token.prefix(1).uppercased() + token.dropFirst())
                continue
            }
            var current = ""
            for ch in token {
                if ch.isUppercase, !current.isEmpty { symbols.append(current); current = "" }
                current.append(ch)
            }
            if !current.isEmpty { symbols.append(current) }
        }
        return .elements(symbols, only: only)
    }

    /// Runs the search the text asks for. Called from a task keyed on `searchKey`: a newer key cancels this one, and the
    /// client's typing pause sends only the last. Answered once per key, so a view that appears again sends nothing.
    public func search() async {
        let key = searchKey
        guard key != answered else { return }
        guard let query = Self.query(for: text, only: onlyTheseElements) else {
            status = .empty; answered = key; return
        }
        let request: URLRequest
        do {
            request = try MaterialsProjectOptimade.searchRequest(query)
        } catch {
            status = .problem(title: error.description, next: Self.typingHelp); answered = key; return
        }
        status = .searching
        do {
            // Elements without Only These Elements: the exact system is asked for first, as its own search, so elemental Si is
            // listed for "Si" although the service's page of every entry holding Si may not reach it (#1029).
            var exact: MaterialsProjectOptimade.SearchAnswer?
            if case .elements(let symbols, only: false) = query {
                let exactRequest = try MaterialsProjectOptimade.searchRequest(.elements(symbols, only: true))
                exact = try MaterialsProjectOptimade.decodeSearch(try await client.search(exactRequest, key: nil))
                if exact == .serviceEmpty { status = .serviceEmpty; answered = key; return }
            }
            let answer = try MaterialsProjectOptimade.decodeSearch(try await client.search(request, key: nil))
            switch (answer, exact) {
            case (.rows(let rows, let more), .rows(let exactRows, let exactMore)?):
                status = .results(Self.ranked(exactRows + rows, for: query), more: more || exactMore)
            case (.rows(let rows, let more), _):
                status = .results(Self.ranked(rows, for: query), more: more)
            case (_, .rows(let exactRows, let exactMore)?):
                status = .results(Self.ranked(exactRows, for: query), more: exactMore)
            case (.serviceEmpty, _): status = .serviceEmpty
            case (.noResults, _): status = .noResults
            }
            answered = key
        } catch let error as MaterialsProjectOptimade.RequestError {
            status = .problem(title: error.description, next: Self.typingHelp); answered = key
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            status = Self.status(for: error)
            answered = key
        }
    }

    /// The rows in the order the sheet lists them (#1029): an exact match first (an entry of exactly the typed elements, such as
    /// elemental Si for "Si", or of the typed formula), then fewer elements before more, then the most stable (the lowest energy
    /// above the hull the entry gives; none given last), then the id. A row listed twice (the exact search and the broad one) is
    /// kept once.
    public nonisolated static func ranked(_ rows: [MaterialsProjectOptimade.Row],
                                          for query: MaterialsProjectOptimade.Query) -> [MaterialsProjectOptimade.Row] {
        var seen = Set<String>()
        let unique = rows.filter { seen.insert($0.materialID).inserted }
        let wanted: Set<String>
        switch query {
        case .elements(let symbols, _): wanted = Set(symbols)
        case .formula(let formula): wanted = Set(elements(ofFormula: formula))
        }
        func key(_ row: MaterialsProjectOptimade.Row) -> (exact: Int, count: Int, hull: Double) {
            let held = row.formula.map { Set(elements(ofFormula: $0)) }
            return (held == wanted ? 0 : 1, held?.count ?? Int.max, row.lowestEnergyAboveHull ?? .infinity)
        }
        return unique.sorted { a, b in
            let ka = key(a), kb = key(b)
            if ka.exact != kb.exact { return ka.exact < kb.exact }
            if ka.count != kb.count { return ka.count < kb.count }
            if ka.hull != kb.hull { return ka.hull < kb.hull }
            return a.materialID < b.materialID
        }
    }

    /// The element symbols of a formula, in its order: "Co2ErSi2" gives Co, Er, Si.
    nonisolated static func elements(ofFormula formula: String) -> [String] {
        var symbols: [String] = []
        var current = ""
        for ch in formula where ch.isLetter {
            if ch.isUppercase, !current.isEmpty { symbols.append(current); current = "" }
            current.append(ch)
        }
        if !current.isEmpty { symbols.append(current) }
        return symbols
    }

    /// Searches again (offline, timed out, busy).
    public func retry() { attempt += 1 }

    nonisolated static let typingHelp = "Type element symbols, such as Al Cu, or a formula, such as Al2Cu."

    nonisolated static func status(for error: any Error) -> Status {
        if let failure = error as? MaterialsProjectClient.Failure {
            return failure == .offline ? .offline : .problem(title: title(for: failure), next: next(for: failure))
        }
        if let answer = error as? MaterialsProjectOptimade.AnswerError {
            return .problem(title: answer.description, next: "Try again later, or open a CIF of your own.")
        }
        return .problem(title: "The search failed: \(error.localizedDescription)", next: "Try again, or open a CIF of your own.")
    }

    nonisolated static func title(for failure: MaterialsProjectClient.Failure) -> String {
        switch failure {
        case .offline: "You're offline."
        case .timedOut: "The Materials Project didn't answer in time."
        case .keyRefused: "The Materials Project refused your API key."
        case .busy: "The Materials Project is busy."
        case .status(let code): "The Materials Project answered with an error (\(code))."
        case .notHTTP: "The Materials Project's answer could not be read."
        }
    }

    nonisolated static func next(for failure: MaterialsProjectClient.Failure) -> String {
        switch failure {
        case .offline: "Connect to the internet and try again, or open a CIF of your own."
        case .timedOut: "Try again in a moment."
        case .keyRefused: "Check the key in Settings, or remove it to use the open service."
        case .busy(let seconds?): "Wait \(Int(seconds.rounded(.up))) seconds and try again."
        case .busy(nil): "Wait a moment and try again."
        case .status, .notHTTP: "Try again later, or open a CIF of your own."
        }
    }

    /// The sentence pair the results area shows when there are no rows: what happened, and what to do next.
    public var statusMessage: (title: String, next: String)? {
        switch status {
        case .empty:
            return (title: "Search the Materials Project", next: Self.typingHelp + " Or open a CIF of your own.")
        case .searching, .results:
            return nil
        case .noResults:
            let next = onlyTheseElements
                ? "Nothing holds only these elements. Turn off Only These Elements, or check the symbols."
                : "Nothing on the Materials Project matches. Check the symbols, or search fewer elements."
            return (title: "No matches", next: next)
        case .serviceEmpty:
            return (title: "The Materials Project has no data right now",
                    next: "Its service answered with no structures at all. Try again later, or open a CIF of your own.")
        case .offline:
            return (title: "You're offline", next: Self.next(for: .offline))
        case .problem(let title, let next):
            return (title: title, next: next)
        }
    }

    // MARK: Preview and Add

    /// Downloads and reads the chosen entry. Called from a task keyed on `selection`.
    public func loadPreview() async {
        guard let id = selection else { preview = .none; return }
        switch preview {
        case .ready(let p) where p.materialID == id: return
        default: break
        }
        preview = .loading(id)
        let stored: String? = (try? await keyStore.loadInBackground()) ?? nil
        let key = (stored?.isEmpty ?? true) ? nil : stored
        do {
            let request: URLRequest
            if let key {
                request = try MaterialsProjectImport.request(materialID: id, apiKey: key)
            } else {
                request = try MaterialsProjectOptimade.entryRequest(materialID: id)
            }
            let data = try await client.download(request, key: key)
            let imported = try await Self.read(data, keyed: key != nil)
            guard selection == id else { return }
            preview = .ready(Preview(materialID: id, name: name(for: id, imported.structure), structure: imported.structure,
                                     converted: imported.cell != .asServed, source: data))
        } catch is CancellationError {
            return
        } catch {
            guard selection == id, !Task.isCancelled else { return }
            let message: String
            switch error {
            case let failure as MaterialsProjectClient.Failure: message = Self.title(for: failure) + " " + Self.next(for: failure)
            case let failure as MaterialsProjectImport.Failure: message = failure.errorDescription ?? "\(failure)"
            case let failure as MaterialsProjectOptimade.AnswerError: message = failure.description
            case let failure as MaterialsProjectOptimade.RequestError: message = failure.description
            default: message = "The entry could not be read: \(error.localizedDescription)"
            }
            preview = .failed(id, message: message)
        }
    }

    /// The kit reads the answer off the main actor (the symmetry is detected from the atoms).
    @concurrent nonisolated static func read(_ data: Data, keyed: Bool) async throws -> MaterialsProjectImport.ImportedStructure {
        if keyed {
            let doc = try MaterialsProjectImport.firstDocument(in: MaterialsProjectImport.decode(data))
            return try MaterialsProjectImport.structure(from: doc)
        }
        return try MaterialsProjectOptimade.structure(from: MaterialsProjectOptimade.decodeEntry(data))
    }

    /// The phase's name before it is added: the reduced formula of the structure read ("Si", never the bare id "mp-149"), the same
    /// whether the entry was found by a search or added by its id; the search row's formula (in `displayFormula` order) and then
    /// the id only when the structure gives none (partial occupancy). The rows of the results write their formula in the same
    /// order (#1115), so a row and its preview read alike.
    private func name(for id: String, _ structure: CrystalStructure) -> String {
        if let formula = Self.reducedFormula(of: structure) { return formula }
        if case .results(let rows, _) = status, let formula = rows.first(where: { $0.materialID == id })?.formula {
            return Self.displayFormula(formula)
        }
        return structure.name ?? id
    }

    /// The reduced formula of the structure's content, elements by increasing electronegativity as pymatgen's `reduced_formula` writes it (SiO2,
    /// Fe2O3, GaN; `PaulingElectronegativity`) and a count of 1 left out; nil when the counts are not whole numbers (partial occupancy).
    /// The search rows write the service's formula in the same order (`displayFormula`).
    nonisolated static func reducedFormula(of structure: CrystalStructure) -> String? {
        var counts: [String: Double] = [:]
        for site in structure.sites {
            guard let symbol = Element.symbol(forAtomicNumber: site.z) else { return nil }
            counts[symbol, default: 0] += site.occupancy
        }
        guard !counts.isEmpty else { return nil }
        var whole: [String: Int] = [:]
        for (symbol, n) in counts {
            guard n.isFinite, n > 0, n < 1e9, abs(n - n.rounded()) < 1e-6 else { return nil }
            whole[symbol] = Int(n.rounded())
        }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let divisor = whole.values.reduce(0, gcd)
        guard divisor > 0 else { return nil }
        return PaulingElectronegativity.ordered(Array(whole.keys)).map { symbol in
            let n = whole[symbol]! / divisor
            return n == 1 ? symbol : "\(symbol)\(n)"
        }.joined()
    }

    /// A search row's formula as the sheet writes it (#1115): the service's reduced formula, which OPTIMADE writes in alphabetical
    /// order ("AsGa", "AsGa3"), with its elements in the order `reducedFormula(of:)` gives the preview's name ("GaAs", "Ga3As"). Each
    /// count stays as the service wrote it; nothing is reduced or sent. Text that is not element symbols with counts (a symbol
    /// twice, a stray character, a count that starts with 0) comes back unchanged.
    public nonisolated static func displayFormula(_ formula: String) -> String {
        var parts: [(symbol: String, count: String)] = []
        var rest = formula[...]
        while let first = rest.first {
            guard first.isASCII, first.isUppercase else { return formula }
            var symbol = String(first)
            rest = rest.dropFirst()
            while let ch = rest.first, ch.isASCII, ch.isLowercase { symbol.append(ch); rest = rest.dropFirst() }
            var count = ""
            while let ch = rest.first, ch.isASCII, ch.isNumber { count.append(ch); rest = rest.dropFirst() }
            guard symbol.count <= 3, !count.hasPrefix("0") else { return formula }
            parts.append((symbol: symbol, count: count))
        }
        let counts = Dictionary(parts.map { ($0.symbol, $0.count) }, uniquingKeysWith: { first, _ in first })
        guard !parts.isEmpty, counts.count == parts.count else { return formula }
        return PaulingElectronegativity.ordered(Array(counts.keys)).map { $0 + (counts[$0] ?? "") }.joined()
    }

    /// The name the library stores: the formula, and the space-group symbol after it only where another phase of the library
    /// already has that formula ("Si", then "Si (P6_3/mmc)"); the id when the symbol is not known either. The names already in the
    /// library are never changed. A name that is the id (no formula could be made) is kept as it is.
    nonisolated static func libraryName(formula: String, symbol: String?, id: String, existing: [String]) -> String {
        guard formula != id else { return formula }
        func shares(_ name: String) -> Bool { name == formula || name.hasPrefix(formula + " (") }
        guard existing.contains(where: shares) else { return formula }
        let withSymbol = symbol.map { "\(formula) (\($0))" }
        if let withSymbol, !existing.contains(withSymbol) { return withSymbol }
        return "\(formula) (\(id))"
    }

    /// The previewed entry is already in the library (Add reads "In Library").
    public var isInLibrary: Bool {
        guard case .ready(let p) = preview else { return false }
        return library.phase(materialsProjectID: p.materialID) != nil
    }

    public var canAdd: Bool {
        if case .ready = preview { return !isInLibrary }
        return false
    }

    /// Adds the previewed entry, with the bytes it came as, and returns it. The phase's id is its Materials Project id.
    @discardableResult
    public func add() throws -> Phase? {
        guard case .ready(let p) = preview, !isInLibrary else { return nil }
        let symbol = SpaceGroupType.of(p.structure.operations)?.internationalSymbol
            ?? p.structure.spaceGroupNumber.map { "No. \($0)" }
        let name = Self.libraryName(formula: p.name, symbol: symbol, id: p.materialID, existing: library.phases.map(\.name))
        let phase = Phase(id: p.materialID, name: name, source: .materialsProject(id: p.materialID, fetched: now()),
                          added: now(), structure: p.structure)
        try library.add(phase, source: p.source, sourceExtension: "json")
        return phase
    }
}
