package org.gamow.core.astro

import org.gamow.core.*
import kotlin.math.*
import kotlin.random.Random

/** CGS constants for reaction rates. Port of NucPhysKit `CGS`. */
internal object CGS {
    const val AVOGADRO = 6.022_140_76e23
    /** erg per keV */
    const val ERG = 1.602_176_634e-9
    const val ATOMIC_MASS_GRAM = 1.660_539_066_60e-24
    /** erg s */
    const val HBAR = 1.054_571_817e-27
    /** cm² */
    const val BARN = 1e-24
}

// S factor

/**
 * Astrophysical S factor S(E) = σ(E) E exp(2πη), keV b, as a function of the centre-of-mass energy (keV).
 * The table is kept sorted by energy. Port of NucPhysKit.SFactorModel.
 */
class SFactorModel(
    val kind: Kind = Kind.POLYNOMIAL,
    /** S(0), keV b */
    val s0: Double = 1.0,
    /** S'(0), b */
    val s1: Double = 0.0,
    /** S''(0), b/keV; S = s0 + s1 E + s2 E²/2 */
    val s2: Double = 0.0,
    table: List<Point> = emptyList(),
) {
    enum class Kind { POLYNOMIAL, TABLE }

    /** keV (c.m.), keV b */
    data class Point(val energy: Double, val s: Double)

    /** Sorted by energy. */
    val table: List<Point> = table.sortedBy { it.energy }

    fun copy(kind: Kind = this.kind, s0: Double = this.s0, s1: Double = this.s1, s2: Double = this.s2,
             table: List<Point> = this.table) = SFactorModel(kind, s0, s1, s2, table)

    override fun equals(other: Any?): Boolean =
        other is SFactorModel && kind == other.kind && s0 == other.s0 && s1 == other.s1 && s2 == other.s2 && table == other.table

    override fun hashCode(): Int = listOf(kind, s0, s1, s2, table).hashCode()
    override fun toString() = "SFactorModel($kind, s0=$s0, s1=$s1, s2=$s2, table=$table)"

    /**
     * S(E), keV b. Tables interpolate linearly in ln S (linearly where S ≤ 0) and are held constant beyond
     * their ends.
     */
    fun s(at: Double): Double {
        val e = at
        return when (kind) {
            Kind.POLYNOMIAL -> max(0.0, s0 + s1 * e + 0.5 * s2 * e * e)
            Kind.TABLE -> {
                if (table.isEmpty()) return 0.0
                val first = table.first(); val last = table.last()
                if (e <= first.energy) return first.s
                if (e >= last.energy) return last.s
                var lo = 0; var hi = table.size - 1
                while (hi - lo > 1) {
                    val mid = (lo + hi) / 2
                    if (table[mid].energy <= e) lo = mid else hi = mid
                }
                val a = table[lo]; val b = table[hi]
                val t = (e - a.energy) / (b.energy - a.energy)
                if (a.s > 0 && b.s > 0) exp(ln(a.s) + t * (ln(b.s) - ln(a.s))) else a.s + t * (b.s - a.s)
            }
        }
    }

    /** Energy range the model is defined on without extrapolation (null for a polynomial). */
    val tableRange: ClosedFloatingPointRange<Double>?
        get() = if (kind != Kind.TABLE || table.isEmpty()) null else table.first().energy..table.last().energy

    /** Two-column text of the table (keV, keV b), "%.6g" like C. */
    val tableText: String
        get() = table.joinToString("\n") { "${formatG6(it.energy)}, ${formatG6(it.s)}" }

    companion object {
        private val newline = Regex("[\n\r\u000B\u000C\u0085  ]")

        /**
         * Parses "E S" rows (keV, keV b): separators comma, semicolon, tab or spaces; '#' starts a comment;
         * a non-numeric first line is taken as a header. Throws [SFactorParseException].
         */
        fun parseTable(text: String): List<Point> {
            val points = mutableListOf<Point>()
            text.split(newline).filter { it.isNotEmpty() }.forEachIndexed { i, raw ->
                val line = raw.substringBefore('#')
                val fields = line.split(',', ';', '\t', ' ').filter { it.isNotEmpty() }
                if (fields.isEmpty()) return@forEachIndexed
                val e = if (fields.size >= 2) swiftDouble(fields[0]) else null
                val s = if (fields.size >= 2) swiftDouble(fields[1]) else null
                if (e == null || s == null) {
                    if (points.isEmpty() && i == 0) return@forEachIndexed     // header
                    throw SFactorParseException.BadLine(i + 1)
                }
                points.add(Point(e, s))
            }
            if (points.size < 2) throw SFactorParseException.TooFewPoints(points.size)
            return points.sortedBy { it.energy }
        }

        fun parseTableOrNull(text: String): List<Point>? = try { parseTable(text) } catch (_: SFactorParseException) { null }
    }
}

