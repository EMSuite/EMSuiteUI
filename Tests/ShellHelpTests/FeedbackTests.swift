//
//  FeedbackTests.swift
//  EMSuiteUI Q12: the diagnostics summary, the drafts made from it, and the Help menu's items.
//

import Foundation
import XCTest
@testable import ShellHelp

nonisolated final class FeedbackTests: XCTestCase {
    private let summary = DiagnosticsSummary(appName: "Electron Microscopy Studio", appVersion: "2.3.0 (52)", channel: .appStore,
                                             macOSVersion: "26.1.0", macModel: "Mac16,7", memoryBytes: 36 << 30)
    private let destination = FeedbackDestination(address: "mail@example.com", repository: "EMSuite/Electron-Microscopy-Studio")

    private func query(_ url: URL?) throws -> [String: String] {
        let items = try XCTUnwrap(URLComponents(url: XCTUnwrap(url), resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testTheSummaryNamesVersionChannelMacOSModelAndMemory() {
        XCTAssertEqual(summary.lines, [
            "Electron Microscopy Studio 2.3.0 (52) (App Store)",
            "macOS 26.1.0",
            "Mac Mac16,7, 36 GB memory",
        ])
    }

    /// On this Mac (the CI runner): the model and the memory are read, not left unknown.
    func testTheCurrentSummaryReadsThisMac() {
        let here = DiagnosticsSummary.current(appName: "Test", channel: .development)
        XCTAssertNotEqual(here.macModel, "unknown")
        XCTAssertGreaterThan(here.memoryBytes, 0)
        XCTAssertNil(DiagnosticsSummary.sysctlString("no.such.name"))
    }

    func testTheEmailDraftCarriesTheWordsThenTheSummary() throws {
        let url = FeedbackComposer.mail(message: "  The ring fit stops at 2 rings.\nSteps: open, fit.  ", summary: summary, to: destination)
        XCTAssertEqual(url?.scheme, "mailto")
        XCTAssertTrue(url?.absoluteString.hasPrefix("mailto:mail@example.com?") == true)
        let q = try query(url)
        XCTAssertEqual(q["subject"], "The ring fit stops at 2 rings.")
        XCTAssertEqual(q["body"], "The ring fit stops at 2 rings.\nSteps: open, fit.\n\n---\n" + summary.text)
    }

    func testTheIssueDraftOpensTheRepositorysNewIssuePage() throws {
        let url = FeedbackComposer.githubIssue(message: "", summary: summary, to: destination)
        XCTAssertEqual(url?.host, "github.com")
        XCTAssertEqual(url?.path, "/EMSuite/Electron-Microscopy-Studio/issues/new")
        let q = try query(url)
        XCTAssertEqual(q["title"], "Electron Microscopy Studio feedback", "no words: the app's name")
        XCTAssertEqual(q["body"], "---\n" + summary.text)
        XCTAssertNil(FeedbackComposer.githubIssue(message: "", summary: summary, to: FeedbackDestination(address: "a@b", repository: "nope")))
    }

    /// A plus in the words reaches GitHub's form reader as a plus (EMSuiteUI#233). Red before: "+" went out bare, a space there.
    func testAPlusInTheWordsIsWrittenSoAFormReaderKeepsIt() throws {
        for url in [FeedbackComposer.githubIssue(message: "Si+Ge map is empty", summary: summary, to: destination),
                    FeedbackComposer.mail(message: "Si+Ge map is empty", summary: summary, to: destination)] {
            let text = try XCTUnwrap(url?.absoluteString)
            XCTAssertTrue(text.contains("Si%2BGe"), text)
            XCTAssertFalse(try XCTUnwrap(URLComponents(string: text)?.percentEncodedQuery).contains("+"), text)
        }
        let q = try query(FeedbackComposer.githubIssue(message: "Si+Ge map is empty", summary: summary, to: destination))
        XCTAssertEqual(q["title"], "Si+Ge map is empty")
    }

    func testALongFirstLineIsShortenedForTheSubject() {
        let subject = FeedbackComposer.subject(message: String(repeating: "x", count: 200), summary: summary)
        XCTAssertEqual(subject.count, 80)
        XCTAssertTrue(subject.hasSuffix("…"))
    }

    func testTheHelpMenuReplacesTheMissingHelpBook() throws {
        let links = HelpLinks(appName: "Electron Microscopy Studio", support: try XCTUnwrap(URL(string: "https://example.com/support")),
                              destination: destination, channel: .website)
        XCTAssertEqual(links.menuTitles, ["Electron Microscopy Studio Support", "Report a Problem…"])
        var documented = links
        documented.documentation = URL(string: "https://example.com/docs")
        XCTAssertEqual(documented.menuTitles, ["Electron Microscopy Studio Support", "Electron Microscopy Studio Documentation", "Report a Problem…"])
        XCTAssertTrue(FeedbackView.privacyNote.hasPrefix("Nothing is sent"))
    }
}
