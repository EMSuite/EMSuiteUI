//
//  AddPhaseCrystal.swift
//  Role: the unit-cell picture of the Add Phase preview (EMSuiteUI#195, plan row MU3): the chosen entry's cell as VESTA draws
//        it, with DiffractoKit's bonds, in ShellCrystal's still crystal view (no zoom, no drag, no focus), and the words VoiceOver
//        says for it. The cell is seen a little off its c axis, so a cubic cell reads as a box and not a square. No numerics:
//        the sites and bonds are the kit's, mapped into ShellCrystal's plain data as the apps' crystal panes do.
//

import DiffractoCore
import ShellCrystal
import ShellPhaseLibrary
import simd
import SwiftUI

nonisolated enum AddPhaseCrystal {

    /// One unit cell of `structure` with its sites wrapped onto every face they touch, and each of the kit's bonds once (the kit
    /// lists a bond from both of its atoms). An empty scene for a structure without three lattice vectors.
    static func scene(_ structure: CrystalStructure) -> CrystalScene {
        let l = structure.cell.realLattice
        guard l.count == 3 else { return .empty }
        let sites = structure.sites.map { CrystalSite(fractional: $0.fractional, atomicNumber: $0.z, occupancy: $0.occupancy) }
        let bonds = structure.bonds.filter { b in
            b.site < b.neighbour || (b.site == b.neighbour && (b.image.x, b.image.y, b.image.z) > (0, 0, 0))
        }.map { CrystalBondInput(from: $0.site, to: $0.neighbour, image: $0.image) }
        return .unitCell(cell: simd_double3x3(columns: (l[0], l[1], l[2])), sites: sites, bonds: bonds)
    }

    /// The still view's orientation: looking down c turned a little toward a and b, with b toward the top, so all three cell
    /// directions show. The identity for a structure without three lattice vectors.
    static func orientation(_ structure: CrystalStructure) -> simd_double3x3 {
        let l = structure.cell.realLattice
        guard l.count == 3, l.allSatisfy({ simd_length($0) > 0 }) else { return matrix_identity_double3x3 }
        let a = simd_normalize(l[0]), b = simd_normalize(l[1]), c = simd_normalize(l[2])
        return CrystalTurn.lookingDown(c + 0.35 * a + 0.2 * b, up: b)
    }

    /// VoiceOver's label: "Unit cell of Al (mp-134)", or "Unit cell of Corundum (mp-1143), Al2O3" when the name is not the
    /// formula. The view adds its own value: the atoms per element, the bonds and "unit cell shown".
    static func label(name: String, materialID: String, formula: String) -> String {
        name == formula ? "Unit cell of \(name) (\(materialID))" : "Unit cell of \(name) (\(materialID)), \(formula)"
    }
}

/// The picture itself: a still crystal view of the entry's unit cell, a fixed height in the preview.
struct AddPhaseCellPicture: View {
    let preview: AddPhaseModel.Preview

    var body: some View {
        let structure = preview.structure
        CrystalView(AddPhaseCrystal.scene(structure), orientation: AddPhaseCrystal.orientation(structure), showsUnitCell: true,
                    interaction: .still,
                    accessibilityLabel: AddPhaseCrystal.label(name: preview.name, materialID: preview.materialID,
                                                              formula: structure.formula))
            .frame(height: 180)
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityIdentifier("addPhase.cellPicture")
    }
}
