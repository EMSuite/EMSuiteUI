//
//  CrystalElements.swift
//  Role: what the crystal view needs to know about an element to draw and name it: symbol, English name (VoiceOver and the hover
//        chip), and the covalent radius that sizes its ball. These are drawing data, never a number a user reads: bonds come from
//        DiffractoKit (row K8), not from these radii.
//        Radii: Cordero et al., Dalton Trans. 2008, 2832 (the table ASE and pymatgen carry), low-spin values for Mn, Fe and Co as ASE
//        has them; elements past Cm have no measured value and draw at `fallbackRadius`.
//

/// Element data for drawing.
public nonisolated enum CrystalElements {
    /// Symbols, H (Z = 1) to Og (Z = 118).
    public static let symbols: [String] = ("H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se "
        + "Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os "
        + "Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og")
        .split(separator: " ").map(String.init)

    /// English names, in the order of `symbols`.
    public static let names: [String] = ("Hydrogen Helium Lithium Beryllium Boron Carbon Nitrogen Oxygen Fluorine Neon Sodium Magnesium "
        + "Aluminium Silicon Phosphorus Sulfur Chlorine Argon Potassium Calcium Scandium Titanium Vanadium Chromium Manganese Iron Cobalt "
        + "Nickel Copper Zinc Gallium Germanium Arsenic Selenium Bromine Krypton Rubidium Strontium Yttrium Zirconium Niobium Molybdenum "
        + "Technetium Ruthenium Rhodium Palladium Silver Cadmium Indium Tin Antimony Tellurium Iodine Xenon Caesium Barium Lanthanum "
        + "Cerium Praseodymium Neodymium Promethium Samarium Europium Gadolinium Terbium Dysprosium Holmium Erbium Thulium Ytterbium "
        + "Lutetium Hafnium Tantalum Tungsten Rhenium Osmium Iridium Platinum Gold Mercury Thallium Lead Bismuth Polonium Astatine Radon "
        + "Francium Radium Actinium Thorium Protactinium Uranium Neptunium Plutonium Americium Curium Berkelium Californium Einsteinium "
        + "Fermium Mendelevium Nobelium Lawrencium Rutherfordium Dubnium Seaborgium Bohrium Hassium Meitnerium Darmstadtium Roentgenium "
        + "Copernicium Nihonium Flerovium Moscovium Livermorium Tennessine Oganesson")
        .split(separator: " ").map(String.init)

    /// Covalent radii in Å, H to Cm (Cordero 2008).
    static let covalentRadii: [Double] = [
        0.31, 0.28, 1.28, 0.96, 0.84, 0.76, 0.71, 0.66, 0.57, 0.58,                 // H to Ne
        1.66, 1.41, 1.21, 1.11, 1.07, 1.05, 1.02, 1.06,                             // Na to Ar
        2.03, 1.76, 1.70, 1.60, 1.53, 1.39, 1.39, 1.32, 1.26, 1.24, 1.32, 1.22,     // K to Zn
        1.22, 1.20, 1.19, 1.20, 1.20, 1.16,                                         // Ga to Kr
        2.20, 1.95, 1.90, 1.75, 1.64, 1.54, 1.47, 1.46, 1.42, 1.39, 1.45, 1.44,     // Rb to Cd
        1.42, 1.39, 1.39, 1.38, 1.39, 1.40,                                         // In to Xe
        2.44, 2.15,                                                                 // Cs, Ba
        2.07, 2.04, 2.03, 2.01, 1.99, 1.98, 1.98, 1.96, 1.94, 1.92, 1.92, 1.89, 1.90, 1.87, 1.87,  // La to Lu
        1.75, 1.70, 1.62, 1.51, 1.44, 1.41, 1.36, 1.36, 1.32,                       // Hf to Hg
        1.45, 1.46, 1.48, 1.40, 1.50, 1.50,                                         // Tl to Rn
        2.60, 2.21,                                                                 // Fr, Ra
        2.15, 2.06, 2.00, 1.96, 1.90, 1.87, 1.80, 1.69,                             // Ac to Cm
    ]

    /// The radius drawn for an element with no tabulated value.
    public static let fallbackRadius = 1.5

    /// The symbol of element `z`; "Z=\(z)" outside 1...118, never an index out of range.
    public static func symbol(z: Int) -> String { symbols.indices.contains(z - 1) ? symbols[z - 1] : "Z=\(z)" }

    /// The English name of element `z`; "element \(z)" outside 1...118.
    public static func name(z: Int) -> String { names.indices.contains(z - 1) ? names[z - 1] : "element \(z)" }

    /// The covalent radius of element `z` in Å.
    public static func covalentRadius(z: Int) -> Double {
        covalentRadii.indices.contains(z - 1) ? covalentRadii[z - 1] : fallbackRadius
    }

    /// The ball's radius in Å for ball and stick: a compressed covalent radius, so hydrogen stays visible and caesium does not hide
    /// its neighbours (Si 0.63 Å, O 0.52 Å, H 0.43 Å, Cs 0.96 Å).
    public static func ballRadius(z: Int) -> Double { 0.35 + 0.25 * covalentRadius(z: z) }
}
