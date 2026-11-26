//
//  PhaseLibrary.swift
//  Role: the phase library the app shows (EMSuiteUI#188): every phase the person added, read from `PhaseLibraryStore` and
//        written back on each change. One per app, in the environment; the rooms read it, the Add Phase sheet adds to it.
//        Main-actor and observed for the views; the files are read off the main actor.
//

import DiffractoCore
import Foundation
import Observation

@MainActor
@Observable
public final class PhaseLibrary {
    /// Newest first.
    public private(set) var phases: [Phase] = []
    /// A sentence per record that could not be read (a newer schema, a damaged file), shown, never silently dropped.
    public private(set) var unreadable: [String] = []

    @ObservationIgnored private let store: PhaseLibraryStore
    /// Ids removed since the last `load()` began, so a read that started before the removal does not bring them back.
    @ObservationIgnored private var removedWhileLoading: Set<String> = []

    public init(store: PhaseLibraryStore) { self.store = store }

    /// Reads the library from disk. A phase added or removed while the read was under way keeps that change: the phases in
    /// memory win over what the read found, and one removed meanwhile does not come back (EMSuiteUI#231).
    public func load() async {
        let store = self.store
        removedWhileLoading = []
        let entries = await Task.detached(priority: .userInitiated) { store.entries() }.value
        var read: [Phase] = [], failed: [String] = []
        for entry in entries {
            do { read.append(try Phase.decoded(entry.record)) } catch {
                failed.append("\(entry.id): \(error)")
            }
        }
        let named = Self.namedByFormula(read, save: { try? store.save(id: $0.id, record: Phase.encoded($0)) })
        phases = Self.merged(read: named, inMemory: phases, removed: removedWhileLoading)
        unreadable = failed
    }

    /// The read phases with the ones in memory laid over them by id, less those removed meanwhile, newest first.
    nonisolated static func merged(read: [Phase], inMemory: [Phase], removed: Set<String>) -> [Phase] {
        var byID = Dictionary(read.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for phase in inMemory { byID[phase.id] = phase }
        for id in removed { byID[id] = nil }
        return byID.values.sorted { ($0.added, $0.id) > ($1.added, $1.id) }
    }

    /// A Materials Project phase still named by its bare id ("mp-149", as Add named it before EMSuiteUI#250) takes the name Add
    /// gives now: its reduced formula, with the space group only where another phase already has that formula. A name the
    /// person typed is never the bare id, so it is never changed; each renamed record is written back once.
    nonisolated static func namedByFormula(_ phases: [Phase], save: (Phase) -> Void) -> [Phase] {
        var out = phases
        for i in out.indices {
            guard case .materialsProject(let id, _) = out[i].source, out[i].name == id else { continue }
            let structure = out[i].structure()
            guard let formula = AddPhaseModel.reducedFormula(of: structure) else { continue }
            let symbol = SpaceGroupType.of(structure.operations)?.internationalSymbol ?? structure.spaceGroupNumber.map { "No. \($0)" }
            let others = out.indices.filter { $0 != i }.map { out[$0].name }
            out[i].name = AddPhaseModel.libraryName(formula: formula, symbol: symbol, id: id, existing: others)
            save(out[i])
        }
        return out
    }

    /// The phase already in the library for this Materials Project id, if any (Add shows "In Library" instead).
    public func phase(materialsProjectID id: String) -> Phase? {
        phases.first { if case .materialsProject(let mp, _) = $0.source { mp == id } else { false } }
    }

    /// Adds a phase with the raw source it came from (the fetched JSON, or the CIF's bytes).
    public func add(_ phase: Phase, source: Data, sourceExtension: String) throws {
        try store.save(id: phase.id, record: Phase.encoded(phase), source: source, sourceExtension: sourceExtension)
        phases.removeAll { $0.id == phase.id }
        phases.insert(phase, at: 0)
    }

    /// Writes a changed phase (name, notes, an edited or reset lattice).
    public func update(_ phase: Phase) throws {
        guard let i = phases.firstIndex(where: { $0.id == phase.id }) else { return }
        try store.save(id: phase.id, record: Phase.encoded(phase))
        phases[i] = phase
    }

    public func remove(id: String) throws {
        try store.remove(id: id)
        phases.removeAll { $0.id == id }
        removedWhileLoading.insert(id)
    }

    /// The raw source of a phase as it was added, for Reset to Source and Show in Finder.
    public func sourceFile(of id: String) -> URL? {
        store.sourceFile(id: id)
    }
}
