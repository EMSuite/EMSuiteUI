//
//  PhaseLatticeFields.swift
//  Role: the lattice of the phase in use, as fields a room's inspector shows (EMSuiteUI#191, plan section 9: "the lattice
//        fields sit in the room's inspector for the phase in use, … never in a second sheet"). Only the parameters the
//        phase's symmetry leaves free get a field; the tied ones follow. An edit is written to the library at once and marks
//        the phase edited; Reset to Source reads the source again. The app places these rows inside its own section and is
//        told of every change, so the room takes the edited phase as its own copy.
//

import DiffractoCore
import ShellInspector
import ShellPhaseLibrary
import SwiftUI

public struct PhaseLatticeFields: View {
    let library: PhaseLibrary
    let phaseID: String
    let onChange: (Phase) -> Void
    @State private var problem: String?
    @State private var resetting = false

    /// `onChange` gets the phase as written after each edit or reset.
    public init(library: PhaseLibrary, phaseID: String, onChange: @escaping (Phase) -> Void = { _ in }) {
        self.library = library
        self.phaseID = phaseID
        self.onChange = onChange
    }

    public var body: some View {
        if let phase = library.phases.first(where: { $0.id == phaseID }) {
            let structure = phase.structure()
            let free = Self.fields(for: structure)
            ForEach(free, id: \.self) { parameter in
                InspectorRow(Self.label(parameter)) {
                    OptionalNumericField(title: "\(Self.spoken(parameter)) of \(phase.name)", value: Self.value(parameter, of: structure.cell),
                                         format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...5)),
                                         unit: Self.isLength(parameter) ? "Å" : "°") { set(parameter, to: $0) }
                        .help(Self.help(parameter, free: free))
                        .accessibilityIdentifier("phase.lattice.\(parameter.rawValue)")
                }
            }
            if free.isEmpty {
                InspectorNote("The symmetry of \(phase.name) was not read, so its lattice cannot be edited here.")
            }
            if phase.isEdited {
                InspectorActionRow {
                    Text("Edited").font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("phase.lattice.edited")
                    Button("Reset to Source") { reset() }
                        .disabled(resetting)
                        .help("Read the lattice again from the file or entry this phase was added from")
                        .accessibilityIdentifier("phase.lattice.reset")
                }
            }
            if let problem { InspectorWarning(problem) }
        }
    }

    /// The parameters that get a field: the free ones, in the order a, b, c, α, β, γ.
    nonisolated static func fields(for structure: CrystalStructure) -> [LatticeParameter] {
        structure.freeLatticeParameters
    }

    nonisolated static func isLength(_ p: LatticeParameter) -> Bool { p == .a || p == .b || p == .c }

    nonisolated static func label(_ p: LatticeParameter) -> String { p.description }

    nonisolated static func spoken(_ p: LatticeParameter) -> String {
        switch p {
        case .a, .b, .c: "Lattice parameter \(p.rawValue)"
        case .alpha: "Angle alpha"
        case .beta: "Angle beta"
        case .gamma: "Angle gamma"
        }
    }

    nonisolated static func value(_ p: LatticeParameter, of cell: UnitCell) -> Double {
        switch p {
        case .a: cell.a
        case .b: cell.b
        case .c: cell.c
        case .alpha: cell.alphaDeg
        case .beta: cell.betaDeg
        case .gamma: cell.gammaDeg
        }
    }

    /// "a; b and c follow it" for a parameter that moves others.
    nonisolated static func help(_ p: LatticeParameter, free: [LatticeParameter]) -> String {
        let tiedLengths = isLength(p) ? [LatticeParameter.a, .b, .c].filter { $0 != p && !free.contains($0) } : []
        guard !tiedLengths.isEmpty else { return "Set \(p.description); the atoms keep their fractional positions" }
        return "Set \(p.description); \(tiedLengths.map(\.description).joined(separator: " and ")) follow it by symmetry"
    }

    private func set(_ parameter: LatticeParameter, to value: Double) {
        do {
            onChange(try library.setLattice([parameter: value], of: phaseID))
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }

    private func reset() {
        resetting = true
        Task {
            defer { resetting = false }
            do {
                onChange(try await library.resetToSource(phaseID))
                problem = nil
            } catch {
                problem = String(describing: error)
            }
        }
    }
}
