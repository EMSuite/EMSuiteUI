//
//  MyPhasesView.swift
//  Role: My Phases, the library's own page in the Add Phase sheet (EMSuiteUI#191, plan sections 3 and 9): the phases on
//        this Mac on the left, the chosen one's details on the right: its name and notes to edit, where it came from with
//        its credit, its lattice (edited in the room's inspector, not here), Reset to Source and Delete. Records the library
//        could not read are listed with their reason, never dropped in silence.
//

import DiffractoCore
import ShellPhaseLibrary
import SwiftUI

public struct MyPhasesView: View {
    let library: PhaseLibrary
    @State private var selection: String?

    public init(library: PhaseLibrary, selection: String? = nil) {
        self.library = library
        _selection = State(initialValue: selection)
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if library.phases.isEmpty {
                    ContentUnavailableView("No Phases Yet", systemImage: "cube.transparent",
                                           description: Text("Search the Materials Project or open a CIF to add one."))
                } else {
                    List(library.phases, selection: $selection) { phase in
                        MyPhasesRow(phase: phase)
                    }
                    .accessibilityLabel("My phases")
                    .accessibilityIdentifier("myPhases.list")
                }
                if !library.unreadable.isEmpty {
                    SheetWarning("Could not be read: " + library.unreadable.joined(separator: "; "))
                        .lineLimit(3)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("myPhases.unreadable")
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Group {
                if let id = selection, library.phases.contains(where: { $0.id == id }) {
                    PhaseDetails(library: library, phaseID: id) { selection = nil }
                        .id(id)
                } else {
                    ContentUnavailableView("No Phase Chosen", systemImage: "list.bullet.rectangle",
                                           description: Text("Choose a phase to rename it, add notes or reset it to its source."))
                }
            }
            .frame(minWidth: 280, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One phase: name, source and whether its lattice was edited.
struct MyPhasesRow: View {
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(phase.name).font(.body.weight(.medium))
            HStack(spacing: 6) {
                Text(Self.source(phase.source)).font(.caption).foregroundStyle(.secondary)
                if phase.isEdited { Text("Edited").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("myPhases.row.\(phase.id)")
    }

    /// "mp-134" for a Materials Project entry, the file name for a CIF.
    static func source(_ source: PhaseSource) -> String {
        switch source {
        case .materialsProject(let id, _): id
        case .cif(let fileName): fileName
        }
    }
}

/// The chosen phase: name and notes, source and credit, lattice, Reset to Source and Delete.
struct PhaseDetails: View {
    let library: PhaseLibrary
    let phaseID: String
    let onDeleted: () -> Void
    @State private var name = ""
    @State private var notes = ""
    @State private var problem: String?
    @State private var confirmDelete = false
    @State private var resetting = false

    var body: some View {
        if let phase = library.phases.first(where: { $0.id == phaseID }) {
            let cell = phase.structure().cell
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit { commitName() }
                        .accessibilityIdentifier("myPhases.name")
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .onSubmit { commitNotes() }
                        .accessibilityIdentifier("myPhases.notes")
                }
                Section("Source") {
                    LabeledContent("From", value: Self.from(phase.source))
                    if let attribution = phase.source.attribution {
                        if let url = phase.source.pageURL {
                            Link(attribution, destination: url).font(.caption).accessibilityIdentifier("myPhases.attribution")
                        } else {
                            Text(attribution).font(.caption)
                        }
                    }
                    LabeledContent("Added", value: phase.added.formatted(date: .abbreviated, time: .omitted))
                }
                Section("Lattice") {
                    LabeledContent("a, b, c", value: String(format: "%.4f, %.4f, %.4f Å", cell.a, cell.b, cell.c))
                    LabeledContent("α, β, γ", value: String(format: "%.2f°, %.2f°, %.2f°", cell.alphaDeg, cell.betaDeg, cell.gammaDeg))
                    Text(phase.isEdited ? "Edited in a room's inspector." : "As its source gives it. Edit it in a room's inspector.")
                        .font(.caption).foregroundStyle(.secondary)
                    if phase.isEdited {
                        Button("Reset to Source") { reset() }
                            .disabled(resetting)
                            .accessibilityIdentifier("myPhases.reset")
                    }
                }
                Section {
                    Button("Delete Phase…", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("myPhases.delete")
                    if let problem { SheetWarning(problem) }
                }
            }
            .formStyle(.grouped)
            .onAppear { name = phase.name; notes = phase.notes }
            .onDisappear { commitName(); commitNotes() }
            .confirmationDialog("Delete \(phase.name)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("It is removed from this Mac's library with its source file. A document that used it keeps its own copy.")
            }
        }
    }

    /// "Materials Project" or "CIF file beta.cif".
    static func from(_ source: PhaseSource) -> String {
        switch source {
        case .materialsProject: "Materials Project"
        case .cif(let fileName): "CIF file \(fileName)"
        }
    }

    private func commitName() {
        guard let phase = library.phases.first(where: { $0.id == phaseID }), name != phase.name else { return }
        do { _ = try library.rename(phaseID, to: name); problem = nil } catch {
            problem = String(describing: error); name = phase.name
        }
    }

    private func commitNotes() {
        guard let phase = library.phases.first(where: { $0.id == phaseID }), notes != phase.notes else { return }
        do { _ = try library.setNotes(notes, of: phaseID); problem = nil } catch { problem = String(describing: error) }
    }

    private func reset() {
        resetting = true
        Task {
            defer { resetting = false }
            do { _ = try await library.resetToSource(phaseID); problem = nil } catch { problem = String(describing: error) }
        }
    }

    private func delete() {
        do { try library.remove(id: phaseID); onDeleted() } catch {
            problem = "The phase could not be deleted: \(error.localizedDescription)"
        }
    }
}
