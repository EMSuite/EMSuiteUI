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
        /// Matches, the most stable first; `more`: the service holds more than it returned.
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
            let data = try await client.search(request, key: nil)
            switch try MaterialsProjectOptimade.decodeSearch(data) {
            case .rows(let rows, let more): status = .results(rows, more: more)
            case .noResults: status = .noResults
            case .serviceEmpty: status = .serviceEmpty
            }
            answered = key
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            status = Self.status(for: error)
            answered = key
        }
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

    private func name(for id: String, _ structure: CrystalStructure) -> String {
        if case .results(let rows, _) = status, let formula = rows.first(where: { $0.materialID == id })?.formula { return formula }
        return structure.name ?? id
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
        let phase = Phase(id: p.materialID, name: p.name, source: .materialsProject(id: p.materialID, fetched: now()),
                          added: now(), structure: p.structure)
        try library.add(phase, source: p.source, sourceExtension: "json")
        return phase
    }
}
