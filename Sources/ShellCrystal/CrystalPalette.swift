//
//  CrystalPalette.swift
//  Role: the suite's own element colours for the crystal view, in this one file so they are easy to change later (Paul, 23 Nov 2026:
//        our own palette, not Jmol's or VESTA's). The hues are the ones a chemist expects (oxygen red, nitrogen blue, sulfur yellow,
//        carbon grey, hydrogen white, noble gases cyan, alkali metals violet, alkaline earths green), with lightness and saturation set
//        for the dark stage: every element reads at 3:1 or better against `stage`, which a unit test checks for all 118. The stage
//        stays dark in light and dark appearance, as the image panes do (plan 5.8), so one table serves both.
//        Generated once from OKLCH families (lightness, chroma, hue per group; f-block ramps), then lifted until 3:1; edit the hex
//        values directly from now on. Colour never names an element alone: the legend, the hover chip and VoiceOver do.
//

import simd

/// Element colours of the crystal view and the colour of its stage.
public nonisolated enum CrystalPalette {
    /// The stage behind the crystal, sRGB 0 to 1. The same dark grey in light and dark appearance.
    public static let stage = SIMD3<Double>(0.100, 0.105, 0.115)

    /// The colour of a bond is the colour of the atom it leaves, darkened by this factor (a half-bond per atom, as VESTA draws).
    public static let bondShade = 0.78

    /// The colour of the unit cell's edges and the a, b, c triad's labels.
    public static let cellEdge = SIMD3<Double>(0.90, 0.90, 0.92)

    /// The colour for an atomic number outside 1...118 (a damaged structure): a neutral grey that still reads on the stage.
    public static let unknown = SIMD3<Double>(0.62, 0.62, 0.62)

    /// sRGB colour of element `z`, 0 to 1 per channel.
    public static func color(z: Int) -> SIMD3<Double> {
        guard table.indices.contains(z - 1) else { return unknown }
        let hex = table[z - 1]
        return SIMD3(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
    }

    /// WCAG 2 contrast ratio of two sRGB colours (1 to 21).
    public static func contrast(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG 2 relative luminance of an sRGB colour.
    public static func luminance(_ c: SIMD3<Double>) -> Double {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.x) + 0.7152 * lin(c.y) + 0.0722 * lin(c.z)
    }

    /// One sRGB hex value per element, H (Z = 1) to Og (Z = 118).
    static let table: [UInt32] = [
        0xE8E8E8, 0x78D5E0, 0xB484E8, 0x81CE70, 0xFBA587, 0x868686,  // H He Li Be B C
        0x568EF9, 0xF84C45, 0xB1DD54, 0x6DC9D8, 0xAF77D9, 0x6CC46C,  // N O F Ne Na Mg
        0xD6B4B5, 0xE8BF98, 0xF99532, 0xF5DC3A, 0x9DD451, 0x63BDD0,  // Al Si P S Cl Ar
        0xA86BC9, 0x56BA69, 0xC7D2DE, 0xAEB9C4, 0x9CACC5, 0x83A8CF,  // K Ca Sc Ti V Cr
        0xA28ACD, 0xDE7949, 0xDE7D8D, 0x85CC87, 0xE58B55, 0x96A3CB,  // Mn Fe Co Ni Cu Zn
        0xCFA5AA, 0x81B8AC, 0xB093E5, 0xF2AF48, 0xD05F43, 0x5AB1C8,  // Ga Ge As Se Br Kr
        0xA25EB9, 0x3CB067, 0x9CD7DA, 0x91CBC6, 0x7ABFBF, 0x63B5B4,  // Rb Sr Y Zr Nb Mo
        0x56A7AC, 0x5CAEB2, 0x5CADB6, 0x74A8B8, 0xD1D1D1, 0xE5CF94,  // Tc Ru Rh Pd Ag Cd
        0xCE9C9F, 0x95AFC2, 0xA890D4, 0xDAA668, 0xA95CBB, 0x51A5BF,  // In Sn Sb Te I Xe
        0x9B52A9, 0x17A664, 0x7FE0C7, 0x7BDEC6, 0x77DBC6, 0x74D9C5,  // Cs Ba La Ce Pr Nd
        0x70D7C5, 0x6DD4C4, 0x69D2C3, 0x66D0C3, 0x63CDC2, 0x5FCBC2,  // Pm Sm Eu Gd Tb Dy
        0x5CC8C1, 0x59C6C0, 0x56C3C0, 0x53C1BF, 0x50BFBE, 0x87C8E8,  // Ho Er Tm Yb Lu Hf
        0x7BB9E5, 0x6DABDF, 0x679DD4, 0x6197CD, 0x5D8ECE, 0xC3CBD8,  // Ta W Re Os Ir Pt
        0xF0C543, 0xA9B8D2, 0xC89695, 0x8691B2, 0xBF85CD, 0xD39562,  // Au Hg Tl Pb Bi Po
        0xBB6690, 0x4899B7, 0x9A4C9F, 0x009C61, 0x6FC8FF, 0x71C4FF,  // At Rn Fr Ra Ac Th
        0x73C0FF, 0x75BCFF, 0x77B8FD, 0x7AB3FB, 0x7CAFF9, 0x7EABF6,  // Pa U Np Pu Am Cm
        0x80A7F4, 0x82A3F1, 0x839FEE, 0x859BEB, 0x8797E8, 0x8993E4,  // Bk Cf Es Fm Md No
        0x8A8FE1, 0xAB8696, 0xAB8696, 0xAB8696, 0xAB8696, 0xAB8696,  // Lr Rf Db Sg Bh Hs
        0xAB8696, 0xAB8696, 0xAB8696, 0xAB8696, 0xAB8696, 0xAB8696,  // Mt Ds Rg Cn Nh Fl
        0xAB8696, 0xAB8696, 0xB15B81, 0x418DAE,  // Mc Lv Ts Og
    ]
}
