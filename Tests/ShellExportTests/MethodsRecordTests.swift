import FormatoCore
import Foundation
import XCTest
@testable import ShellExport

/// Pins M1 and M2: the records of `MethodsTestRecords`, written as JSON (bytes equal to `Goldens/methods/<name>.json`) and as
/// a paragraph (text equal to `Goldens/methods/<name>.txt`); every golden follows `docs/schema/emsuite.methods-1.schema.json`
/// and holds no path, user name or host name.
///
/// To write the goldens again after a deliberate change, run the tests once with SHELLEXPORT_RECORD_GOLDENS=1 and review the
/// diff.
final class MethodsRecordTests: XCTestCase {
    static let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let goldens = here.appendingPathComponent("Goldens").appendingPathComponent("methods")
    static let schema = here.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs").appendingPathComponent("schema").appendingPathComponent("emsuite.methods-1.schema.json")

    // MARK: - M1 and M2

    func testRecordEqualsItsGolden() throws {
        let record = ProcessInfo.processInfo.environment["SHELLEXPORT_RECORD_GOLDENS"] == "1"
        for named in MethodsTestRecords.all {
            let json = try named.record.json()
            let url = Self.goldens.appendingPathComponent("\(named.name).json")
            if record {
                try FileManager.default.createDirectory(at: Self.goldens, withIntermediateDirectories: true)
                try Data(json.utf8).write(to: url)
                continue
            }
            let golden = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(json, golden, "\(named.name): the record differs from Goldens/methods/\(named.name).json")
        }
        if record { XCTFail("Goldens recorded; unset SHELLEXPORT_RECORD_GOLDENS and review the diff.") }
    }

    func testParagraphEqualsItsGolden() throws {
        let record = ProcessInfo.processInfo.environment["SHELLEXPORT_RECORD_GOLDENS"] == "1"
        for named in MethodsTestRecords.all {
            let paragraph = MethodsParagraph.text(for: named.record)
            let url = Self.goldens.appendingPathComponent("\(named.name).txt")
            if record {
                try FileManager.default.createDirectory(at: Self.goldens, withIntermediateDirectories: true)
                try Data(paragraph.utf8).write(to: url)
                continue
            }
            let golden = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(paragraph, golden, "\(named.name): the paragraph differs from Goldens/methods/\(named.name).txt")
        }
        if record { XCTFail("Goldens recorded; unset SHELLEXPORT_RECORD_GOLDENS and review the diff.") }
    }

