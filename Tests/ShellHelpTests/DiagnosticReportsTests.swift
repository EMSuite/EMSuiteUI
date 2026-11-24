//
//  DiagnosticReportsTests.swift
//  EMSuiteUI Q14: crash and hang reports are kept in the app's own folder, newest first to survive, and nothing else is touched.
//

import Foundation
import XCTest
@testable import ShellHelp

nonisolated final class DiagnosticReportsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DiagnosticReportsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAReportIsWrittenAsTheSystemGaveIt() throws {
        let store = DiagnosticReportStore(folder: folder)
        XCTAssertEqual(store.reports(), [], "no folder yet: no reports, and no error")
        let json = Data(#"{"crashDiagnostics":[]}"#.utf8)
        let written = try store.save([json], receivedAt: Date(timeIntervalSince1970: 1_795_445_702))
        XCTAssertEqual(written.map(\.lastPathComponent), ["diagnostic-20261123-145502-1.json"])
        XCTAssertEqual(try Data(contentsOf: written[0]), json)
        XCTAssertEqual(store.reports().map(\.lastPathComponent), written.map(\.lastPathComponent))
        XCTAssertEqual(try store.reports().map { try Data(contentsOf: $0) }, [json])
    }

    func testOnlyTheNewestAreKeptAndOtherFilesAreLeftAlone() throws {
        let store = DiagnosticReportStore(folder: folder, capacity: 3)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let other = folder.appending(path: "notes.txt")
        try Data("mine".utf8).write(to: other)
        for day in 0..<5 {
            try store.save([Data("\(day)".utf8)], receivedAt: Date(timeIntervalSince1970: 1_795_445_702 + Double(day) * 86_400))
        }
        let kept = store.reports()
        XCTAssertEqual(kept.count, 3)
        XCTAssertEqual(try kept.map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }, ["2", "3", "4"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "a file that is not a report is never removed")
    }

    /// Two deliveries in one second keep all their reports (EMSuiteUI#233). Red before: the second replaced the first's file.
    func testTwoDeliveriesInOneSecondKeepEveryReport() throws {
        let store = DiagnosticReportStore(folder: folder)
        let date = Date(timeIntervalSince1970: 1_795_445_702)
        try store.save([Data("a".utf8)], receivedAt: date)
        let second = try store.save([Data("b".utf8), Data("c".utf8)], receivedAt: date)
        XCTAssertEqual(second.map(\.lastPathComponent), ["diagnostic-20261123-145502-2.json", "diagnostic-20261123-145502-3.json"])
        XCTAssertEqual(try store.reports().map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }, ["a", "b", "c"])
    }

    func testNothingIsWrittenForAnEmptyDelivery() throws {
        let store = DiagnosticReportStore(folder: folder)
        XCTAssertEqual(try store.save([]), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testTheReportWindowSaysHowManyAreKept() {
        XCTAssertNil(FeedbackView.reportsLine(count: 0))
        XCTAssertEqual(FeedbackView.reportsLine(count: 1)?.hasPrefix("1 crash or hang report is"), true)
        XCTAssertEqual(FeedbackView.reportsLine(count: 3)?.hasPrefix("3 crash or hang reports are"), true)
    }
}
