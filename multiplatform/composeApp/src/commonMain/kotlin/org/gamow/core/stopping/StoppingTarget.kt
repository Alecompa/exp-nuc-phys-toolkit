package org.gamow.core.stopping

import org.gamow.core.Elements
import org.gamow.core.Nuclide
import org.gamow.core.PhysicalConstants
import org.gamow.core.formatFixed
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.sqrt
import kotlin.math.truncate

/** The projectile for a stopping calculation. Mass in u. */
data class StoppingIon(val z: Int, val mass: Double) {
    /** SRIM's default: the most abundant isotope. */
    constructor(z: Int, data: SRIMData = SRIMData.shared) : this(z, data.element(z).isotopeMass)

    /** The ion of a specific nuclide, with its AME2020 atomic mass. */
    constructor(nuclide: Nuclide) : this(nuclide.z, nuclide.atomicMass / PhysicalConstants.ATOMIC_MASS_UNIT)
}

/** A homogeneous target layer: elements with stoichiometries, a density (g/cm³) and a phase. */
class StoppingTarget(
    val name: String,
    components: List<Component>,
    /** g/cm³ */
    val density: Double,
    val isGas: Boolean = false,
    /** Bragg-rule (compound) correction factor; 1 = none. */
    val compoundCorrection: Double = 1.0,
) {
    data class Component(
        val z: Int,
        val stoichiometry: Double,
        /** Mass in u (SRIM default: natural atomic weight). */
        val mass: Double,
        /** Explicit isotope from a formula; null means a natural-element component. */
        val massNumber: Int? = null,
    ) {
        /** Recover isotope tags from older saved targets when their mass differs clearly from natural mass. */
        val isotopeMassNumber: Int?
            get() = massNumber
                ?: if (abs(mass - SRIMData.shared.element(z).naturalMass) > 0.5) roundHalfAway(mass).toInt() else null
    }

    val components: List<Component> = components.filter { it.stoichiometry > 0 }

    fun copy(
        name: String = this.name, components: List<Component> = this.components, density: Double = this.density,
        isGas: Boolean = this.isGas, compoundCorrection: Double = this.compoundCorrection,
    ) = StoppingTarget(name, components, density, isGas, compoundCorrection)

    override fun equals(other: Any?): Boolean = other is StoppingTarget && name == other.name &&
        components == other.components && density == other.density && isGas == other.isGas &&
        compoundCorrection == other.compoundCorrection

    override fun hashCode(): Int =
        listOf(name, components, density, isGas, compoundCorrection).hashCode()

    override fun toString() = "StoppingTarget($name, $components, ρ=$density, gas=$isGas, corr=$compoundCorrection)"

    /** Atom fractions (stoichiometries normalised to 1). */
    val fractions: List<Double>
        get() {
            val total = components.fold(0.0) { s, c -> s + c.stoichiometry }
            return components.map { it.stoichiometry / total }
        }

    val meanMass: Double get() = components.zip(fractions).fold(0.0) { s, p -> s + p.first.mass * p.second }
    val meanZ: Double get() = components.zip(fractions).fold(0.0) { s, p -> s + p.first.z.toDouble() * p.second }

    /** Explicit isotopes contribute only to their own channel; abundance applies to untagged components. */
    fun activeFraction(z: Int, a: Int, abundance: Double): Double {
        if (!abundance.isFinite() || abundance !in 0.0..1.0) return 0.0
        return components.zip(fractions).fold(0.0) { sum, (component, fraction) ->
            if (component.z != z) sum
            else {
                val isotope = component.isotopeMassNumber
                if (isotope != null) sum + (if (isotope == a) fraction else 0.0) else sum + fraction * abundance
            }
        }
    }

    /** Active nuclei/cm² along the beam path through the complete homogeneous layer (thickness Å, angle °). */
    fun activeArealDensity(z: Int, a: Int, abundance: Double, thickness: Double, angle: Double): Double? {
        if (!(thickness.isFinite() && thickness >= 0 && angle.isFinite() && abs(angle) < 90 &&
                density.isFinite() && density > 0)) return null
        return thickness * 1e-8 * atomDensity * activeFraction(z, a, abundance) / cos(angle * PI / 180)
    }

    /** Atomic density, atoms/cm³ (SRIM's Avogadro constant 6.022·10²³). */
    val atomDensity: Double get() = 6.022e23 * density / meanMass
    /** Atomic density, atoms/Å³. */
    val atomsPerA3: Double get() = 0.6022 * density / meanMass

    /** "Si", or "C 50.0% · H 50.0%". */
    val compositionLabel: String
        get() {
            if (components.size == 1) return Elements.symbol(components[0].z) ?: "?"
            return components.zip(fractions).joinToString(" · ") { (c, f) ->
                "${Elements.symbol(c.z) ?: "?"} ${formatSignificantDigits(f * 100, 3, 3)}%"
            }
        }

    /** Stoichiometries for display: atom fractions become the smallest integer ratio with counts up to 100. */
    internal val displayStoichiometries: List<Double>
        get() {
            val s = components.map { it.stoichiometry }
            val total = s.fold(0.0) { a, b -> a + b }
            val lo = s.minOrNull()
            if (!(abs(total - 1) < 1e-6) || lo == null || !(lo > 0)) return s
            for (k in 1..20) {
                val r = s.map { it / lo * k.toDouble() }
                if (r.all { abs(it - roundHalfAway(it)) < 2e-3 * maxOf(1.0, it) } && r.max() <= 100) {
                    return r.map { roundHalfAway(it) }
                }
            }
            return s
        }

    /** The composition written as a formula ("Ta₂N₃", "TiD₂", "Ta₂¹⁷O₅"), preserving isotope tags. */
    fun formulaLabel(): String = components.zip(displayStoichiometries).joinToString("") { (c, n) ->
        ChemicalFormula.symbol(c.z, c.isotopeMassNumber) + ChemicalFormula.subscriptCount(n)
    }

    /** The composition as plain text that [ChemicalFormula.parse] reads back ("Ta2N3", "TiD2", "[17O]"). */
    fun formulaText(): String = components.zip(displayStoichiometries).joinToString("") { (c, n) ->
        val sym = Elements.symbol(c.z) ?: "?"
        val a = c.isotopeMassNumber
        var s = if (a == null) sym else if (c.z == 1 && a == 2) "D" else if (c.z == 1 && a == 3) "T" else "[$a$sym]"
        if (abs(n - 1) > 1e-9) s += formatSignificantDigits(n, 1, 6)
        s
    }

    companion object {
        /** A pure element at SRIM's default density (solid, or the gas at STP). */
        fun element(z: Int, gas: Boolean? = null, data: SRIMData = SRIMData.shared): StoppingTarget {
            val e = data.element(z)
            val isGas = gas ?: (z in SRIMStopping.gasElements)
            return StoppingTarget(Elements.name(z) ?: e.symbol, listOf(Component(z, 1.0, e.naturalMass)),
                if (isGas) e.gasDensity else e.density, isGas)
        }

        /** A material from SRIM's compound dictionary. */
        fun compound(c: SRIMCompound, data: SRIMData = SRIMData.shared): StoppingTarget =
            StoppingTarget(c.displayName,
                c.elements.map { val z = it[0].toInt(); Component(z, it[1], data.element(z).naturalMass) },
                c.density, c.gas)

        /** A target from a chemical formula: isotopic entries use their AME2020 atomic mass, natural elements SRIM's weight. */
        fun formula(f: ChemicalFormula, density: Double, gas: Boolean = false, data: SRIMData = SRIMData.shared): StoppingTarget =
            StoppingTarget(f.label, f.parts.map { p ->
                val mass = p.massNumber?.let { org.gamow.core.MassTable.ame2020.nuclide(p.z, it) }
                    ?.let { it.atomicMass / PhysicalConstants.ATOMIC_MASS_UNIT } ?: data.element(p.z).naturalMass
                Component(p.z, p.count, mass, p.massNumber)
            }, density, gas)
    }
}

