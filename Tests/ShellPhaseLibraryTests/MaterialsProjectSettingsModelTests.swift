//
//  MaterialsProjectSettingsModelTests.swift
//  EMSuiteUI#190: a key pasted, tested and removed, on a stub transport and a key store in memory (no network, no keychain).
//

import Foundation
import XCTest
@testable import ShellPhaseLibrary

final class MaterialsProjectSettingsModelTests: XCTestCase {

    @MainActor private func make(_ stub: StubTransport, key: String? = nil) -> (MaterialsProjectSettingsModel, FixedKeyStore) {
        let store = FixedKeyStore(key)
        let client = MaterialsProjectClient(transport: stub, sleep: { _ in })
        return (MaterialsProjectSettingsModel(keyStore: store, client: client), store)
    }

    @MainActor func testAPastedKeyIsSavedTrimmedAndNeverShown() async {
        let (model, store) = make(StubTransport())
        await model.refresh()
        XCTAssertFalse(model.hasKey)
        XCTAssertFalse(model.canSave)
        model.draft = "  abc123\n"
        XCTAssertTrue(model.canSave)
        await model.save()
        XCTAssertEqual(store.key, "abc123")
        XCTAssertTrue(model.hasKey)
        XCTAssertEqual(model.draft, "", "the field empties: the key is not shown again")
    }

    @MainActor func testTheStoredKeyIsTestedWithOneKeyedRequest() async throws {
        let stub = StubTransport { _ in (Data(#"{"data":[],"errors":[]}"#.utf8), 200, [:]) }
        let (model, _) = make(stub, key: "abc123")
        await model.refresh()
        XCTAssertTrue(model.hasKey)
        await model.testKey()
        XCTAssertEqual(model.test, .accepted)
        XCTAssertEqual(stub.sent.count, 1)
        let sent = try XCTUnwrap(stub.sent.first)
        XCTAssertEqual(sent.url?.host, "api.materialsproject.org")
        XCTAssertEqual(sent.value(forHTTPHeaderField: MaterialsProjectClient.keyHeader), "abc123")
    }

    @MainActor func testARefusedKeyIsSaidAndAPastedKeyIsTestedBeforeTheStoredOne() async throws {
        let stub = StubTransport { _ in (Data(), 401, [:]) }
        let (model, _) = make(stub, key: "old")
        await model.refresh()
        model.draft = "new"
        await model.testKey()
        XCTAssertEqual(stub.sent.first?.value(forHTTPHeaderField: MaterialsProjectClient.keyHeader), "new")
        guard case .failed(let message) = model.test else { return XCTFail("\(model.test)") }
        XCTAssertTrue(message.contains("refused"), message)
    }

    @MainActor func testNoKeyToTestSendsNothing() async {
        let stub = StubTransport()
        let (model, _) = make(stub)
        await model.refresh()
        await model.testKey()
        XCTAssertEqual(stub.sent.count, 0)
        XCTAssertEqual(model.test, .failed("Paste a key first."))
    }

    @MainActor func testRemoveForgetsTheKey() async {
        let (model, store) = make(StubTransport(), key: "abc123")
        await model.refresh()
        await model.remove()
        XCTAssertNil(store.key)
        XCTAssertFalse(model.hasKey)
    }

    func testThePaneSaysWhatIsSentInOneSentenceAndCarriesTheCitation() {
        let sentence = MaterialsProjectSettingsModel.whatIsSent
        XCTAssertEqual(sentence.filter { $0 == "." }.count, 1, sentence)
        XCTAssertTrue(sentence.hasSuffix("."))
        XCTAssertTrue(MaterialsProjectSettingsModel.citation.contains("10.1063/1.4812323"))
        XCTAssertEqual(MaterialsProjectSettingsModel.citationURL.absoluteString, "https://doi.org/10.1063/1.4812323")
    }
}
