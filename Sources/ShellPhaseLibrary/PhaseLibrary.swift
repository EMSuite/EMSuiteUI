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

    public init(store: PhaseLibraryStore) { self.store = store }

    /// Reads the library from disk.
    public func load() async {
        let store = self.store
        let entries = await Task.detached(priority: .userInitiated) { store.entries() }.value
        var read: [Phase] = [], failed: [String] = []
        for entry in entries {
            do { read.append(try Phase.decoded(entry.record)) } catch {
                failed.append("\(entry.id): \(error)")
            }
        }
        phases = read.sorted { $0.added > $1.added }
        unreadable = failed
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
    }

    /// The raw source of a phase as it was added, for Reset to Source and Show in Finder.
    public func sourceFile(of id: String) -> URL? {
        store.sourceFile(id: id)
    }
}