sealed class SFactorParseException(override val message: String) : Exception(message) {
    class TooFewPoints(val count: Int) : SFactorParseException("Need at least 2 points (found $count).")
    class BadLine(val line: Int) : SFactorParseException("Line $line is not two numbers.")
}

private val decimalNumber = Regex("[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?")
private val specialNumber = Regex("[+-]?(inf|infinity|nan)", RegexOption.IGNORE_CASE)

/** Swift's `Double(String)`: a decimal number, inf or nan, nothing else (no Java "1d" suffixes or blanks). */
internal fun swiftDouble(s: String): Double? = when {
    decimalNumber.matches(s) -> s.toDouble()
    specialNumber.matches(s) -> {
        val neg = s.startsWith('-')
        if (s.trimStart('+', '-').lowercase() == "nan") Double.NaN
        else if (neg) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
    }
    else -> null
}

/** C's "%.6g": six significant digits, trailing zeros removed. */
internal fun formatG6(x: Double): String {
    if (x.isNaN()) return "nan"
    if (x.isInfinite()) return if (x > 0) "inf" else "-inf"
    val s = formatSignificant(x, 6)          // Java %g: same fixed/scientific switch as C, zeros kept
    val ePos = s.indexOfFirst { it == 'e' || it == 'E' }
    var mant = if (ePos >= 0) s.substring(0, ePos) else s
    val exp = if (ePos >= 0) s.substring(ePos).lowercase() else ""
    if ('.' in mant) mant = mant.trimEnd('0').trimEnd('.')
    return mant + exp
}

// Narrow resonances

/** A narrow resonance: energy (keV, centre of mass) and strength ωγ (eV). */
data class NarrowResonance(val energy: Double, val strength: Double, val id: Long = Random.nextLong()) {
    companion object {
        /** ω = (2J+1)/((2j₁+1)(2j₂+1)) (× (1+δ₁₂) for identical particles, not included). */
        fun spinFactor(j: Double, j1: Double, j2: Double): Double = (2 * j + 1) / ((2 * j1 + 1) * (2 * j2 + 1))

        /** ωγ = ω Γ_a Γ_b / Γ (any common width unit). */
        fun strength(omega: Double, gammaA: Double, gammaB: Double, total: Double): Double =
            if (total > 0) omega * gammaA * gammaB / total else 0.0
    }
}

/** λ²/2 with λ the centre-of-mass de Broglie wavelength h/p at `energy` keV, cm². */
fun ChargedChannel.deBroglieHalfSquared(energy: Double): Double {
    val lambdaFm = 2 * PI * PhysicalConstants.HBAR_C / sqrt(2 * reducedMassEnergy * energy)
    return (lambdaFm * 1e-13).pow(2) / 2
}

/**
 * Maximum thick-target yield (reactions per projectile) of a narrow resonance:
 * Y = (λ²/2) (m₁+m₂)/m₂ ωγ/ε_eff, ε_eff the laboratory stopping per active nucleus (eV cm²), ωγ in eV.
 */
fun ChargedChannel.thickTargetYield(resonanceEnergy: Double, strength: Double, effectiveStopping: Double): Double =
    deBroglieHalfSquared(resonanceEnergy) * (m1 + m2) / m2 * strength / effectiveStopping

/** ωγ (eV) from a measured maximum thick-target yield; inverse of [thickTargetYield]. */
fun ChargedChannel.resonanceStrength(resonanceEnergy: Double, yield: Double, effectiveStopping: Double): Double =
    yield * effectiveStopping / (deBroglieHalfSquared(resonanceEnergy) * (m1 + m2) / m2)

