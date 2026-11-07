import Foundation

/// Physical constants used throughout NucPhysKit. Energies are in keV.
public enum PhysicalConstants {
    /// Atomic mass unit, keV/c² (CODATA 2018, as used by AME2020).
    public static let atomicMassUnit = 931_494.102_42
    /// Electron mass, keV/c² (CODATA 2018).
    public static let electronMass = 510.998_950_00
    /// Speed of light, m/s.
    public static let speedOfLight = 299_792_458.0
    /// ħc, keV·fm.
    public static let hbarC = 197_326.980_4
    /// Fine-structure constant.
    public static let fineStructure = 7.297_352_569_3e-3

    /// Total electron binding energy of a neutral atom, keV.
    /// Lunney, Pearson & Thibault, Rev. Mod. Phys. 75 (2003) 1021, Eq. (A4).
    public static func electronBindingEnergy(z: Int) -> Double {
        guard z > 0 else { return 0 }
        let zd = Double(z)
        return (14.4381 * pow(zd, 2.39) + 1.55468e-6 * pow(zd, 5.35)) / 1000.0
    }
}

/// Element symbols and names indexed by Z (index 0 is the neutron).
public enum Elements {
    public static let symbols: [String] = [
        "n", "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne",
        "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca",
        "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn",
        "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr",
        "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn",
        "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd",
        "Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb",
        "Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg",
        "Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th",
        "Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf", "Es", "Fm",
        "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds",
        "Rg", "Cn", "Nh", "Fl", "Mc", "Lv", "Ts", "Og",
    ]

    public static let names: [String] = [
        "Neutron", "Hydrogen", "Helium", "Lithium", "Beryllium", "Boron", "Carbon", "Nitrogen", "Oxygen", "Fluorine", "Neon",
        "Sodium", "Magnesium", "Aluminium", "Silicon", "Phosphorus", "Sulfur", "Chlorine", "Argon", "Potassium", "Calcium",
        "Scandium", "Titanium", "Vanadium", "Chromium", "Manganese", "Iron", "Cobalt", "Nickel", "Copper", "Zinc",
        "Gallium", "Germanium", "Arsenic", "Selenium", "Bromine", "Krypton", "Rubidium", "Strontium", "Yttrium", "Zirconium",
        "Niobium", "Molybdenum", "Technetium", "Ruthenium", "Rhodium", "Palladium", "Silver", "Cadmium", "Indium", "Tin",
        "Antimony", "Tellurium", "Iodine", "Xenon", "Caesium", "Barium", "Lanthanum", "Cerium", "Praseodymium", "Neodymium",
        "Promethium", "Samarium", "Europium", "Gadolinium", "Terbium", "Dysprosium", "Holmium", "Erbium", "Thulium", "Ytterbium",
        "Lutetium", "Hafnium", "Tantalum", "Tungsten", "Rhenium", "Osmium", "Iridium", "Platinum", "Gold", "Mercury",
        "Thallium", "Lead", "Bismuth", "Polonium", "Astatine", "Radon", "Francium", "Radium", "Actinium", "Thorium",
        "Protactinium", "Uranium", "Neptunium", "Plutonium", "Americium", "Curium", "Berkelium", "Californium", "Einsteinium", "Fermium",
        "Mendelevium", "Nobelium", "Lawrencium", "Rutherfordium", "Dubnium", "Seaborgium", "Bohrium", "Hassium", "Meitnerium", "Darmstadtium",
        "Roentgenium", "Copernicium", "Nihonium", "Flerovium", "Moscovium", "Livermorium", "Tennessine", "Oganesson",
    ]

    public static func symbol(z: Int) -> String? {
        symbols.indices.contains(z) ? symbols[z] : nil
    }

    public static func name(z: Int) -> String? {
        names.indices.contains(z) ? names[z] : nil
    }

    /// Element symbol lookup ("C", "c", "He", "he" → Z). Exact case wins, so "N" is nitrogen
    /// and "n" the neutron; case-insensitive matching never returns the neutron.
    public static func z(forSymbol symbol: String) -> Int? {
        if let exact = symbols.firstIndex(of: symbol) { return exact }
        let s = symbol.lowercased()
        return symbols.indices.dropFirst().first { symbols[$0].lowercased() == s }
    }
}
