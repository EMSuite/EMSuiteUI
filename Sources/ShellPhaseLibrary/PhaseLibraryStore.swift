//
//  PhaseLibraryStore.swift
//  Role: the phase library on disk (EMSuiteUI#188, plan section 5.2): one folder per phase in Application Support, holding the
//        record and the raw source exactly as it came (the fetched JSON or the CIF's bytes), so a phase added once works offline
//        for good and can always be reset to its source. Plain files, written atomically; what a record says is `Phase`'s.
//

import Foundation

public struct PhaseLibraryStore: Sendable {
    public static let recordName = "phase.json"
    public static let sourceStem = "source"

    /// One phase's folder as read back: its id, the record's bytes and the source's file.
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let record: Data
        public let source: URL?
    }

    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    /// Application Support/<bundle id>/Phases (inside the container in the store build).
    public static func standard(bundle: Bundle = .main) -> PhaseLibraryStore? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return PhaseLibraryStore(folder: support.appending(path: bundle.bundleIdentifier ?? "EMSuite", directoryHint: .isDirectory)
            .appending(path: "Phases", directoryHint: .isDirectory))
    }

    /// A phase id as a folder name: letters, digits, "-", "_" and "." kept, anything else "_" (an id is "mp-149" or a UUID).
    public static func folderName(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let name = String(id.unicodeScalars.map { allowed.contains($0) && $0.isASCII ? Character($0) : "_" })
        return name.isEmpty || name.hasPrefix(".") ? "_" + name : name
    }

    /// Writes a phase: its record, and its source on the first write (the source never changes after; Reset to Source reads it).
    public func save(id: String, record: Data, source: Data? = nil, sourceExtension: String = "json") throws {
        let dir = folder.appending(path: Self.folderName(for: id), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let source, sourceURL(in: dir) == nil {
            try source.write(to: dir.appending(path: "\(Self.sourceStem).\(sourceExtension)"), options: .atomic)
        }
        try record.write(to: dir.appending(path: Self.recordName), options: .atomic)
    }

    /// Every phase that has a record, in folder-name order. A folder without one (a write cut short) is skipped, not an error.
    public func entries() -> [Entry] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return dirs.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { dir in
            guard let record = try? Data(contentsOf: dir.appending(path: Self.recordName)) else { return nil }
            return Entry(id: dir.lastPathComponent, record: record, source: sourceURL(in: dir))
        }
    }

    public func remove(id: String) throws {
        let dir = folder.appending(path: Self.folderName(for: id), directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }

    private func sourceURL(in dir: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.first { $0.hasPrefix(Self.sourceStem + ".") }.map { dir.appending(path: $0) }
    }
}
