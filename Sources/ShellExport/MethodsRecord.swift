//
//  MethodsRecord.swift
//  Role: the methods record of one export, schema `emsuite.methods/1` (`docs/schema/emsuite.methods-1.schema.json`): the app,
//        kit and reference versions, each source file by name, size and fingerprint with its calibrations, each phase with its
//        source and licence, the steps with every setting, the results, what was drawn and what to cite. The app fills it from
//        its lineage; every export with a safe place for it carries it (PNG text chunk, PDF metadata, SVG `<metadata>`, ...).
//
//  NOTHING PRIVATE: records travel with figures into papers and mail, so the record has no field for a path, a user name or a
//  host. A source is named by its file name only (a path given by mistake keeps its last component, as does a calibration's
//  provenance), and `json()` refuses any text that holds a path (`/Users/`, `/home/`, `~/`, `file://`, ...).
//  A calibration is FormatoCore's own `FormatoMetadataEntry`: its value, units and `FormatoProvenance`, not a second type.
//
//  `json()` is the record's canonical text (pin M1): see `MethodsJSON.swift` for keys, numbers and escaping. `Codable` reads
//  that text back (`decode(_:)`); the `paragraph` key it carries is written from the record, never read.
//

import FormatoCore
import Foundation

/// Why a methods record could not be written or read.
public enum MethodsRecordError: Error, Equatable, LocalizedError {
    /// A number is NaN or infinite; the associated value names its field.
    case notFinite(String)
    /// A text holds what looks like a path (a user's folder, a URL to a file); the associated value is the text.
    case privateText(String)
    /// A fingerprint is not 64 lowercase hexadecimal digits (a SHA-256).
    case notAFingerprint(String)
    /// The record names another schema than `emsuite.methods/1`.
    case unknownSchema(String)

    public var errorDescription: String? {
        switch self {
        case .notFinite(let field): "The methods record's \(field) is not a finite number."
        case .privateText(let text): "The methods record would carry a path, which it never holds: \"\(text)\"."
        case .notAFingerprint(let text): "\"\(text)\" is not a SHA-256 fingerprint (64 lowercase hexadecimal digits)."
        case .unknownSchema(let schema): "The methods record's schema is \"\(schema)\", not \"\(MethodsRecord.currentSchema)\"."
        }
    }
}

/// The methods record of one export: what was read, with which software, how and what came out.
public struct MethodsRecord: Sendable, Equatable, Codable {
    /// The schema this type writes and reads.
    public static let currentSchema = "emsuite.methods/1"

    /// A program and its version: the app, a kit, a reference package.
    public struct Software: Sendable, Equatable, Codable {
        public var name: String
        public var version: String

        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    /// One file the result was made from, by name, size and fingerprint, never by path.
    public struct Source: Sendable, Equatable, Codable {
        /// The file's name, without any folder.
        public let fileName: String
        /// The file's size in bytes.
        public var byteCount: Int
        /// The lineage's fingerprint of the file: SHA-256, 64 lowercase hexadecimal digits.
        public var fingerprint: String
        /// What the file holds, in words, lowercase ("diffraction pattern", "spectrum image").
        public var kind: String
        /// The data's shape as the room read it (width, height, channels ...).
        public var shape: [Int]
        /// The calibrations the file states, each with its FormatoCore provenance (the provenance's file is a name too).
        public let calibrations: [FormatoMetadataEntry]

        /// `fileName` and each calibration's provenance file keep only their last path component.
        public init(fileName: String, byteCount: Int, fingerprint: String, kind: String, shape: [Int],
                    calibrations: [FormatoMetadataEntry] = []) {
            self.fileName = MethodsRecord.nameOnly(fileName)
            self.byteCount = byteCount
            self.fingerprint = fingerprint
            self.kind = kind
            self.shape = shape
            self.calibrations = calibrations.map { entry in
                FormatoMetadataEntry(key: entry.key, value: entry.value, units: entry.units,
                                     provenance: FormatoProvenance(file: MethodsRecord.nameOnly(entry.provenance.file),
                                                                   source: entry.provenance.source, rule: entry.provenance.rule))
            }
        }

