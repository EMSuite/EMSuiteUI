//
//  CrystalDescription.swift
//  Role: the words of the crystal view: the one VoiceOver element's value (atoms per element), the legend's rows and the hover
//        chip. The label (phase, zone axis, tilt) is the app's, because only the document knows them; the view appends what it draws.
//

/// Words the crystal view speaks and shows.
public nonisolated enum CrystalDescription {
    /// "18 atoms: 18 silicon" or "5 atoms: 1 strontium, 1 titanium, 3 oxygen"; "No atoms" for an empty scene.
    public static func value(_ scene: CrystalScene, showsUnitCell: Bool) -> String {
        let counts = scene.elementCounts
        guard !counts.isEmpty else { return "No atoms" }
        let total = scene.atoms.count
        let parts = counts.map { "\($0.count) \(CrystalElements.name(z: $0.atomicNumber).lowercased())" }
        var text = "\(total) \(total == 1 ? "atom" : "atoms"): " + parts.joined(separator: ", ")
        if !scene.bonds.isEmpty { text += ", \(scene.bonds.count) \(scene.bonds.count == 1 ? "bond" : "bonds")" }
        if showsUnitCell, scene.cell != nil { text += ", unit cell shown" }
        return text
    }

    /// The legend's rows: symbol and name, in the order of `CrystalScene.elementCounts`.
    public static func legend(_ scene: CrystalScene) -> [(atomicNumber: Int, symbol: String, name: String)] {
        scene.elementCounts.map { (atomicNumber: $0.atomicNumber, symbol: CrystalElements.symbol(z: $0.atomicNumber),
                                   name: CrystalElements.name(z: $0.atomicNumber)) }
    }
}
