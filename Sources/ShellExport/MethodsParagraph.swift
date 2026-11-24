//
//  MethodsParagraph.swift
//  Role: the methods record as a paragraph for a paper, in plain past tense (pin M2). Edit > Copy Methods Paragraph puts it on
//        the clipboard; the record's JSON carries it under `paragraph`.
//
//  THE TEXT is written from the record alone, the same on every Mac: numbers as the record writes them (`MethodsJSON.numberText`:
//  "." for the decimal point, no grouping, the en_US_POSIX form whatever the Mac's locale), dates as "23 Nov 2026", lists as
//  "a, b and c". The sentences, in order:
//    1. the sources and the software: "The diffraction pattern (frame_012.dm4, 2048 × 2048, scale 0.01 nm⁻¹ as stored) was
//       analysed with Electron Microscopy Studio 2.4.0 (DiffractoKit 0.21.0)." Without a source: "The analysis used ...".
//    2. the phases: "The phase was aluminium (Fm-3m, a = 4.0495 Å; Materials Project mp-134, fetched 23 Nov 2026, CC BY 4.0,
//       lattice edited)."
//    3. one per step: "Indexing used the kinematic model (py4DSTEM 0.14.0) with excitation error 0.02 Å⁻¹."
//    4. one per result: "The fitted scale's difference from the stored scale was 0.4 %."
//    5. what was drawn: "The export shows the pattern and a scale bar."
//  A calibration is named by the last component of its key, underscores as spaces ("Acquisition_instrument.TEM.beam_energy" is
//  "beam energy"). A flag reads "on" or "off". What to cite stays in the record: a paper cites by its own markers.
//

import FormatoCore
import Foundation

/// Writes a methods record as a paragraph for a paper.
public enum MethodsParagraph {
    /// The paragraph, sentences joined by one space.
    public static func text(for record: MethodsRecord) -> String {
        var sentences = [analysisSentence(record)]
        if let phases = phaseSentence(record.phases) { sentences.append(phases) }
        for step in record.steps { sentences.append(stepSentence(step)) }
        for result in record.results {
            sentences.append(capitalized("\(result.name) was \(value(result.value))\(units(result.units))."))
        }
        if !record.drawn.isEmpty { sentences.append("The export shows \(list(record.drawn)).") }
        return sentences.joined(separator: " ")
    }

    // MARK: - Sentences

    static func analysisSentence(_ record: MethodsRecord) -> String {
        var software = "\(record.app.name) \(record.app.version)"
        if !record.kits.isEmpty { software += " (" + record.kits.map { "\($0.name) \($0.version)" }.joined(separator: ", ") + ")" }
        guard !record.sources.isEmpty else { return "The analysis used \(software)." }
        let verb = record.sources.count == 1 ? "was" : "were"
        return capitalized("\(list(record.sources.map(sourcePhrase))) \(verb) analysed with \(software).")
    }

    static func sourcePhrase(_ source: MethodsRecord.Source) -> String {
        var details = [source.fileName]
        if !source.shape.isEmpty { details.append(source.shape.map { String($0) }.joined(separator: " × ")) }
        if !source.calibrations.isEmpty {
            details.append(list(source.calibrations.map { entry in
                "\(calibrationName(entry.key)) \(value(entry.value))\(units(entry.units))"
            }) + " as stored")
        }
        return "the \(source.kind) (\(details.joined(separator: ", ")))"
    }

    static func phaseSentence(_ phases: [MethodsRecord.Phase]) -> String? {
        guard !phases.isEmpty else { return nil }
        let described = list(phases.map(phasePhrase))
        return phases.count == 1 ? "The phase was \(described)." : "The phases were \(described)."
    }

    static func phasePhrase(_ phase: MethodsRecord.Phase) -> String {
        var origin: [String] = []
        if !phase.source.isEmpty { origin.append(phase.source) }
        if let fetched = phase.fetched { origin.append("fetched \(date(fetched))") }
        if !phase.licence.isEmpty { origin.append(phase.licence) }
        if phase.latticeEdited { origin.append("lattice edited") }
        var inside = "\(phase.spaceGroup), \(cellPhrase(phase.cell))"
        if !origin.isEmpty { inside += "; " + origin.joined(separator: ", ") }
        return "\(phase.name) (\(inside))"
    }

    /// A cubic cell by a; a tetragonal or hexagonal one by a and c; any other by all six parameters.
    static func cellPhrase(_ cell: MethodsRecord.Cell) -> String {
        let a = "a = \(MethodsJSON.numberText(cell.a)) Å"
        let rightAngles = cell.alpha == 90 && cell.beta == 90
        if cell.a == cell.b, cell.b == cell.c, rightAngles, cell.gamma == 90 { return a }
        if cell.a == cell.b, rightAngles, cell.gamma == 90 || cell.gamma == 120 {
            return "\(a), c = \(MethodsJSON.numberText(cell.c)) Å"
        }
        let b = MethodsJSON.numberText(cell.b), c = MethodsJSON.numberText(cell.c)
        let alpha = MethodsJSON.numberText(cell.alpha), beta = MethodsJSON.numberText(cell.beta)
        let gamma = MethodsJSON.numberText(cell.gamma)
        return "\(a), b = \(b) Å, c = \(c) Å, α = \(alpha)°, β = \(beta)°, γ = \(gamma)°"
    }

    static func stepSentence(_ step: MethodsRecord.Step) -> String {
        var sentence = "\(step.name) used \(step.method)"
        if let reference = step.reference { sentence += " (\(reference.name) \(reference.version))" }
        if !step.settings.isEmpty {
            sentence += " with " + list(step.settings.map { "\($0.name) \(value($0.value))\(units($0.units))" })
        }
        return capitalized(sentence + ".")
    }

    // MARK: - Words

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    static func value(_ value: FormatoValue) -> String {
        switch value {
        case .number(let number): MethodsJSON.numberText(number)
        case .text(let text): text
        case .flag(let flag): flag ? "on" : "off"
        case .texts(let texts): texts.joined(separator: ", ")
        }
    }

    /// " kV", or nothing for no units.
    static func units(_ units: String?) -> String {
        guard let units, !units.isEmpty else { return "" }
        return " " + units
    }

    /// The last component of a metadata key, underscores as spaces.
    static func calibrationName(_ key: String) -> String {
        let last = key.split(separator: ".").last.map(String.init) ?? key
        return last.replacingOccurrences(of: "_", with: " ")
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2026-11-23" as "23 Nov 2026"; any other text as it is.
    static func date(_ iso: String) -> String {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return iso }
        return "\(day) \(months[month - 1]) \(year)"
    }

    /// The first character in upper case.
    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