/** SRIM's eight stopping units. */
enum class StoppingUnit(val code: Int, val label: String) {
    EV_PER_ANGSTROM(1, "eV/Å"),
    KEV_PER_MICRON(2, "keV/µm"),
    MEV_PER_MILLIMETRE(3, "MeV/mm"),
    KEV_PER_MICROGRAM_CM2(4, "keV/(µg/cm²)"),
    MEV_PER_MILLIGRAM_CM2(5, "MeV/(mg/cm²)"),
    KEV_PER_MILLIGRAM_CM2(6, "keV/(mg/cm²)"),
    EV_PER_1E15_ATOMS_CM2(7, "eV/(10¹⁵ at/cm²)"),
    REDUCED(8, "LSS reduced");

    /** Multiplies a stopping cross section in eV/(10¹⁵ atoms/cm²) to give this unit (SRIM's factors). */
    fun factor(ion: StoppingIon, target: StoppingTarget): Double {
        val n = target.atomDensity
        val m = target.meanMass
        return when (this) {
            EV_PER_ANGSTROM -> 1e-23 * n
            KEV_PER_MICRON, MEV_PER_MILLIMETRE -> 1e-22 * n
            KEV_PER_MICROGRAM_CM2, MEV_PER_MILLIGRAM_CM2 -> 0.60222 / m
            KEV_PER_MILLIGRAM_CM2 -> 602.22 / m
            EV_PER_1E15_ATOMS_CM2 -> 1.0
            REDUCED -> {
                val z1 = ion.z.toDouble()
                val mz = target.meanZ
                val m1 = ion.mass
                (m1 + m) * sqrt(z1.pow(0.6667) + mz.pow(0.6667)) / (8.462 * mz * z1 * m1)
            }
        }
    }
}

