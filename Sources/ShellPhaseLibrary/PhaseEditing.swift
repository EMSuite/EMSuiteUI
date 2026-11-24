//
//  PhaseEditing.swift
//  Role: the changes a person makes to a phase of the library (EMSuiteUI#191, plan section 3): its name and notes, its lattice
//        parameters, and Reset to Source. The lattice is changed by DiffractoKit (`editingLattice`): only the parameters the
//        symmetry leaves free, the tied ones following, a change of Laue class refused in the kit's words. Reset to Source reads
//        the stored source again with the importer it was added with, so an edit is undone with the kit's own reading. Every
//        change is written to the library's folder before it is shown.
//

import DiffractoCore
import Foundation

/// Why a change to a phase was not made, as a sentence for a scientist.
public enum PhaseEditError: Error, Equatable, Sendable, CustomStringConvertible {
    case notInLibrary(String)
    case lattice(LatticeEditError)
    case emptyName
    case sourceMissing(String)
    case sourceUnreadable(String)
    case notWritten(String)

    public var description: String {
        switch self {
        case .notInLibrary(let id): "\(id) is no longer in the library."
        case .lattice(let error): error.description
        case .emptyName: "A phase needs a name."
        case .sourceMissing(let id): "The source \(id) was added from is missing from the library's folder, so it cannot be reset."
        case .sourceUnreadable(let why): "The source could not be read again: \(why)"
        case .notWritten(let why): "The library could not be written: \(why)"
        }
    }
}

extension PhaseLibrary {

    private func stored(_ id: String) throws(PhaseEditError) -> Phase {
        guard let phase = phases.first(where: { $0.id == id }) else { throw .notInLibrary(id) }
        return phase
    }

    private func write(_ phase: Phase) throws(PhaseEditError) {
        do { try update(phase) } catch { throw .notWritten(error.localizedDescription) }
    }

    /// Sets some of a phase's free lattice parameters; the rest follow the symmetry. Returns the phase as written.
    @discardableResult
    public func setLattice(_ values: [LatticeParameter: Double], of id: String) throws(PhaseEditError) -> Phase {
        var phase = try stored(id)
        let edited: CrystalStructure
        do throws(LatticeEditError) { edited = try phase.structure().editingLattice(values) } catch { throw .lattice(error) }
        phase.replaceStructure(edited)
        try write(phase)
        return phase
    }

    /// Gives a phase another name (trimmed; never empty).
    @discardableResult
    public func rename(_ id: String, to name: String) throws(PhaseEditError) -> Phase {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        var phase = try stored(id)
        guard phase.name != trimmed else { return phase }
        phase.name = trimmed
        try write(phase)
        return phase
    }

    /// Sets a phase's notes.
    @discardableResult
    public func setNotes(_ notes: String, of id: String) throws(PhaseEditError) -> Phase {
        var phase = try stored(id)
        guard phase.notes != notes else { return phase }
        phase.notes = notes
        try write(phase)
        return phase
    }

    /// Reset to Source: the structure read again from the bytes the phase was added from. Name and notes stay.
    @discardableResult
    public func resetToSource(_ id: String) async throws(PhaseEditError) -> Phase {
        let phase = try stored(id)
        guard let url = sourceFile(of: id) else { throw .sourceMissing(id) }
        let structure = try await Self.readSource(at: url, source: phase.source)
        var reset = try stored(id)
        reset.resetStructure(to: structure)
        try write(reset)
        return reset
    }

    /// The structure in a stored source, read by the importer it came through: a CIF by DiffractoKit's CIF loader; a
    /// Materials Project answer by the open service's decoder, or the keyed one's when it came with the person's key.
    @concurrent nonisolated static func readSource(at url: URL, source: PhaseSource) async throws(PhaseEditError) -> CrystalStructure {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw .sourceUnreadable(error.localizedDescription) }
        switch source {
        case .cif(let fileName):
            do { return try CrystalLoading.load(bytes: data, fileName: fileName).structure } catch {
                throw .sourceUnreadable(error.localizedDescription)
            }
        case .materialsProject:
            if let entry = try? MaterialsProjectOptimade.decodeEntry(data),
               let imported = try? MaterialsProjectOptimade.structure(from: entry) {
                return imported.structure
            }
            do {
                let doc = try MaterialsProjectImport.firstDocument(in: MaterialsProjectImport.decode(data))
                return try MaterialsProjectImport.structure(from: doc).structure
            } catch {
                throw .sourceUnreadable(error.localizedDescription)
            }
        }
    }
}
