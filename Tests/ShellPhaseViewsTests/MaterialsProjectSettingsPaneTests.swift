//
//  MaterialsProjectSettingsPaneTests.swift
//  EMSuiteUI#190: the Materials Project settings pane in light and dark, without a key and with a tested key. The pictures
//  compare only on CI's macos-26 leg (SNAPSHOTS=1); new ones are attached to the PR and committed under
//  __Snapshots__/MaterialsProjectSettingsPaneTests/ once reviewed.
//

import Foundation
import ShellPhaseLibrary
import ShellSnapshotTesting
import SwiftUI
import XCTest
@testable import ShellPhaseViews

private nonisolated final class MemoryKeyStore: APIKeyStore, @unchecked Sendable {
    var key: String?
    init(_ key: String?) { self.key = key }
    func load() throws -> String? { key }
    func save(_ key: String) throws { self.key = key }
    func delete() throws { key = nil }
}

private nonisolated final class AcceptingTransport: PhaseTransport, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

nonisolated final class MaterialsProjectSettingsPaneTests: XCTestCase {

    @MainActor private func check(_ name: String, _ model: MaterialsProjectSettingsModel,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(Snapshot.isEnabled, "snapshots are compared only where SNAPSHOTS=1 is set (CI's macos-26 leg)")
        let view = MaterialsProjectSettingsPane(model: model)
        for appearance in SnapshotAppearance.allCases {
            let result = Snapshot.verify(view, named: name, size: CGSize(width: 560, height: 520), appearance: appearance,
                                         testFile: file)
            if let failure = result.failure { XCTFail(failure, file: file, line: line) }
        }
    }

    @MainActor private func model(key: String?) -> MaterialsProjectSettingsModel {
        MaterialsProjectSettingsModel(keyStore: MemoryKeyStore(key),
                                      client: MaterialsProjectClient(transport: AcceptingTransport(), sleep: { _ in }))
    }

    @MainActor func testSnapshotWithoutAKey() throws {
        try check("materials-project-no-key", model(key: nil))
    }

    @MainActor func testSnapshotWithATestedKey() async throws {
        let m = model(key: "abc123")
        await m.testKey()
        XCTAssertEqual(m.test, .accepted)
        try check("materials-project-key-accepted", m)
    }
}
