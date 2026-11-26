package org.gamow.core

import kotlin.math.pow

/** Physical constants; energies in keV. Same values as NucPhysKit (Swift). */
object PhysicalConstants {
    /** Atomic mass unit, keV/c² (CODATA 2018, as used by AME2020). */
    const val ATOMIC_MASS_UNIT = 931_494.102_42
    /** Electron mass, keV/c² (CODATA 2018). */
    const val ELECTRON_MASS = 510.998_950_00
    const val SPEED_OF_LIGHT = 299_792_458.0
    /** ħc, keV·fm. */
    const val HBAR_C = 197_326.980_4
    const val FINE_STRUCTURE = 7.297_352_569_3e-3
    /** e²/(4πε₀) = αħc, keV fm. */
    const val COULOMB_CONSTANT = FINE_STRUCTURE * HBAR_C

    /** Total electron binding energy of a neutral atom, keV (Lunney, Pearson & Thibault 2003, Eq. A4). */
    fun electronBindingEnergy(z: Int): Double {
        if (z <= 0) return 0.0
        val zd = z.toDouble()
        return (14.4381 * zd.pow(2.39) + 1.55468e-6 * zd.pow(5.35)) / 1000.0
    }
}

/** Element symbols and names indexed by Z (index 0 is the neutron). */
object Elements {
    val symbols = listOf(
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
    )

    val names = listOf(
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
    )

    fun symbol(z: Int): String? = symbols.getOrNull(z)
    fun name(z: Int): String? = names.getOrNull(z)

    /** "C", "c", "He", "he" → Z. Exact case wins; case-insensitive matching never returns the neutron. */
    fun z(symbol: String): Int? {
        val exact = symbols.indexOf(symbol)
        if (exact >= 0) return exact
        val s = symbol.lowercase()
        return (1 until symbols.size).firstOrNull { symbols[it].lowercase() == s }
    }
}

object Superscript {
    private val map = mapOf(
        '0' to '⁰', '1' to '¹', '2' to '²', '3' to '³', '4' to '⁴',
        '5' to '⁵', '6' to '⁶', '7' to '⁷', '8' to '⁸', '9' to '⁹', '-' to '⁻', '+' to '⁺',
    )
    fun digits(value: Int): String = value.toString().map { map[it] ?: it }.joinToString("")
    fun string(s: String): String = s.map { map[it] ?: it }.joinToString("")
}
