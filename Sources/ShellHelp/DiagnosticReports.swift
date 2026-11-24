//
//  DiagnosticReports.swift
//  Role: keeps the system's crash and hang reports for this app on this Mac (EMSuiteUI Q14). macOS hands them to the app through
//        MetricKit, usually at the next launch after the crash; each is written as the system's JSON into the app's own folder in
//        Application Support, the newest `capacity` kept. Nothing is sent: Report a Problem… names how many there are and shows
//        the folder, and the person attaches what they choose.
//

import Foundation
import MetricKit

/// The folder of kept reports: listing, writing and pruning, on plain files (a test gives it a temporary folder).
public nonisolated struct DiagnosticReportStore: Sendable {
    public let folder: URL
    public let capacity: Int

    public init(folder: URL, capacity: Int = 20) {
        self.folder = folder; self.capacity = max(capacity, 1)
    }

    /// The app's own folder: Application Support/<bundle id>/Diagnostic Reports (inside the container in the store build).
    public static func standard(bundle: Bundle = .main) -> DiagnosticReportStore? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let id = bundle.bundleIdentifier ?? "EMSuite"
        return DiagnosticReportStore(folder: support.appending(path: id, directoryHint: .isDirectory)
            .appending(path: "Diagnostic Reports", directoryHint: .isDirectory))
    }

    /// The file name for a report received at `date`: sortable, and safe in every file system ("diagnostic-20261123-145502-1.json").
    public static func fileName(for date: Date, index: Int) -> String {
        let stamp = date.formatted(Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: Calendar(identifier: .gregorian)))
        return "diagnostic-\(stamp)-\(index).json"
    }

    /// The kept reports, oldest first.
    public func reports() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return names.filter { $0.lastPathComponent.hasPrefix("diagnostic-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Writes each report, then drops the oldest past `capacity`. Returns the files written.
    @discardableResult
    public func save(_ reports: [Data], receivedAt date: Date = Date()) throws -> [URL] {
        guard !reports.isEmpty else { return [] }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        // The next free index of this second: a second delivery in the same second never replaces the first's files.
        var index = 1
        for data in reports {
            var url = folder.appending(path: Self.fileName(for: date, index: index), directoryHint: .notDirectory)
            while FileManager.default.fileExists(atPath: url.path) {
                index += 1
                url = folder.appending(path: Self.fileName(for: date, index: index), directoryHint: .notDirectory)
            }
            try data.write(to: url, options: [.atomic])
            written.append(url)
            index += 1
        }
        let all = self.reports()
        for old in all.prefix(max(all.count - capacity, 0)) { try? FileManager.default.removeItem(at: old) }
        return written
    }
}

/// Subscribes to MetricKit's diagnostics for the app's life and hands each delivery to the store. Start it once, at launch.
public nonisolated final class DiagnosticReportCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let store: DiagnosticReportStore

    public init(store: DiagnosticReportStore) {
        self.store = store
        super.init()
    }

    /// The collector for the app's own folder, subscribed; nil when the folder cannot be named.
    @MainActor public static func start(bundle: Bundle = .main) -> DiagnosticReportCollector? {
        guard let store = DiagnosticReportStore.standard(bundle: bundle) else { return nil }
        let collector = DiagnosticReportCollector(store: store)
        MXMetricManager.shared.add(collector)
        return collector
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // A delivery that cannot be written is dropped: keeping reports must never itself disturb the app.
        try? store.save(payloads.map { $0.jsonRepresentation() })
    }
}