    /// A golden reads back as the record it was written from, and carries the record's paragraph.
    func testGoldenReadsBackAsItsRecord() throws {
        for named in MethodsTestRecords.all {
            let golden = try String(contentsOf: Self.goldens.appendingPathComponent("\(named.name).json"), encoding: .utf8)
            XCTAssertEqual(try MethodsRecord.decode(golden), named.record, named.name)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(golden.utf8)) as? [String: Any], named.name)
            XCTAssertEqual(object["paragraph"] as? String, named.record.paragraph, named.name)
            XCTAssertEqual(object["schema"] as? String, "emsuite.methods/1", named.name)
        }
    }

    /// Swift's own coders agree with the canonical text on keys and values.
    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for named in MethodsTestRecords.all {
            let data = try encoder.encode(named.record)
            XCTAssertEqual(try JSONDecoder().decode(MethodsRecord.self, from: data), named.record, named.name)
            XCTAssertEqual(try MethodsRecord.decode(String(decoding: data, as: UTF8.self)).json(), try named.record.json(), named.name)
        }
    }

    func testGoldensFollowTheSchema() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Self.schema)) as? [String: Any])
        XCTAssertEqual(schema["title"] as? String, MethodsRecord.currentSchema)
        for named in MethodsTestRecords.all {
            let data = try Data(contentsOf: Self.goldens.appendingPathComponent("\(named.name).json"))
            let instance = try JSONSerialization.jsonObject(with: data)
            var problems: [String] = []
            SchemaCheck(root: schema).check(instance, against: schema, at: "$", problems: &problems)
            XCTAssertEqual(problems, [], named.name)
        }
        // The check itself finds a missing key, an extra key, a wrong type and a path for a file name.
        var problems: [String] = []
        let broken: [String: Any] = ["fileName": "/Users/someone/frame.dm4", "byteCount": "12", "fingerprint": "abc", "kind": "image",
                                     "shape": [2], "extra": true]
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let sourceSchema = try XCTUnwrap(defs["source"] as? [String: Any])
        SchemaCheck(root: schema).check(broken, against: sourceSchema, at: "$", problems: &problems)
        XCTAssertEqual(problems.count, 5, "\(problems)")
    }

    /// No golden holds a path, this Mac's user name or its host name.
    func testNoGoldenHoldsAPathUserOrHost() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.goldens, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2 * MethodsTestRecords.all.count)
        var forbidden = MethodsJSON.pathMarkers + ["/Users/", "/home/", "~/", "file://"]
        for name in [NSUserName(), Self.hostName(), Self.hostName().split(separator: ".").first.map(String.init) ?? ""]
            where name.count >= 4 {
            forbidden.append(name)
        }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(file.lastPathComponent) holds \"\(marker)\"")
            }
        }
    }

    // MARK: - Nothing private

    func testSourceKeepsOnlyFileNames() throws {
        let entry = FormatoMetadataEntry(key: "axes.x.scale", value: .number(0.25), units: "nm",
                                         provenance: FormatoProvenance(file: "/Users/someone/data/grain_04.dm4", source: "ImageList.2",
                                                                       rule: "as stored"))
        let source = MethodsRecord.Source(fileName: "/Users/someone/data/grain_04.dm4", byteCount: 1, fingerprint: Self.fingerprint,
                                          kind: "image", shape: [1], calibrations: [entry])
        XCTAssertEqual(source.fileName, "grain_04.dm4")
        XCTAssertEqual(source.calibrations.first?.provenance.file, "grain_04.dm4")
        XCTAssertEqual(source.calibrations.first?.provenance.source, "ImageList.2")
        XCTAssertEqual(MethodsRecord.Source(fileName: #"C:\Data\frame.dm4"#, byteCount: 1, fingerprint: Self.fingerprint,
                                            kind: "image", shape: []).fileName, "frame.dm4")

        // A path read back from JSON is cut to its name too.
        var record = Self.minimal
        record.sources = [source]
        let json = try record.json().replacingOccurrences(of: #""fileName":"grain_04.dm4""#, with: #""fileName":"/data/x/grain_04.dm4""#)
        XCTAssertTrue(json.contains("/data/x/"))
        XCTAssertEqual(try MethodsRecord.decode(json).sources.first?.fileName, "grain_04.dm4")
    }

    func testTextHoldingAPathIsRefused() {
        var record = Self.minimal
        record.steps = [MethodsRecord.Step(name: "Loading", method: "the reader",
                                           settings: [MethodsRecord.Quantity(name: "folder", value: .text("/Users/someone/data"))])]
        XCTAssertThrowsError(try record.json()) { error in
            XCTAssertEqual(error as? MethodsRecordError, .privateText("/Users/someone/data"))
        }
        record.steps = []
        record.drawn = ["file:///Volumes/scope/frame.dm4"]
        XCTAssertThrowsError(try record.json())
        record.drawn = []
        record.citations = [MethodsRecord.Citation(text: "~/notes.txt")]
        XCTAssertThrowsError(try record.json())
    }

    func testFingerprintNumbersAndSchemaAreChecked() throws {
        var record = Self.minimal
        record.sources = [MethodsRecord.Source(fileName: "a.dm4", byteCount: 1, fingerprint: Self.fingerprint.uppercased(),
                                               kind: "image", shape: [])]
        XCTAssertThrowsError(try record.json()) { error in
            XCTAssertEqual(error as? MethodsRecordError, .notAFingerprint(Self.fingerprint.uppercased()))
        }
        record.sources = []
        record.results = [MethodsRecord.Quantity(name: "The mean", value: .number(.nan))]
        XCTAssertThrowsError(try record.json()) { error in
            XCTAssertEqual(error as? MethodsRecordError, .notFinite("The mean"))
        }
        record.results = []
        let other = try record.json().replacingOccurrences(of: "emsuite.methods/1", with: "emsuite.methods/2")
        XCTAssertThrowsError(try MethodsRecord.decode(other)) { error in
            XCTAssertEqual(error as? MethodsRecordError, .unknownSchema("emsuite.methods/2"))
        }
    }

    // MARK: - The canonical form

    func testNumbersAndEscaping() {
        XCTAssertEqual(MethodsJSON.numberText(2048), "2048")
        XCTAssertEqual(MethodsJSON.numberText(-0.0), "0")
        XCTAssertEqual(MethodsJSON.numberText(0.4), "0.4")
        XCTAssertEqual(MethodsJSON.numberText(4.0495), "4.0495")
        XCTAssertEqual(MethodsJSON.numberText(-2.5), "-2.5")
        XCTAssertEqual(MethodsJSON.numberText(0.1 + 0.2), "0.30000000000000004")
        var out = ""
        MethodsJSON.writeString("a\"b\\c/d\n\t\u{01}Å", into: &out)
        XCTAssertEqual(out, #""a\"b\\c/d\n\t\u0001Å""#)
        out = ""
        MethodsJSON.object(["b": .integer(1), "a": .array([.bool(true), .number(0.5)]), "B": .string("x")]).write(into: &out)
        XCTAssertEqual(out, #"{"B":"x","a":[true,0.5],"b":1}"#)
    }

    func testParagraphWords() {
        XCTAssertEqual(MethodsParagraph.list([]), "")
        XCTAssertEqual(MethodsParagraph.list(["a"]), "a")
        XCTAssertEqual(MethodsParagraph.list(["a", "b"]), "a and b")
        XCTAssertEqual(MethodsParagraph.list(["a", "b", "c"]), "a, b and c")
        XCTAssertEqual(MethodsParagraph.date("2026-11-03"), "3 Nov 2026")
        XCTAssertEqual(MethodsParagraph.date("2026-13-03"), "2026-13-03")
        XCTAssertEqual(MethodsParagraph.date("November"), "November")
        XCTAssertEqual(MethodsParagraph.calibrationName("Acquisition_instrument.TEM.beam_energy"), "beam energy")
        XCTAssertEqual(MethodsParagraph.cellPhrase(MethodsRecord.Cell(a: 5.1, b: 5.2, c: 5.3, alpha: 90, beta: 99.5, gamma: 90)),
                       "a = 5.1 Å, b = 5.2 Å, c = 5.3 Å, α = 90°, β = 99.5°, γ = 90°")
        XCTAssertEqual(MethodsParagraph.cellPhrase(MethodsRecord.Cell(a: 4, b: 4, c: 6, alpha: 90, beta: 90, gamma: 90)), "a = 4 Å, c = 6 Å")
        XCTAssertEqual(MethodsParagraph.text(for: Self.minimal), "The analysis used Electron Microscopy Studio 2.4.0.")
    }

    // MARK: - In a figure

    /// The figure's files carry the record's canonical JSON, and it reads back as the record.
    func testFigureMetadataCarriesTheRecord() throws {
        let named = MethodsTestRecords.diffraction
        let metadata = try FigureMetadata(title: "Pattern", creator: "EMSuiteUI tests", methods: named.record)
        XCTAssertEqual(metadata.methodsRecord, try named.record.json())
        let png = try FigureRenderer.png(FigureTestScenes.overlay.scene, scale: 1, metadata: metadata)
        let entries = try FormatoPNG.textEntries(in: png)
        let description = try XCTUnwrap(entries.first { $0.keyword == "Description" }?.value)
        XCTAssertEqual(try MethodsRecord.decode(description), named.record)
        XCTAssertTrue(FigureRenderer.svg(FigureTestScenes.overlay.scene, metadata: metadata)
            .contains("<metadata>{&quot;app&quot;:{&quot;name&quot;:&quot;Electron Microscopy Studio&quot;"))
    }

    // MARK: - Helpers

    static let fingerprint = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    static let minimal = MethodsRecord(app: MethodsTestRecords.studio, room: "imaging", exportKind: "png")

    static func hostName() -> String {
        let size = 256
        var buffer = [CChar](repeating: 0, count: size)
        guard gethostname(&buffer, size - 1) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// A small JSON Schema check, enough for the record's schema: `$ref` into `$defs`, `type` (one or a list), `const`, `required`,
/// `properties`, `additionalProperties: false`, `items`, `pattern` and `minimum`. Each problem is one line naming its place.
struct SchemaCheck {
    let root: [String: Any]

    func check(_ value: Any, against schema: [String: Any], at path: String, problems: inout [String]) {
        if let ref = schema["$ref"] as? String {
            let name = ref.replacingOccurrences(of: "#/$defs/", with: "")
            guard let defs = root["$defs"] as? [String: Any], let target = defs[name] as? [String: Any] else {
                problems.append("\(path): no definition \(ref)")
                return
            }
            check(value, against: target, at: path, problems: &problems)
            return
        }
        if let constant = schema["const"] as? String, value as? String != constant {
            problems.append("\(path): not \(constant)")
        }
        if let type = schema["type"] {
            let types = (type as? [String]) ?? [(type as? String) ?? ""]
            guard types.contains(where: { Self.matches(value, $0) }) else {
                problems.append("\(path): not \(types.joined(separator: " or "))")
                return
            }
        }
        if let pattern = schema["pattern"] as? String, let text = value as? String,
           text.range(of: pattern, options: .regularExpression) == nil {
            problems.append("\(path): \"\(text)\" does not match \(pattern)")
        }
        if let minimum = schema["minimum"] as? Double, let number = value as? NSNumber, number.doubleValue < minimum {
            problems.append("\(path): below \(minimum)")
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for key in schema["required"] as? [String] ?? [] where object[key] == nil {
                problems.append("\(path): no \(key)")
            }
            for (key, member) in object.sorted(by: { $0.key < $1.key }) {
                if let property = properties[key] as? [String: Any] {
                    check(member, against: property, at: "\(path).\(key)", problems: &problems)
                } else if schema["additionalProperties"] as? Bool == false {
                    problems.append("\(path): \(key) is not in the schema")
                }
            }
        }
        if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
            for (index, element) in array.enumerated() {
                check(element, against: items, at: "\(path)[\(index)]", problems: &problems)
            }
        }
    }

    /// JSONSerialization reads every number and boolean as an NSNumber; a boolean is told apart by its Core Foundation type.
    static func matches(_ value: Any, _ type: String) -> Bool {
        let number = value as? NSNumber
        let isBool = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return isBool
        case "number": return number != nil && !isBool
        case "integer": return number.map { !isBool && $0.doubleValue == $0.doubleValue.rounded() } ?? false
        default: return false
        }
    }
}