        enum CodingKeys: String, CodingKey {
            case fileName, byteCount, fingerprint, kind, shape, calibrations
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let calibrations = try container.decode([CalibrationCoding].self, forKey: .calibrations)
            try self.init(fileName: container.decode(String.self, forKey: .fileName),
                          byteCount: container.decode(Int.self, forKey: .byteCount),
                          fingerprint: container.decode(String.self, forKey: .fingerprint),
                          kind: container.decode(String.self, forKey: .kind),
                          shape: container.decode([Int].self, forKey: .shape),
                          calibrations: calibrations.map(\.entry))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(fileName, forKey: .fileName)
            try container.encode(byteCount, forKey: .byteCount)
            try container.encode(fingerprint, forKey: .fingerprint)
            try container.encode(kind, forKey: .kind)
            try container.encode(shape, forKey: .shape)
            try container.encode(calibrations.map { CalibrationCoding($0) }, forKey: .calibrations)
        }
    }

    /// A unit cell: lengths in ångström, angles in degrees.
    public struct Cell: Sendable, Equatable, Codable {
        public var a: Double
        public var b: Double
        public var c: Double
        public var alpha: Double
        public var beta: Double
        public var gamma: Double

        public init(a: Double, b: Double, c: Double, alpha: Double, beta: Double, gamma: Double) {
            self.a = a
            self.b = b
            self.c = c
            self.alpha = alpha
            self.beta = beta
            self.gamma = gamma
        }

        /// A cubic cell.
        public init(cubic a: Double) {
            self.init(a: a, b: a, c: a, alpha: 90, beta: 90, gamma: 90)
        }
    }

    /// One phase a result used, with where it came from and under which licence.
    public struct Phase: Sendable, Equatable, Codable {
        public var name: String
        /// The space group's Hermann–Mauguin symbol ("Fm-3m").
        public var spaceGroup: String
        public var cell: Cell
        /// Where the structure came from ("Materials Project mp-134", a CIF's file name); empty when unknown.
        public var source: String
        /// The day it was fetched, ISO 8601 ("2026-11-23"), for a database entry.
        public var fetched: String?
        /// The structure's licence ("CC BY 4.0"); empty when unknown.
        public var licence: String
        /// The lattice was edited after it was read.
        public var latticeEdited: Bool

        public init(name: String, spaceGroup: String, cell: Cell, source: String, fetched: String? = nil, licence: String,
                    latticeEdited: Bool = false) {
            self.name = name
            self.spaceGroup = spaceGroup
            self.cell = cell
            self.source = source
            self.fetched = fetched
            self.licence = licence
            self.latticeEdited = latticeEdited
        }
    }

    /// A named value with its units: a step's setting or a result. The value is FormatoCore's `FormatoValue`.
    public struct Quantity: Sendable, Equatable, Codable {
        /// Lowercase words for a setting ("excitation error"); a sentence's subject for a result ("The Fe content").
        public var name: String
        public var value: FormatoValue
        public var units: String?

        public init(name: String, value: FormatoValue, units: String? = nil) {
            self.name = name
            self.value = value
            self.units = units
        }

        enum CodingKeys: String, CodingKey {
            case name, value, units
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            value = try container.decode(ValueCoding.self, forKey: .value).value
            units = try container.decodeIfPresent(String.self, forKey: .units)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(ValueCoding(value), forKey: .value)
            try container.encodeIfPresent(units, forKey: .units)
        }
    }

    /// One step of the lineage, in order, with every setting.
    public struct Step: Sendable, Equatable, Codable {
        /// The step as a noun ("Indexing", "Background subtraction").
        public var name: String
        /// The method as a noun phrase ("the kinematic model", "a power law").
        public var method: String
        /// The reference package the method follows, when a number came from one.
        public var reference: Software?
        public var settings: [Quantity]

        public init(name: String, method: String, reference: Software? = nil, settings: [Quantity] = []) {
            self.name = name
            self.method = method
            self.reference = reference
            self.settings = settings
        }
    }

