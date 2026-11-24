//
//  PhaseLibraryStoreTests.swift
//  EMSuiteUI#188: one folder per phase with its record and its raw source.
//

import Foundation
import XCTest
@testable import ShellPhaseLibrary

final class PhaseLibraryStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PhaseLibraryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    func testAPhaseIsOneFolderWithItsRecordAndItsSourceAsItCame() throws {
        let store = PhaseLibraryStore(folder: folder)
        XCTAssertEqual(store.entries(), [], "no folder yet: an empty library")
        let cif = Data("data_Si\n_cell_length_a 5.431\n".utf8)
        try store.save(id: "mp-149", record: Data("{\"v\":1}".utf8), source: cif, sourceExtension: "cif")
        let entry = try XCTUnwrap(store.entries().first)
        XCTAssertEqual(entry.id, "mp-149")
        XCTAssertEqual(entry.record, Data("{\"v\":1}".utf8))
        XCTAssertEqual(entry.source?.lastPathComponent, "source.cif")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(entry.source)), cif)
    }

    func testAnEditRewritesTheRecordAndNeverTheSource() throws {
        let store = PhaseLibraryStore(folder: folder)
        try store.save(id: "a", record: Data("1".utf8), source: Data("original".utf8))
        try store.save(id: "a", record: Data("2".utf8), source: Data("other".utf8))
        let entry = try XCTUnwrap(store.entries().first)
        XCTAssertEqual(entry.record, Data("2".utf8))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(entry.source)), Data("original".utf8))
        try store.remove(id: "a")
        XCTAssertEqual(store.entries(), [])
    }

    func testAFolderWithoutARecordIsSkippedAndIdsAreSafeNames() throws {
        let store = PhaseLibraryStore(folder: folder)
        try FileManager.default.createDirectory(at: folder.appending(path: "half"), withIntermediateDirectories: true)
        XCTAssertEqual(store.entries(), [])
        XCTAssertEqual(PhaseLibraryStore.folderName(for: "mp-149"), "mp-149")
        XCTAssertEqual(PhaseLibraryStore.folderName(for: "../etc/x"), "_.._etc_x")
        XCTAssertEqual(PhaseLibraryStore.folderName(for: "Mg₂Si"), "Mg_Si")
    }
}