/** N_A⟨σv⟩ of a narrow resonance, cm³ mol⁻¹ s⁻¹: N_A (2π/(μkT))^{3/2} ħ² ωγ exp(−E_R/kT). */
fun ChargedChannel.narrowResonanceRate(r: NarrowResonance, t9: Double): Double {
    val kT = ChargedChannel.kT(t9) * CGS.ERG
    val mu = reducedMass * CGS.ATOMIC_MASS_GRAM
    val wg = r.strength * 1e-3 * CGS.ERG
    val arg = r.energy / ChargedChannel.kT(t9)
    if (!(arg < 700)) return 0.0
    return CGS.AVOGADRO * (2 * PI / (mu * kT)).pow(1.5) * CGS.HBAR * CGS.HBAR * wg * exp(-arg)
}

// Non-resonant rate

/**
 * N_A⟨σv⟩ (cm³ mol⁻¹ s⁻¹) from an S factor by numerical integration:
 * N_A √(8/(πμ)) (kT)^{−3/2} ∫ S(E) exp(−2πη − E/kT) dE, Simpson's rule in ln E.
 */
fun ChargedChannel.rate(sFactor: SFactorModel, t9: Double, points: Int = 2000): Double {
    val kT = ChargedChannel.kT(t9)
    val w = gamowWindow(t9)
    val lo = max(w.peak / 200, 1e-6)
    val hi = max(w.peak + 12 * w.width, w.peak + 60 * kT)
    val a = ln(lo); val b = ln(hi)
    val n = if (points % 2 == 0) points else points + 1
    val h = (b - a) / n
    val sqrtEG = sqrt(gamowEnergy)
    var sum = 0.0
    for (i in 0..n) {
        val e = exp(a + i * h)
        val x = -sqrtEG / sqrt(e) - e / kT
        val fx = if (x < -700) 0.0 else sFactor.s(e) * exp(x) * e      // dE = E d(ln E)
        val wgt = if (i == 0 || i == n) 1.0 else if (i % 2 == 1) 4.0 else 2.0
        sum += wgt * fx
    }
    val integral = sum * h / 3                                          // keV² b
    val mu = reducedMass * CGS.ATOMIC_MASS_GRAM
    val kTerg = kT * CGS.ERG
    return CGS.AVOGADRO * sqrt(8 / (PI * mu)) * kTerg.pow(-1.5) * integral * CGS.ERG * CGS.ERG * CGS.BARN
}

/** The standard temperature grid of rate tables (REACLIB/STARLIB-like), GK. */
val ChargedChannel.Companion.rateGrid: List<Double>
    get() = RATE_GRID

private val RATE_GRID = listOf(0.001, 0.002, 0.003, 0.004, 0.005, 0.006, 0.007, 0.008, 0.009,
    0.01, 0.011, 0.012, 0.013, 0.014, 0.015, 0.016, 0.018, 0.02, 0.025, 0.03, 0.04, 0.05, 0.06, 0.07,
    0.08, 0.09, 0.1, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16, 0.18, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5,
    0.6, 0.7, 0.8, 0.9, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0)

// Rutherford scattering

/** Elastic Coulomb (Rutherford) scattering of the projectile on the target, relativistic kinematics. */
class RutherfordScattering(projectile: Nuclide, target: Nuclide, beamEnergy: Double) {
    val z1: Int = projectile.z
    val z2: Int = target.z
    val kinematics = TwoBodyKinematics(projectile.kinematicMass, target.kinematicMass,
        projectile.kinematicMass, target.kinematicMass, beamEnergy)

    /** Cross sections in b/sr. */
    data class Point(val thetaCM: Double, val energy: Double, val crossSectionCM: Double, val crossSectionLab: Double)

    /** dσ/dΩ in the centre of mass, b/sr: (Z₁Z₂e²/(4E))² / sin⁴(θ/2). */
    fun crossSectionCM(thetaCM: Double): Double {
        val a = (z1 * z2).toDouble() * PhysicalConstants.COULOMB_CONSTANT / (4 * kinematics.centerOfMassEnergy)  // fm
        return a * a / sin(thetaCM / 2).pow(4) * 1e-2
    }

    /** The scattered projectile at laboratory angle `labAngle` (radians); two solutions when it is heavier than the target. */
    fun at(labAngle: Double): List<Point> =
        // Equal masses give a degenerate second branch at θ* = π with zero energy.
        kinematics.solutions(labAngle).filter { it.ejectileEnergy > 1e-6 * kinematics.beamEnergy }.map { s ->
            val cm = crossSectionCM(s.thetaCM)
            Point(s.thetaCM, s.ejectileEnergy, cm, cm * s.jacobian)
        }
}
