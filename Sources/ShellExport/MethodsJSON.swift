//
//  MethodsJSON.swift
//  Role: the methods record's canonical JSON, written by hand so its bytes are the same on every Mac and every Foundation
//        (pin M1). JSONEncoder is not used: its number and slash formats are its own.
//
//  THE FORM: no whitespace; object keys sorted by their UTF-8 bytes (Python's `sort_keys`); an absent optional is an absent key,
//  never `null`. Strings are UTF-8 as they are, with `"` and `\` escaped, `\b \f \n \r \t` as such and other control characters
//  as `\u00xx`; `/` is not escaped. This is Python's `json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False)`
//  once whole floats are written as integers.
//
//  NUMBERS: an integer as its digits. A Double that is a whole number below 10^15 in size is written as an integer ("200", not
//  "200.0"; -0 is "0"); any other is Swift's shortest round-trip `description` ("0.02", "4.0495", "1e-05"), which is Python's
//  `repr` for the values a record holds (the two may differ in form for whole numbers from 10^15 to 10^16). NaN and infinity
//  are refused. The paragraph writes its numbers the same way.
//

import FormatoCore
import Foundation

/// A JSON value as the methods record writes it.
enum MethodsJSON {
    case object([String: MethodsJSON])
    case array([MethodsJSON])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)

    /// Appends the value's canonical text to `out`.
    func write(into out: inout String) {
        switch self {
        case .object(let members):
            out += "{"
            let keys = members.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (index, key) in keys.enumerated() {
                if index > 0 { out += "," }
                Self.writeString(key, into: &out)
                out += ":"
                if let value = members[key] { value.write(into: &out) }
            }
            out += "}"
        case .array(let elements):
            out += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { out += "," }
                element.write(into: &out)
            }
            out += "]"
        case .string(let text):
            Self.writeString(text, into: &out)
        case .integer(let value):
            out += String(value)
        case .number(let value):
            out += Self.numberText(value)
        case .bool(let value):
            out += value ? "true" : "false"
        }
    }

    /// A finite Double as the record writes it: a whole number below 10^15 as an integer, any other as its shortest
    /// round-trip text.
    static func numberText(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return value.description
    }

    static func writeString(_ text: String, into out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    // MARK: - Checked leaves

    /// What a path looks like in text: a user's or a system's folder, a home-relative path, a file URL.
    static let pathMarkers = ["/Users/", "/home/", "/Volumes/", "/private/", "/var/folders/", "/tmp/", "~/", "file://",
                              "\\Users\\", "\\Documents and Settings\\"]

    /// A text leaf, refused when it holds a path.
    static func text(_ value: String) throws -> MethodsJSON {
        for marker in pathMarkers where value.contains(marker) { throw MethodsRecordError.privateText(value) }
        return .string(value)
    }

    /// A number leaf, refused when it is not finite; `field` names it in the error.
    static func finite(_ value: Double, _ field: String) throws -> MethodsJSON {
        guard value.isFinite else { throw MethodsRecordError.notFinite(field) }
        return .number(value)
    }

    static func value(_ value: FormatoValue, _ field: String) throws -> MethodsJSON {
        switch value {
        case .number(let number): return try finite(number, field)
        case .text(let string): return try text(string)
        case .flag(let flag): return .bool(flag)
        case .texts(let strings): return try .array(strings.map { try text($0) })
        }
    }
}

// MARK: - The record as a JSON value

extension MethodsRecord {
    func jsonValue() throws -> MethodsJSON {
        guard schema == Self.currentSchema else { throw MethodsRecordError.unknownSchema(schema) }
        var object: [String: MethodsJSON] = [:]
        object["schema"] = try MethodsJSON.text(schema)
        object["app"] = try app.jsonValue()
        object["room"] = try MethodsJSON.text(room)
        object["exportKind"] = try MethodsJSON.text(exportKind)
        object["kits"] = try .array(kits.map { try $0.jsonValue() })
        object["references"] = try .array(references.map { try $0.jsonValue() })
        object["sources"] = try .array(sources.map { try $0.jsonValue() })
        object["phases"] = try .array(phases.map { try $0.jsonValue() })
        object["steps"] = try .array(steps.map { try $0.jsonValue() })
        object["results"] = try .array(results.map { try $0.jsonValue() })
        object["drawn"] = try .array(drawn.map { try MethodsJSON.text($0) })
        object["citations"] = try .array(citations.map { try $0.jsonValue() })
        object["paragraph"] = try MethodsJSON.text(paragraph)
        return .object(object)
    }
}

