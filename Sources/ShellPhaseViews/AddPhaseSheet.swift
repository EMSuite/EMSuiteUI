//
//  AddPhaseSheet.swift
//  Role: the Add Phase sheet both apps show (EMSuiteUI#189, plan section 5.2), first slice: a search field that has the
//        focus, the matches, a preview of the chosen entry with its id and licence, Add, and Open CIF…, which closes the
//        sheet before the app shows its file dialog. Resizable. Everything it says comes from `AddPhaseModel`.
//        The preview opens with a still picture of the entry's unit cell (EMSuiteUI#195, `AddPhaseCellPicture`). Its second
//        page is My Phases (EMSuiteUI#191): the library's phases, their names, notes, Reset to Source and Delete.
//

import DiffractoCore
import ShellPhaseLibrary
import SwiftUI

public struct AddPhaseSheet: View {
    @Bindable var model: AddPhaseModel
    let onOpenCIF: () -> Void
    let onAdded: (Phase) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var addError: String?
    @State private var page: Page

    /// The sheet's two pages.
    public enum Page: String, CaseIterable, Sendable {
        case search = "Materials Project"
        case mine = "My Phases"
    }

    /// `onOpenCIF` runs after the sheet has closed, so the app's Open panel never sits on top of it.
    public init(model: AddPhaseModel, page: Page = .search, onOpenCIF: @escaping () -> Void,
                onAdded: @escaping (Phase) -> Void = { _ in }) {
        self.model = model
        self.onOpenCIF = onOpenCIF
        self.onAdded = onAdded
        _page = State(initialValue: page)
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            switch page {
            case .search:
                HStack(spacing: 0) {
                    results
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    AddPhasePreview(state: model.preview, inLibrary: model.isInLibrary)
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            case .mine:
                MyPhasesView(library: model.library)
            }
            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 720, maxWidth: .infinity, minHeight: 400, idealHeight: 500, maxHeight: .infinity)
        .onAppear { searchFocused = page == .search }
        .onChange(of: page) { searchFocused = page == .search }
        .task(id: model.searchKey) { await model.search() }
        .task(id: model.selection) { await model.loadPreview() }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Picker("Page", selection: $page) {
                ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Show")
            .accessibilityIdentifier("addPhase.page")
            if page == .search { searchFields } else { Spacer() }
        }
        .padding(12)
    }

    @ViewBuilder private var searchFields: some View {
        TextField("Elements or formula, such as Al Cu or Al2Cu", text: $model.text)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .accessibilityLabel("Search the Materials Project")
            .accessibilityIdentifier("addPhase.search")
        Toggle("Only These Elements", isOn: $model.onlyTheseElements)
            .toggleStyle(.checkbox)
            .help("Find entries with these elements and no other")
            .accessibilityIdentifier("addPhase.onlyTheseElements")
    }

