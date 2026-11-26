//
//  FeedbackComposer.swift
//  Role: turns the person's words and the diagnostics summary into an email draft (a `mailto:` link) and a GitHub issue draft (the
//        repository's new-issue page with title and body filled in). Both open in the person's own mail app or browser, where they
//        read it once more and send it themselves; the app sends nothing. Pure, so the drafts are tested.
//

import Foundation

/// Where a report goes: the project's address and the app's public repository ("EMSuite/Electron-Microscopy-Studio").
public nonisolated struct FeedbackDestination: Equatable, Sendable {
    public var address: String
    public var repository: String

    public init(address: String, repository: String) {
        self.address = address; self.repository = repository
    }
}

public nonisolated enum FeedbackComposer {
    /// The report's text: what the person wrote, then the summary under a rule. The summary comes last so the person's words lead.
    public static func body(message: String, summary: DiagnosticsSummary) -> String {
        let words = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return (words.isEmpty ? "" : words + "\n\n") + "---\n" + summary.text
    }

    /// The subject and the issue's title: the person's first line, or "<App> feedback" when they wrote none.
    public static func subject(message: String, summary: DiagnosticsSummary) -> String {
        let first = message.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !first.isEmpty else { return "\(summary.appName) feedback" }
        return first.count > 80 ? String(first.prefix(79)) + "…" : first
    }

    /// `URLComponents` leaves "+" in a query as it is, and a page that reads the query as form data (GitHub's new-issue page) takes
    /// "+" for a space: "Si+Ge" would arrive as "Si Ge". Written as %2B it is a plus for every reader.
    static func formSafe(_ link: URLComponents) -> URLComponents {
        var link = link
        link.percentEncodedQuery = link.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return link
    }

    /// The email draft.
    public static func mail(message: String, summary: DiagnosticsSummary, to destination: FeedbackDestination) -> URL? {
        var link = URLComponents()
        link.scheme = "mailto"
        link.path = destination.address
        link.queryItems = [
            URLQueryItem(name: "subject", value: subject(message: message, summary: summary)),
            URLQueryItem(name: "body", value: body(message: message, summary: summary)),
        ]
        return formSafe(link).url
    }

    /// The GitHub issue draft: the new-issue page of the app's repository with title and body filled in. Nothing is filed until the
    /// person presses Submit there.
    public static func githubIssue(message: String, summary: DiagnosticsSummary, to destination: FeedbackDestination) -> URL? {
        guard destination.repository.split(separator: "/").count == 2 else { return nil }
        var link = URLComponents()
        link.scheme = "https"
        link.host = "github.com"
        link.path = "/\(destination.repository)/issues/new"
        link.queryItems = [
            URLQueryItem(name: "title", value: subject(message: message, summary: summary)),
            URLQueryItem(name: "body", value: body(message: message, summary: summary)),
        ]
        return formSafe(link).url
    }
}
