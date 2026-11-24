//
//  MaterialsProjectSettingsModel.swift
//  Role: the Materials Project pane in Settings (EMSuiteUI#190, plan section 5.2): paste a key, test it, remove it. The key
//        is optional (search and download work without one, on the open service); it lives in the login keychain through
//        `APIKeyStore`, never in a file or a log. Test sends one keyed request for one entry and reads only the answer's
//        status.
//

import DiffractoCore
import Foundation
import Observation

@MainActor
@Observable
public final class MaterialsProjectSettingsModel {

    public enum TestState: Equatable, Sendable {
        case idle
        case testing
        case accepted
        case failed(String)
    }

    /// The one sentence the pane says about what leaves the Mac.
    public nonisolated static let whatIsSent = "Searches send only the elements or formula you type, and downloads only the "
        + "entry's id, to the Materials Project; with a key, the key goes with them."
    /// The reference the Materials Project asks its users to cite.
    public nonisolated static let citation = "A. Jain, S. P. Ong, G. Hautier, W. Chen, W. D. Richards, S. Dacek, S. Cholia, "
        + "D. Gunter, D. Skinner, G. Ceder and K. A. Persson, \"Commentary: The Materials Project: A materials genome approach "
        + "to accelerating materials innovation\", APL Materials 1, 011002 (2013). doi:10.1063/1.4812323"
    public nonisolated static let citationURL = URL(string: "https://doi.org/10.1063/1.4812323")!
    /// Where a person gets their own key (signed in to the Materials Project).
    public nonisolated static let keyPageURL = URL(string: "https://next-gen.materialsproject.org/api")!
    /// The entry Test asks for: silicon, which every release of the database holds.
    public nonisolated static let testMaterialID = "mp-149"

    /// What the field holds before Save.
    public var draft = ""
    public private(set) var hasKey = false
    public private(set) var test: TestState = .idle
    /// A sentence when the keychain refused a read, a save or a removal.
    public private(set) var keychainProblem: String?

    @ObservationIgnored private let keyStore: any APIKeyStore
    @ObservationIgnored private let client: MaterialsProjectClient

    public init(keyStore: any APIKeyStore, client: MaterialsProjectClient) {
        self.keyStore = keyStore
        self.client = client
        refresh()
    }

    /// Reads whether a key is stored (the key itself is never shown).
    public func refresh() {
        do {
            hasKey = !((try keyStore.load()) ?? "").isEmpty
            keychainProblem = nil
        } catch {
            keychainProblem = "The keychain could not be read: \(error)"
        }
    }

    public var canSave: Bool { !Self.cleaned(draft).isEmpty }

    /// Stores the pasted key (spaces and line breaks around it dropped) and forgets cached searches.
    public func save() async {
        let key = Self.cleaned(draft)
        guard !key.isEmpty else { return }
        do {
            try keyStore.save(key)
            draft = ""
            hasKey = true
            test = .idle
            keychainProblem = nil
            await client.clearCache()
        } catch {
            keychainProblem = "The key could not be saved in the keychain: \(error)"
        }
    }

    /// Removes the key; the open service is used from then on.
    public func remove() async {
        do {
            try keyStore.delete()
            hasKey = false
            test = .idle
            keychainProblem = nil
            await client.clearCache()
        } catch {
            keychainProblem = "The key could not be removed from the keychain: \(error)"
        }
    }

    /// Tests the pasted key if there is one, else the stored key, with one request for one entry.
    public func testKey() async {
        let pasted = Self.cleaned(draft)
        let key = pasted.isEmpty ? ((try? keyStore.load()) ?? nil) : pasted
        guard let key, !key.isEmpty else { test = .failed("Paste a key first."); return }
        test = .testing
        do {
            let request = try MaterialsProjectImport.request(materialID: Self.testMaterialID, apiKey: key)
            _ = try await client.download(request, key: key)
            test = .accepted
        } catch let failure as MaterialsProjectClient.Failure {
            switch failure {
            case .keyRefused:
                test = .failed("The Materials Project refused this key. Copy it again from your dashboard there.")
            default:
                test = .failed(AddPhaseModel.title(for: failure) + " " + AddPhaseModel.next(for: failure))
            }
        } catch {
            test = .failed("The key could not be tested: \(error.localizedDescription)")
        }
    }

    nonisolated static func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
