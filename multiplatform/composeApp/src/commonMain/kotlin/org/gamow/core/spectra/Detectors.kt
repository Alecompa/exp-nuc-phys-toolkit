package org.gamow.core.spectra

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** Energy resolution (FWHM) of a γ-ray detector. Port of NucPhysKit.ResolutionModel. */
data class ResolutionModel(
    val kind: Kind,
    /** Electronic noise FWHM, keV. */
    val noise: Double = 0.9,
    /** Fano factor. */
    val fano: Double = 0.11,
    /** Energy per electron–hole pair, keV (2.96 eV for Ge). */
    val pairEnergy: Double = 2.96e-3,
    /** Charge-collection term (dimensionless, FWHM fraction of E). */
    val collection: Double = 5e-4,
    /** Scintillator: relative FWHM at 662 keV (0.07 = 7 %). */
    val resolutionAt662: Double = 0.07,
) {
    enum class Kind {
        /** FWHM² = a² + (2.355)² F w E + (c E)²: electronic noise, Fano statistics, charge collection. */
        SEMICONDUCTOR,
        /** FWHM ∝ √E, given by the relative resolution at 662 keV. */
        SCINTILLATOR,
    }

    /** FWHM at `e` keV, keV. */
    fun fwhm(e: Double): Double = when (kind) {
        Kind.SEMICONDUCTOR -> {
            val stat = 2.355 * 2.355 * fano * pairEnergy * e
            sqrt(noise * noise + stat + (collection * e).pow(2))
        }
        Kind.SCINTILLATOR -> resolutionAt662 * 662 * sqrt(max(e, 0.0) / 662)
    }

    data class Preset(val name: String, val model: ResolutionModel) {
        val id: String get() = name
    }

    companion object {
        val presets: List<Preset> = listOf(
            Preset("HPGe coaxial (1.9 keV at 1.33 MeV)", ResolutionModel(Kind.SEMICONDUCTOR, noise = 0.9, collection = 5e-4)),
            Preset("HPGe large / clover", ResolutionModel(Kind.SEMICONDUCTOR, noise = 1.1, collection = 7e-4)),
            Preset("Planar HPGe / LEGe", ResolutionModel(Kind.SEMICONDUCTOR, noise = 0.45, collection = 3e-4)),
            Preset("NaI(Tl), 7 % at 662 keV", ResolutionModel(Kind.SCINTILLATOR, resolutionAt662 = 0.07)),
            Preset("LaBr₃(Ce), 2.8 % at 662 keV", ResolutionModel(Kind.SCINTILLATOR, resolutionAt662 = 0.028)),
            Preset("BGO, 10 % at 662 keV", ResolutionModel(Kind.SCINTILLATOR, resolutionAt662 = 0.10)),
        )
    }
}

/** Full-energy-peak efficiency curve ln ε = Σᵢ aᵢ (ln(E/E₀))ⁱ fitted by weighted least squares. */
data class EfficiencyCurve(val points: List<Point>, /** Polynomial order in ln E (1–4). */ val order: Int = 3) {
    data class Point(
        /** keV */
        val energy: Double,
        /** Absolute full-energy-peak efficiency (0–1). */
        val efficiency: Double,
        /** Relative uncertainty (0.02 = 2 %). */
        val relativeUncertainty: Double = 0.02,
        val id: String = SpecMath.newId(),
    )

    data class Fit(val coefficients: List<Double>, val chiSquared: Double, val degreesOfFreedom: Int) {
        fun efficiency(e: Double): Double {
            val x = ln(e / REFERENCE_ENERGY)
            var s = 0.0
            coefficients.forEachIndexed { i, c -> s += c * x.pow(i.toDouble()) }
            return exp(s)
        }
        val reducedChiSquared: Double? get() = if (degreesOfFreedom > 0) chiSquared / degreesOfFreedom else null
    }

    /** Weighted fit in ln ε; null with fewer points than parameters. */
    fun fit(): Fit? {
        val pts = points.filter { it.energy > 0 && it.efficiency > 0 }
        val m = min(max(order, 1), 4) + 1
        if (pts.size < m) return null
        val ata = Array(m) { DoubleArray(m) }
        val atb = DoubleArray(m)
        for (p in pts) {
            val x = ln(p.energy / REFERENCE_ENERGY)
            val y = ln(p.efficiency)
            val w = 1 / max(p.relativeUncertainty, 1e-4).pow(2)
            val row = DoubleArray(m) { x.pow(it.toDouble()) }
            for (i in 0 until m) {
                atb[i] += w * row[i] * y
                for (j in 0 until m) ata[i][j] += w * row[i] * row[j]
            }
        }
        val c = solve(ata.map { it.toList() }, atb.toList()) ?: return null
        val fit = Fit(c, 0.0, 0)
        var chi = 0.0
        for (p in pts) {
            chi += (ln(p.efficiency) - ln(fit.efficiency(p.energy))).pow(2) / max(p.relativeUncertainty, 1e-4).pow(2)
        }
        return Fit(c, chi, pts.size - m)
    }

