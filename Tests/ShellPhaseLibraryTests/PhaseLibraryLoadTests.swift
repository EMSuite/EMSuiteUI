//
//  PhaseLibraryLoadTests.swift
//  EMSuiteUI#231: a load that lands after a phase was added keeps that phase, and one removed meanwhile does not come back;
//  the source of one phase is found in its own folder. Red before: load() assigned what it read over the list in memory.
//

import DiffractoCore
import Foundation
import XCTest
@testable import ShellPhaseLibrary

final class PhaseLibraryLoadTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PhaseLibraryLoadTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func phase(_ id: String, at seconds: TimeInterval) throws -> Phase {
        let entry = try AddPhaseModelTests.entry()
        let structure = try MaterialsProjectOptimade.structure(from: MaterialsProjectOptimade.decodeEntry(entry)).structure
        return Phase(id: id, name: id, source: .materialsProject(id: id, fetched: Date(timeIntervalSince1970: seconds)),
                     added: Date(timeIntervalSince1970: seconds), structure: structure)
    }

    /// A phase in memory whose record the read did not see (added after the read) stays in the list.
    @MainActor func testAPhaseAddedWhileLoadingIsKept() async throws {
        let store = PhaseLibraryStore(folder: folder)
        let library = PhaseLibrary(store: store)
        try library.add(phase("mp-1", at: 1), source: Data("{}".utf8), sourceExtension: "json")
        try library.add(phase("mp-2", at: 2), source: Data("{}".utf8), sourceExtension: "json")
        // As if mp-2 was written after the read had listed the folder.
        try FileManager.default.removeItem(at: folder.appending(path: PhaseLibraryStore.folderName(for: "mp-2")))
        await library.load()
        XCTAssertEqual(library.phases.map(\.id), ["mp-2", "mp-1"], "newest first, the one added meanwhile kept")
    }

    func testARemovedPhaseDoesNotComeBackAndMemoryWins() throws {
        let one = try phase("mp-1", at: 1), two = try phase("mp-2", at: 2)
        var renamed = two
        renamed.name = "renamed"
        let merged = PhaseLibrary.merged(read: [one, two], inMemory: [renamed], removed: ["mp-1"])
        XCTAssertEqual(merged.map(\.id), ["mp-2"])
        XCTAssertEqual(merged.first?.name, "renamed")
    }

    @MainActor func testTheSourceIsFoundInItsOwnFolder() throws {
        let store = PhaseLibraryStore(folder: folder)
        let library = PhaseLibrary(store: store)
        try library.add(phase("mp-1", at: 1), source: Data("{}".utf8), sourceExtension: "json")
        XCTAssertEqual(library.sourceFile(of: "mp-1")?.deletingLastPathComponent().lastPathComponent, "mp-1")
        XCTAssertNil(library.sourceFile(of: "mp-9"))
    }
}
