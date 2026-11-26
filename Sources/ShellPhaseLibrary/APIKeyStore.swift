//
//  APIKeyStore.swift
//  Moved up from 4DSTEM Studio's MaterialsProjectKeyStore.swift (EMSuiteUI#188), unchanged in behaviour so both apps keep one
//  key in one place: the same service and account, the login keychain. The key never reaches a file or a log: errors carry
//  only the keychain's status.
//  Where the Materials Project API key lives between launches. Keychain,
//  not `UserDefaults`. A protocol in front of it so the tests can swap in an
//  in-memory store (in the test target) without touching the Keychain.
//
//  Deliberately no `kSecUseDataProtectionKeychain`: this app is not signed
//  into the data-protection keychain elsewhere, and adding it here would make
//  this one item behave differently from nothing else in the app.
//
//  Every member is `nonisolated`: Keychain calls are synchronous, blocking,
//  thread-agnostic C API — the same shape as the file I/O `Core/` already
//  does off the main actor, and there is no UI or `AppState` dependency here
//  to require otherwise.
//

import Foundation
import Security

/// Where the Materials Project API key is loaded from and saved to. `nil`
/// from `load()` means "no key set" — never a thrown error; a key that
/// exists but cannot be read (a real Keychain failure) throws instead, so
/// the two cases stay distinguishable to the caller.
public nonisolated protocol APIKeyStore: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

/// Stores the key as a Keychain generic-password item. `service`/`account`
/// are injectable so tests can round-trip against a throwaway item rather
/// than the app's own real one.
public nonisolated final class KeychainAPIKeyStore: APIKeyStore, @unchecked Sendable {

    /// Every Keychain failure carries the raw `OSStatus` it came from —
    /// named per the rule "no claim a reader cannot reproduce": a
    /// caller (or a test) can look the number up itself rather than trust a
    /// paraphrase of it.
    public enum KeychainFailure: Error, Equatable {
        case unhandled(OSStatus)
    }

    public static let defaultService = "com.mac4dstem.materials-project"
    public static let defaultAccount = "api-key"

    private let service: String
    private let account: String

    public init(service: String = KeychainAPIKeyStore.defaultService,
                 account: String = KeychainAPIKeyStore.defaultAccount) {
        self.service = service
        self.account = account
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() throws -> String? {
        var lookup = query()
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure.unhandled(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        let existing = query()
        let probe = SecItemCopyMatching(existing as CFDictionary, nil)

        switch probe {
        case errSecSuccess:
            let status = SecItemUpdate(existing as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecSuccess else { throw KeychainFailure.unhandled(status) }
        case errSecItemNotFound:
            var attributes = existing
            attributes[kSecValueData as String] = data
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainFailure.unhandled(status) }
        default:
            throw KeychainFailure.unhandled(probe)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure.unhandled(status)
        }
    }
}

extension APIKeyStore {
    // A keychain call can block, or show a prompt, so the models make it off the main actor (EMSuiteUI#233).

    @concurrent public func loadInBackground() async throws -> String? { try load() }
    @concurrent public func saveInBackground(_ key: String) async throws { try save(key) }
    @concurrent public func deleteInBackground() async throws { try delete() }
}