extension MethodsRecord.Software {
    func jsonValue() throws -> MethodsJSON {
        try .object(["name": MethodsJSON.text(name), "version": MethodsJSON.text(version)])
    }
}

extension MethodsRecord.Source {
    func jsonValue() throws -> MethodsJSON {
        let hexDigits = Set("0123456789abcdef")
        guard fingerprint.count == 64, fingerprint.allSatisfy({ hexDigits.contains($0) }) else {
            throw MethodsRecordError.notAFingerprint(fingerprint)
        }
        var object: [String: MethodsJSON] = [:]
        object["fileName"] = try MethodsJSON.text(fileName)
        object["byteCount"] = .integer(byteCount)
        object["fingerprint"] = .string(fingerprint)
        object["kind"] = try MethodsJSON.text(kind)
        object["shape"] = .array(shape.map { MethodsJSON.integer($0) })
        object["calibrations"] = try .array(calibrations.map { entry -> MethodsJSON in
            var calibration: [String: MethodsJSON] = [:]
            calibration["key"] = try MethodsJSON.text(entry.key)
            calibration["value"] = try MethodsJSON.value(entry.value, "calibration \(entry.key)")
            if let units = entry.units { calibration["units"] = try MethodsJSON.text(units) }
            calibration["provenance"] = try .object(["file": MethodsJSON.text(entry.provenance.file),
                                                     "source": MethodsJSON.text(entry.provenance.source),
                                                     "rule": MethodsJSON.text(entry.provenance.rule)])
            return .object(calibration)
        })
        return .object(object)
    }
}

extension MethodsRecord.Phase {
    func jsonValue() throws -> MethodsJSON {
        var cellObject: [String: MethodsJSON] = [:]
        cellObject["a"] = try MethodsJSON.finite(cell.a, "\(name) a")
        cellObject["b"] = try MethodsJSON.finite(cell.b, "\(name) b")
        cellObject["c"] = try MethodsJSON.finite(cell.c, "\(name) c")
        cellObject["alpha"] = try MethodsJSON.finite(cell.alpha, "\(name) alpha")
        cellObject["beta"] = try MethodsJSON.finite(cell.beta, "\(name) beta")
        cellObject["gamma"] = try MethodsJSON.finite(cell.gamma, "\(name) gamma")
        var object: [String: MethodsJSON] = [:]
        object["name"] = try MethodsJSON.text(name)
        object["spaceGroup"] = try MethodsJSON.text(spaceGroup)
        object["cell"] = .object(cellObject)
        object["source"] = try MethodsJSON.text(source)
        if let fetched { object["fetched"] = try MethodsJSON.text(fetched) }
        object["licence"] = try MethodsJSON.text(licence)
        object["latticeEdited"] = .bool(latticeEdited)
        return .object(object)
    }
}

extension MethodsRecord.Quantity {
    func jsonValue() throws -> MethodsJSON {
        var object: [String: MethodsJSON] = [:]
        object["name"] = try MethodsJSON.text(name)
        object["value"] = try MethodsJSON.value(value, name)
        if let units { object["units"] = try MethodsJSON.text(units) }
        return .object(object)
    }
}

extension MethodsRecord.Step {
    func jsonValue() throws -> MethodsJSON {
        var object: [String: MethodsJSON] = [:]
        object["name"] = try MethodsJSON.text(name)
        object["method"] = try MethodsJSON.text(method)
        if let reference { object["reference"] = try reference.jsonValue() }
        object["settings"] = try .array(settings.map { try $0.jsonValue() })
        return .object(object)
    }
}

extension MethodsRecord.Citation {
    func jsonValue() throws -> MethodsJSON {
        var object: [String: MethodsJSON] = [:]
        object["text"] = try MethodsJSON.text(text)
        if let doi { object["doi"] = try MethodsJSON.text(doi) }
        return .object(object)
    }
}
