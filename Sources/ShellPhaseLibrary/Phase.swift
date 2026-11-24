//
//  Phase.swift
//  Role: one phase of the library (EMSuiteUI#188, plan section 5.2): DiffractoCore's structure as a stored snapshot, with the
//        person's name and notes, where it came from, and the fingerprint of the structure as it came, so an edited lattice
//        shows as "edited" and Reset to Source can undo it. The numbers are the kit's; this record names and keeps them.
//

import DiffractoCore
import Foundation

/// Where a phase came from.
public enum PhaseSource: Sendable, Equatable, Codable {
    /// A Materials Project entry ("mp-149"), fetched on that date. Its data is CC BY 4.0.
    case materialsProject(id: String, fetched: Date)
    /// A CIF the person opened, by its file name.
    case cif(fileName: String)

    /// "Materials Project · mp-149 · CC BY 4.0": the line every Materials Project phase shows; nil for a CIF.
    public var attribution: String? {
        if case .materialsProject(let id, _) = self { return "Materials Project · \(id) · CC BY 4.0" }
        return nil
    }

    /// The entry's page on the Materials Project; nil for a CIF.
    public var pageURL: URL? {
        guard case .materialsProject(let id, _) = self, id.hasPrefix("mp-") || id.hasPrefix("mvc-") else { return nil }
        return URL(string: "https://next-gen.materialsproject.org/materials/\(id)")
    }
}

public struct Phase: Identifiable, Sendable, Equatable, Codable {
    /// The schema this version writes; a record of a newer schema is refused on reading with a sentence.
    public static let currentSchemaVersion = 1

    public private(set) var schemaVersion: Int
    /// The library's id: the Materials Project id, or a UUID for a CIF. Never changes.
    public let id: String
    public var name: String
    public var notes: String
    public let source: PhaseSource
    public let added: Date
    /// The structure now, edited or not.
    public private(set) var snapshot: CrystalStructure.Snapshot
    /// The fingerprint of the structure as it came from its source.
    public let sourceFingerprint: String

    public init(id: String, name: String, notes: String = "", source: PhaseSource, added: Date = Date(), structure: CrystalStructure) {
        let snapshot = CrystalStructure.Snapshot(structure)
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id; self.name = name; self.notes = notes; self.source = source; self.added = added
        self.snapshot = snapshot
        self.sourceFingerprint = snapshot.fingerprint
    }

    /// The structure the kit computes with, rebuilt from the snapshot.
    public func structure() -> CrystalStructure { snapshot.structure() }

    /// Whether the structure differs from the one its source gave (a lattice edit).
    public var isEdited: Bool { snapshot.fingerprint != sourceFingerprint }

    /// Replaces the structure (a lattice edit, made by the kit). The source and its fingerprint stay.
    public mutating func replaceStructure(_ structure: CrystalStructure) {
        snapshot = CrystalStructure.Snapshot(structure)
    }

    /// Back to the structure the source gave, as read again from the stored source by the kit.
    public mutating func resetStructure(to sourceStructure: CrystalStructure) {
        snapshot = CrystalStructure.Snapshot(sourceStructure)
    }

    public enum ReadError: Error, Equatable, CustomStringConvertible {
        case newerSchema(Int)
        public var description: String {
            switch self {
            case .newerSchema(let v): "This phase was saved by a newer version of the app (record version \(v)). Update the app to open it."
            }
        }
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, id, name, notes, source, added, snapshot, sourceFingerprint }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version <= Self.currentSchemaVersion else { throw ReadError.newerSchema(version) }
        schemaVersion = version
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        source = try c.decode(PhaseSource.self, forKey: .source)
        added = try c.decode(Date.self, forKey: .added)
        snapshot = try c.decode(CrystalStructure.Snapshot.self, forKey: .snapshot)
        sourceFingerprint = try c.decode(String.self, forKey: .sourceFingerprint)
    }

    /// The record's bytes as the library stores them: stable keys, ISO dates.
    public static func encoded(_ phase: Phase) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(phase)
    }

    public static func decoded(_ data: Data) throws -> Phase {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Phase.self, from: data)
    }
}