    companion object {
        const val REFERENCE_ENERGY = 1000.0

        /** Gaussian elimination with partial pivoting. */
        fun solve(a0: List<List<Double>>, b0: List<Double>): List<Double>? {
            val a = a0.map { it.toDoubleArray() }.toTypedArray()
            val b = b0.toDoubleArray()
            val n = b.size
            for (col in 0 until n) {
                var piv = col
                for (r in col + 1 until n) if (abs(a[piv][col]) < abs(a[r][col])) piv = r
                if (!(abs(a[piv][col]) > 1e-300)) return null
                val t = a[col]; a[col] = a[piv]; a[piv] = t
                val tb = b[col]; b[col] = b[piv]; b[piv] = tb
                for (r in col + 1 until n) {
                    val f = a[r][col] / a[col][col]
                    for (k in col until n) a[r][k] -= f * a[col][k]
                    b[r] -= f * b[col]
                }
            }
            val x = DoubleArray(n)
            for (i in n - 1 downTo 0) {
                var s = 0.0
                for (j in i + 1 until n) s += a[i][j] * x[j]
                x[i] = (b[i] - s) / a[i][i]
            }
            return x.toList()
        }

        /** A typical 100 % relative-efficiency coaxial HPGe with a point source at 10 cm (order-of-magnitude example). */
        val example = EfficiencyCurve(listOf(
            Point(122.0, 0.0245), Point(344.0, 0.0142), Point(662.0, 0.0086), Point(1173.0, 0.0057),
            Point(1332.0, 0.0052), Point(1408.0, 0.0050), Point(2615.0, 0.0031), Point(6129.0, 0.0016),
        ), order = 3)
    }
}

object Geometry {
    /** Solid angle (sr) of a disk of radius `r` seen on axis from `d` (same units). */
    fun diskSolidAngle(r: Double, d: Double): Double = 2 * PI * (1 - d / sqrt(d * d + r * r))

    /** Half-opening angle (rad) of a disk of radius r at distance d. */
    fun halfOpeningAngle(r: Double, d: Double): Double = atan2(r, d)
}

/** Doppler shift of γ rays emitted in flight. */
object GammaDoppler {
    /** E = E₀ √(1 − β²) / (1 − β cos θ), θ between the emitter's velocity and the photon (lab). */
    fun energy(e0: Double, beta: Double, angle: Double): Double = e0 * sqrt(1 - beta * beta) / (1 - beta * cos(angle))

    /** Energies seen by a detector at `angle` with half-opening `halfOpening` (rad): min…max. */
    fun range(e0: Double, beta: Double, angle: Double, halfOpening: Double): ClosedFloatingPointRange<Double> {
        val lo = max(0.0, angle - halfOpening)
        val hi = min(PI, angle + halfOpening)
        val e1 = energy(e0, beta, lo)
        val e2 = energy(e0, beta, hi)
        return min(e1, e2)..max(e1, e2)
    }

    /** Mean energy over a uniformly illuminated circular detector face (numerical average over the cone). */
    fun meanOverCone(e0: Double, beta: Double, angle: Double, halfOpening: Double, samples: Int = 60): Double {
        if (!(halfOpening > 0)) return energy(e0, beta, angle)
        var sum = 0.0
        var wsum = 0.0
        val axisZ = cos(angle)
        val uZ = -sin(angle)
        val vZ = 0.0
        for (i in 0 until samples) {
            val alpha = halfOpening * (i + 0.5) / samples
            for (k in 0 until 36) {
                val phi = 2 * PI * k / 36
                val dz = cos(alpha) * axisZ + sin(alpha) * (cos(phi) * uZ + sin(phi) * vZ)
                val w = sin(alpha)
                sum += w * energy(e0, beta, acos(max(-1.0, min(1.0, dz))))
                wsum += w
            }
        }
        return sum / wsum
    }

    /** Recoil-corrected γ energy: E_γ ≈ E − E²/(2Mc²). */
    fun recoilCorrected(transition: Double, mass: Double): Double = transition - transition * transition / (2 * mass)
}