/** Units for a layer thickness. */
enum class ThicknessUnit(val symbol: String) {
    ANGSTROM("Å"), NANOMETRE("nm"), MICROMETRE("µm"), MILLIMETRE("mm"),
    MICROGRAM_CM2("µg/cm²"), MILLIGRAM_CM2("mg/cm²"), ATOMS_1E15("10¹⁵ at/cm²");

    /** Thickness in Å for a value in this unit. */
    fun toAngstrom(value: Double, target: StoppingTarget): Double = when (this) {
        ANGSTROM -> value
        NANOMETRE -> value * 10
        MICROMETRE -> value * 1e4
        MILLIMETRE -> value * 1e7
        MICROGRAM_CM2 -> value * 1e-6 / target.density * 1e8
        MILLIGRAM_CM2 -> value * 1e-3 / target.density * 1e8
        ATOMS_1E15 -> value * 1e15 / (target.atomsPerA3 * 1e16)
    }

    fun fromAngstrom(a: Double, target: StoppingTarget): Double = a / toAngstrom(1.0, target)
}

/** Swift's `rounded()`: to nearest, ties away from zero. */
internal fun roundHalfAway(x: Double): Double {
    val t = truncate(x)
    return if (abs(x - t) == 0.5) t + (if (x > 0) 1.0 else -1.0) else round(x)
}

/**
 * Number with between `minDigits` and `maxDigits` significant digits, trailing zeros removed down to `minDigits`,
 * "." as decimal separator and no grouping (Swift's `.precision(.significantDigits(min...max))` in en_US_POSIX).
 */
internal fun formatSignificantDigits(x: Double, minDigits: Int, maxDigits: Int): String {
    if (x == 0.0) return if (minDigits > 1) "0." + "0".repeat(minDigits - 1) else "0"
    if (!x.isFinite()) return x.toString()
    val mag = floor(log10(abs(x))).toInt()
    val decimals = maxDigits - 1 - mag
    var s = if (decimals >= 0) formatFixed(x, decimals)
    else formatFixed(round(x / 10.0.pow(-decimals)) * 10.0.pow(-decimals), 0)
    if ('.' in s) {
        fun sig(t: String) = t.filter { it.isDigit() }.trimStart('0').length
        while (s.endsWith('0') && sig(s) > minDigits) s = s.dropLast(1)
        if (s.endsWith('.')) s = s.dropLast(1)
    }
    return s
}
