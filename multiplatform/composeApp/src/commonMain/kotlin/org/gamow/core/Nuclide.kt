package org.gamow.core

/** A ground-state nuclide with its AME2020 mass excess (keV). */
data class Nuclide(
    val z: Int,
    val a: Int,
    /** Δ = M_atomic − A·u, keV. */
    val massExcess: Double,
    val massExcessUncertainty: Double,
    /** AME flags the value as estimated from systematics ('#'). */
    val isEstimated: Boolean = false,
) {
    val id: Int get() = z * 1000 + a
    val n: Int get() = a - z
    val symbol: String get() = Elements.symbol(z) ?: "?"
    val elementName: String get() = Elements.name(z) ?: "Unknown"

    /** Neutral-atom mass, keV/c². */
    val atomicMass: Double get() = a * PhysicalConstants.ATOMIC_MASS_UNIT + massExcess

    /** Ion mass used for kinematics: atomic mass − Z mₑ (electron binding left out, so kinematic Q = AME Q). */
    val kinematicMass: Double get() = atomicMass - z * PhysicalConstants.ELECTRON_MASS

    /** Total binding energy, keV. */
    val bindingEnergy: Double get() = z * 7288.971064 + n * 8071.31806 - massExcess
    val bindingEnergyPerNucleon: Double get() = if (a > 0) bindingEnergy / a else 0.0

    /** "13N", "n" */
    val plainLabel: String get() = if (z == 0 && a == 1) "n" else "$a$symbol"
    /** "¹³N" */
    val label: String get() = if (z == 0 && a == 1) "n" else "${Superscript.digits(a)}$symbol"

    /** p, d, t, α for light ions inside reaction notation. */
    val reactionLabel: String
        get() = when (z to a) {
            0 to 1 -> "n"; 1 to 1 -> "p"; 1 to 2 -> "d"; 1 to 3 -> "t"; 2 to 4 -> "α"
            else -> label
        }

    /** p d t a n for plain notation. */
    val plainLight: String
        get() = when (z to a) {
            0 to 1 -> "n"; 1 to 1 -> "p"; 1 to 2 -> "d"; 1 to 3 -> "t"; 2 to 4 -> "a"
            else -> plainLabel
        }
}

/** Parses nuclide names: "12C", "C12", "c-12", "¹²C", "p", "α", "alpha", "proton". */
object NuclideNotation {
    /** Case-sensitive: "H", "N", "P", "A" alone are incomplete element names, never ³He, n, p, α. */
    private val letters = mapOf("n" to (0 to 1), "p" to (1 to 1), "d" to (1 to 2), "t" to (1 to 3),
        "a" to (2 to 4), "h" to (2 to 3), "α" to (2 to 4))
    private val words = mapOf("alpha" to (2 to 4), "proton" to (1 to 1), "neutron" to (0 to 1),
        "deuteron" to (1 to 2), "triton" to (1 to 3), "helion" to (2 to 3))
    private val superscripts = mapOf('⁰' to '0', '¹' to '1', '²' to '2', '³' to '3', '⁴' to '4',
        '⁵' to '5', '⁶' to '6', '⁷' to '7', '⁸' to '8', '⁹' to '9')

    fun parse(raw: String): Pair<Int, Int>? {
        val s = raw.trim().replace("-", "").replace(" ", "").map { superscripts[it] ?: it }.joinToString("")
        if (s.isEmpty()) return null
        (letters[s] ?: words[s.lowercase()])?.let { return it }
        val leadingDigits = s.takeWhile { it.isDigit() }
        if (leadingDigits.isNotEmpty()) {
            val sym = s.drop(leadingDigits.length)
            val a = leadingDigits.toIntOrNull() ?: return null
            val z = Elements.z(sym) ?: return null
            return if (a >= maxOf(z, 1)) z to a else null
        }
        val lettersPart = s.takeWhile { it.isLetter() }
        val digits = s.drop(lettersPart.length)
        if (lettersPart.isEmpty() || digits.isEmpty() || !digits.all { it.isDigit() }) return null
        val a = digits.toIntOrNull() ?: return null
        val z = Elements.z(lettersPart) ?: return null
        return if (a >= maxOf(z, 1)) z to a else null
    }
}

/** AME2020 mass table, loaded from the bundled ame2020.csv (`Z,A,symbol,mass_excess_keV,unc_keV,estimated`). */
class MassTable(val name: String, val nuclides: List<Nuclide>) {
    private val index = nuclides.associateBy { it.id }

    fun nuclide(z: Int, a: Int): Nuclide? = index[z * 1000 + a]
    fun nuclide(named: String): Nuclide? = NuclideNotation.parse(named)?.let { nuclide(it.first, it.second) }
    fun isotopes(z: Int): List<Nuclide> = nuclides.filter { it.z == z }.sortedBy { it.a }

    companion object {
        fun parse(name: String, csv: String): MassTable {
            val list = ArrayList<Nuclide>(3600)
            for (line in csv.lineSequence().drop(1)) {
                val f = line.split(',')
                if (f.size < 6) continue
                val z = f[0].toIntOrNull() ?: continue
                val a = f[1].toIntOrNull() ?: continue
                val dm = f[3].toDoubleOrNull() ?: continue
                val du = f[4].toDoubleOrNull() ?: continue
                list.add(Nuclide(z, a, dm, du, f[5].trim() == "1"))
            }
            return MassTable(name, list)
        }

        /** AME2020 (Wang et al., Chin. Phys. C 45, 030003, 2021). */
        val ame2020: MassTable by lazy { parse("AME2020", readResourceText("ame2020.csv")) }
    }
}
