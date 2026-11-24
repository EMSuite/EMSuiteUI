//
//  HelpMenu.swift
//  Role: the Help menu both apps share (EMSuiteUI Q12). Neither app ships a help book, so the system's "<App> Help" item would only
//        say help is unavailable; in its place the support page, the documentation and Report a Problem…, which opens a window
//        holding the report and the diagnostics summary. The person sends it from their own mail app or browser.
//
//  Hooked up by three lines in the app: `HelpCommands(links)` in `.commands`, `FeedbackWindow(links)` among its scenes, and
//  `DiagnosticReportCollector.start()` once at launch, kept for the app's life.
//

import SwiftUI

/// What the app's Help menu links to, and what a report names.
public nonisolated struct HelpLinks: Equatable, Sendable {
    public var appName: String
    public var support: URL
    public var documentation: URL?
    public var destination: FeedbackDestination
    public var channel: DistributionChannel

    public init(appName: String, support: URL, documentation: URL? = nil, destination: FeedbackDestination, channel: DistributionChannel) {
        self.appName = appName; self.support = support; self.documentation = documentation
        self.destination = destination; self.channel = channel
    }

    /// The menu's items, in order: the titles the menu shows (pure, so a test holds them).
    public var menuTitles: [String] {
        ["\(appName) Support"] + (documentation == nil ? [] : ["\(appName) Documentation"]) + [FeedbackWindow.title + "…"]
    }
}

public struct HelpCommands: Commands {
    private let links: HelpLinks
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    public init(_ links: HelpLinks) { self.links = links }

    public var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("\(links.appName) Support") { openURL(links.support) }
            if let documentation = links.documentation {
                Button("\(links.appName) Documentation") { openURL(documentation) }
            }
            Divider()
            Button(FeedbackWindow.title + "…") { openWindow(id: FeedbackWindow.id) }
        }
    }
}

/// The Report a Problem window: one window, never restored at launch.
public struct FeedbackWindow: Scene {
    public nonisolated static let id = "emsuite.feedback"
    public nonisolated static let title = "Report a Problem"
    private let links: HelpLinks

    public init(_ links: HelpLinks) { self.links = links }

    public var body: some Scene {
        Window(Self.title, id: Self.id) {
            FeedbackView(links: links)
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
    }
}

/// The report: the person's words, the summary that will follow them, and two ways out, both through the person's own apps.
struct FeedbackView: View {
    nonisolated static let privacyNote = "Nothing is sent from this window. Your mail app or your browser opens with this report, and you send it from there."

    let links: HelpLinks
    @State private var message = ""
    @State private var summary: DiagnosticsSummary
    /// The crash and hang reports kept on this Mac (`DiagnosticReportCollector`), read when the window opens.
    @State private var reports: [URL]
    private let reportFolder: URL?
    @Environment(\.openURL) private var openURL

    init(links: HelpLinks) {
        self.links = links
        _summary = State(initialValue: .current(appName: links.appName, channel: links.channel))
        let store = DiagnosticReportStore.standard()
        reportFolder = store?.folder
        _reports = State(initialValue: store?.reports() ?? [])
    }

    /// "2 crash or hang reports are kept on this Mac." nil with none.
    nonisolated static func reportsLine(count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 crash or hang report is kept on this Mac. Attach it to your email if you like."
        default: "\(count) crash or hang reports are kept on this Mac. Attach any of them to your email if you like."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happened, and what did you expect?")
                .font(.headline)
            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .accessibilityLabel("Your report")
                .accessibilityIdentifier("feedback.message")
            Text("Added below your words:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(summary.text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Diagnostics summary")
                .accessibilityValue(summary.lines.joined(separator: ", "))
                .accessibilityIdentifier("feedback.summary")
            if let line = Self.reportsLine(count: reports.count), let folder = reportFolder {
                HStack(alignment: .firstTextBaseline) {
                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Show in Finder") { openURL(folder) }
                        .help("Opens the folder that holds the reports")
                        .accessibilityIdentifier("feedback.reports")
                }
            }
            Text(Self.privacyNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Open on GitHub…") {
                    if let url = FeedbackComposer.githubIssue(message: message, summary: summary, to: links.destination) { openURL(url) }
                }
                .help("Opens a new issue on GitHub with this report filled in; it is filed only when you submit it there")
                .accessibilityIdentifier("feedback.github")
                Button("Write Email…") {
                    if let url = FeedbackComposer.mail(message: message, summary: summary, to: links.destination) { openURL(url) }
                }
                .keyboardShortcut(.defaultAction)
                .help("Opens an email to \(links.destination.address) in your mail app with this report filled in")
                .accessibilityIdentifier("feedback.mail")
            }
        }
        .padding(20)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 360)
    }
}