    @ViewBuilder private var results: some View {
        switch model.status {
        case .results(let rows, let more):
            VStack(spacing: 0) {
                List(rows, id: \.materialID, selection: $model.selection) { row in
                    AddPhaseRow(row: row)
                }
                .accessibilityLabel("Matches")
                .accessibilityIdentifier("addPhase.results")
                if more {
                    Text("More matches than shown. Add an element or type a formula to narrow the search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .searching:
            ProgressView("Searching…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("addPhase.searching")
        default:
            if let message = model.statusMessage {
                ContentUnavailableView {
                    Label(message.title, systemImage: symbol)
                } description: {
                    Text(message.next)
                } actions: {
                    if canRetry {
                        Button("Try Again") { model.retry() }
                            .accessibilityIdentifier("addPhase.retry")
                    }
                }
                .accessibilityIdentifier("addPhase.status")
            }
        }
    }

    private var symbol: String {
        switch model.status {
        case .empty: "magnifyingglass"
        case .offline: "wifi.slash"
        case .noResults: "questionmark.circle"
        case .serviceEmpty: "tray"
        default: "exclamationmark.triangle"
        }
    }

    private var canRetry: Bool {
        switch model.status {
        case .offline, .serviceEmpty, .problem: true
        default: false
        }
    }

    private var footer: some View {
        HStack {
            Button("Open CIF…") { Self.openCIF(dismiss: { dismiss() }, open: onOpenCIF) }
                .help("Close this sheet and choose a CIF file on your Mac")
                .accessibilityIdentifier("addPhase.openCIF")
            if let addError {
                SheetWarning(addError).lineLimit(2)
            }
            Spacer()
            if page == .search {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("addPhase.cancel")
                Button(model.isInLibrary ? "In Library" : "Add Phase") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdd)
                    .accessibilityLabel(model.isInLibrary ? "Already in your library" : "Add to your library")
                    .accessibilityIdentifier("addPhase.add")
            } else {
                // Edits here save as they are made, so the way out confirms nothing: Close, on the cancel key, so Escape closes
                // this page too and Return stays with the field being edited.
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("addPhase.close")
            }
        }
        .padding(12)
    }

    private func add() {
        do {
            if let phase = try model.add() {
                onAdded(phase)
                dismiss()
            }
        } catch {
            addError = "The phase could not be saved: \(error.localizedDescription)"
        }
    }

    /// Closes the sheet first and opens the file dialog on the next turn of the main actor, once the sheet is gone.
    static func openCIF(dismiss: () -> Void, open: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in open() }
    }
}

/// One match: formula, id and space group, energy above the hull and site count.
struct AddPhaseRow: View {
    let row: MaterialsProjectOptimade.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(row)).font(.body.weight(.medium))
                Text(Self.caption(row)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.stability(row.lowestEnergyAboveHull)).font(.caption).monospacedDigit()
                if let n = row.siteCount { Text(Self.sites(n)).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("addPhase.row.\(row.materialID)")
    }

    static func sites(_ n: Int) -> String { n == 1 ? "1 site" : "\(n) sites" }

    /// The row's symmetry, so polymorphs tell apart before one is chosen (zincblende and wurtzite GaAs; #1115): the space group's
    /// short symbol and IT number as the kit reads them from the row's atoms, or the crystal system where no group shows; nil
    /// where the answer carried no structure.
    static func symmetry(_ row: MaterialsProjectOptimade.Row) -> String? {
        guard let symmetry = row.symmetry else { return nil }
        if let symbol = symmetry.symbol, let number = symmetry.number { return "\(symbol) (\(number))" }
        return symmetry.crystalSystem
    }

    /// The caption under the formula: the id, then the symmetry where there is one ("mp-2534 · F-43m (216)").
    static func caption(_ row: MaterialsProjectOptimade.Row) -> String {
        symmetry(row).map { "\(row.materialID) · \($0)" } ?? row.materialID
    }

    /// The row's formula in the order the preview's name writes it ("GaAs", not the service's "AsGa"; #1115), else its id.
    static func title(_ row: MaterialsProjectOptimade.Row) -> String {
        row.formula.map { AddPhaseModel.displayFormula($0) } ?? row.materialID
    }

    /// "Stable" on the hull, else its height above it in eV per atom.
    static func stability(_ energy: Double?) -> String {
        guard let energy else { return "No stability data" }
        if energy <= 0.0005 { return "Stable" }
        return String(format: "%.3f eV/atom above hull", energy)
    }
}

/// The chosen entry: a still picture of its unit cell, name, id and licence, cell and symmetry, as the kit read them, and a note
/// that the cell is a computed one.
struct AddPhasePreview: View {
    let state: AddPhaseModel.PreviewState
    let inLibrary: Bool

    var body: some View {
        Group {
            switch state {
            case .none:
                ContentUnavailableView("No Entry Chosen", systemImage: "cube.transparent",
                                       description: Text("Choose a match to see its cell before you add it."))
            case .loading(let id):
                ProgressView("Downloading \(id)…").controlSize(.small)
            case .failed(let id, let message):
                ContentUnavailableView {
                    Label("\(id) could not be read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            case .ready(let preview):
                details(preview)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("addPhase.preview")
    }

    private func details(_ p: AddPhaseModel.Preview) -> some View {
        let cell = p.structure.cell
        return Form {
            Section {
                AddPhaseCellPicture(preview: p)
            }
            Section {
                LabeledContent("Name", value: p.name)
                LabeledContent("Formula", value: p.structure.formula)
                if let number = p.structure.spaceGroupNumber { LabeledContent("Space group", value: "No. \(number)") }
                if let system = p.structure.crystalSystem { LabeledContent("Crystal system", value: "\(system)".capitalized) }
            }
            Section("Cell") {
                LabeledContent("a, b, c", value: LatticeText.lengths(cell.a, cell.b, cell.c))
                LabeledContent("α, β, γ", value: LatticeText.angles(cell.alphaDeg, cell.betaDeg, cell.gammaDeg))
                LabeledContent("Atoms in cell", value: "\(p.structure.sites.count)")
                if p.converted {
                    Text("Served as a primitive cell; shown as the conventional cell.").font(.caption).foregroundStyle(.secondary)
                }
                Text(Self.computedCellNote).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if let url = URL(string: "https://next-gen.materialsproject.org/materials/\(p.materialID)") {
                    Link(p.attribution, destination: url)
                        .font(.caption)
                        .accessibilityIdentifier("addPhase.attribution")
                }
                if inLibrary { Text("Already in your library.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    /// Every preview is a Materials Project entry (a CIF of the person's own opens after the sheet has closed, never here), and
    /// its cell is the one the Materials Project computed (#1115).
    static let computedCellNote =
        "The Materials Project's computed (relaxed) cell; lattice parameters can differ from measured ones by a percent or two."
}
