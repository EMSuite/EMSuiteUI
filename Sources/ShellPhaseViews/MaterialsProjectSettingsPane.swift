//
//  MaterialsProjectSettingsPane.swift
//  Role: the Materials Project pane both apps put in Settings (EMSuiteUI#190): an optional key, pasted, tested and removed;
//        one sentence on what is sent; the citation the Materials Project asks for. Everything it says comes from
//        `MaterialsProjectSettingsModel`.
//

import ShellPhaseLibrary
import SwiftUI

public struct MaterialsProjectSettingsPane: View {
    let model: MaterialsProjectSettingsModel

    public init(model: MaterialsProjectSettingsModel) { self.model = model }

    public var body: some View {
        Form { MaterialsProjectSettingsSections(model: model) }
            .formStyle(.grouped)
    }
}

/// The pane's sections without their Form, for a Settings window whose detail is already one grouped Form.
public struct MaterialsProjectSettingsSections: View {
    @Bindable var model: MaterialsProjectSettingsModel

    public init(model: MaterialsProjectSettingsModel) { self.model = model }

    public var body: some View {
        Group {
            Section {
                LabeledContent("API key") {
                    Text(model.hasKey ? "Saved in your keychain" : "None. Search uses the open service.")
                        .foregroundStyle(model.hasKey ? .primary : .secondary)
                        .accessibilityIdentifier("materialsProject.keyState")
                }
                SecureField(model.hasKey ? "Paste a new key to replace it" : "Paste your key", text: $model.draft)
                    .accessibilityLabel("Materials Project API key")
                    .accessibilityIdentifier("materialsProject.keyField")
                    .onSubmit { Task { await model.save() } }
                HStack {
                    Button("Save") { Task { await model.save() } }
                        .disabled(!model.canSave)
                        .accessibilityLabel("Save the key in your keychain")
                        .accessibilityIdentifier("materialsProject.save")
                    Button("Test") { Task { await model.testKey() } }
                        .disabled(!(model.hasKey || model.canSave) || model.test == .testing)
                        .accessibilityLabel("Test the key with the Materials Project")
                        .accessibilityIdentifier("materialsProject.test")
                    Button("Remove", role: .destructive) { Task { await model.remove() } }
                        .disabled(!model.hasKey)
                        .accessibilityLabel("Remove the key from your keychain")
                        .accessibilityIdentifier("materialsProject.remove")
                    Spacer()
                    testResult
                }
                if let problem = model.keychainProblem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("materialsProject.keychainProblem")
                }
                Link("Get a key from the Materials Project", destination: MaterialsProjectSettingsModel.keyPageURL)
                    .accessibilityIdentifier("materialsProject.getKey")
            } header: {
                Text("Materials Project")
            } footer: {
                Text("A key is optional: searching and adding phases work without one.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("What is sent") {
                Text(MaterialsProjectSettingsModel.whatIsSent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("materialsProject.whatIsSent")
            }
            Section("Cite") {
                Text("Structures from the Materials Project are CC BY 4.0. Please cite:")
                    .font(.callout).foregroundStyle(.secondary)
                Text(MaterialsProjectSettingsModel.citation)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("materialsProject.citation")
                Link("doi:10.1063/1.4812323", destination: MaterialsProjectSettingsModel.citationURL)
                    .accessibilityIdentifier("materialsProject.doi")
            }
        }
        // Whether a key is stored, read off the main actor (EMSuiteUI#233).
        .task { await model.refresh() }
    }

    @ViewBuilder private var testResult: some View {
        switch model.test {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small).accessibilityLabel("Testing the key")
        case .accepted:
            Label("Key accepted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("materialsProject.testResult")
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
                .accessibilityIdentifier("materialsProject.testResult")
        }
    }
}