    /// What to cite: a reference in words and its DOI where it has one.
    public struct Citation: Sendable, Equatable, Codable {
        public var text: String
        public var doi: String?

        public init(text: String, doi: String? = nil) {
            self.text = text
            self.doi = doi
        }
    }

    /// Always `currentSchema` for a record made here; a decoded record keeps what it read and `json()` refuses another.
    public private(set) var schema: String = MethodsRecord.currentSchema
    public var app: Software
    /// The room the export came from ("diffraction", "eds").
    public var room: String
    /// The export's kind ("figure-pdf", "spectrum-csv", "ang").
    public var exportKind: String
    public var kits: [Software]
    public var references: [Software]
    public var sources: [Source]
    public var phases: [Phase]
    public var steps: [Step]
    public var results: [Quantity]
    /// What the export draws or holds, as noun phrases ("the pattern", "a scale bar").
    public var drawn: [String]
    public var citations: [Citation]

    public init(app: Software, room: String, exportKind: String, kits: [Software] = [], references: [Software] = [],
                sources: [Source] = [], phases: [Phase] = [], steps: [Step] = [], results: [Quantity] = [],
                drawn: [String] = [], citations: [Citation] = []) {
        self.app = app
        self.room = room
        self.exportKind = exportKind
        self.kits = kits
        self.references = references
        self.sources = sources
        self.phases = phases
        self.steps = steps
        self.results = results
        self.drawn = drawn
        self.citations = citations
    }

    /// The paragraph for a paper (`MethodsParagraph`).
    public var paragraph: String { MethodsParagraph.text(for: self) }

    /// The record as its canonical JSON (pin M1): sorted keys, no whitespace, numbers as `MethodsJSON.numberText(_:)` writes them,
    /// the paragraph under `paragraph`. Throws for a number that is not finite, a text that holds a path, a fingerprint that
    /// is not a SHA-256, or another schema.
    public func json() throws -> String {
        var out = ""
        try jsonValue().write(into: &out)
        return out
    }

    /// A record from its JSON, as `json()` writes it. The `paragraph` key is not read.
    public static func decode(_ json: String) throws -> MethodsRecord {
        let record = try JSONDecoder().decode(MethodsRecord.self, from: Data(json.utf8))
        guard record.schema == currentSchema else { throw MethodsRecordError.unknownSchema(record.schema) }
        return record
    }

    /// The last path component of `name` ("/a/b/frame.dm4" is "frame.dm4"), so no folder is ever kept.
    static func nameOnly(_ name: String) -> String {
        guard let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last else { return "" }
        return String(last)
    }
}

// MARK: - Coding FormatoCore's values

/// A `FormatoValue` as JSON: a number, a string, a boolean or an array of strings.
struct ValueCoding: Codable {
    let value: FormatoValue

    init(_ value: FormatoValue) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            value = .flag(flag)
        } else if let number = try? container.decode(Double.self) {
            value = .number(number)
        } else if let text = try? container.decode(String.self) {
            value = .text(text)
        } else {
            let texts = try container.decode([String].self)
            value = .texts(texts)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .number(let number): try container.encode(number)
        case .text(let text): try container.encode(text)
        case .flag(let flag): try container.encode(flag)
        case .texts(let texts): try container.encode(texts)
        }
    }
}

/// A calibration as JSON: FormatoCore's `FormatoMetadataEntry` with its `FormatoProvenance`.
struct CalibrationCoding: Codable {
    struct Provenance: Codable {
        let file: String
        let source: String
        let rule: String
    }

    let key: String
    let value: ValueCoding
    let units: String?
    let provenance: Provenance

    init(_ entry: FormatoMetadataEntry) {
        key = entry.key
        value = ValueCoding(entry.value)
        units = entry.units
        provenance = Provenance(file: entry.provenance.file, source: entry.provenance.source, rule: entry.provenance.rule)
    }

    var entry: FormatoMetadataEntry {
        FormatoMetadataEntry(key: key, value: value.value, units: units,
                             provenance: FormatoProvenance(file: provenance.file, source: provenance.source, rule: provenance.rule))
    }
}
