//
//  AddPhaseSheet.swift
//  Role: the Add Phase sheet both apps show (EMSuiteUI#189, plan section 5.2), first slice: a search field that has the
//        focus, the matches, a preview of the chosen entry with its id and licence, Add, and Open CIF…, which closes the
//        sheet before the app shows its file dialog. Resizable. Everything it says comes from `AddPhaseModel`. Its second
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
                Text(addError).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            Spacer()
            if page == .search {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("addPhase.cancel")
                Button(model.isInLibrary ? "In Library" : "Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdd)
                    .accessibilityLabel(model.isInLibrary ? "Already in your library" : "Add to your library")
                    .accessibilityIdentifier("addPhase.add")
            } else {
                // The cancel action, so Escape closes this page too and Return stays with the field being edited.
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("addPhase.done")
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

/// One match: formula, id, energy above the hull and site count.
struct AddPhaseRow: View {
    let row: MaterialsProjectOptimade.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.formula ?? row.materialID).font(.body.weight(.medium))
                Text(row.materialID).font(.caption).foregroundStyle(.secondary).monospacedDigit()
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

    /// "Stable" on the hull, else its height above it in eV per atom.
    static func stability(_ energy: Double?) -> String {
        guard let energy else { return "No stability data" }
        if energy <= 0.0005 { return "Stable" }
        return String(format: "%.3f eV/atom above hull", energy)
    }
}

/// The chosen entry: name, id and licence, cell and symmetry, as the kit read them.
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
                LabeledContent("Name", value: p.name)
                LabeledContent("Formula", value: p.structure.formula)
                if let number = p.structure.spaceGroupNumber { LabeledContent("Space group", value: "No. \(number)") }
                if let system = p.structure.crystalSystem { LabeledContent("Crystal system", value: "\(system)".capitalized) }
            }
            Section("Cell") {
                LabeledContent("a, b, c", value: String(format: "%.4f, %.4f, %.4f Å", cell.a, cell.b, cell.c))
                LabeledContent("α, β, γ", value: String(format: "%.2f°, %.2f°, %.2f°", cell.alphaDeg, cell.betaDeg, cell.gammaDeg))
                LabeledContent("Atoms in cell", value: "\(p.structure.sites.count)")
                if p.converted {
                    Text("Served as a primitive cell; shown as the conventional cell.").font(.caption).foregroundStyle(.secondary)
                }
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
}
