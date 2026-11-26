package org.gamow.core

import kotlin.math.*

/** Radioactive decay arithmetic. Times in s, activities in Bq. Port of NucPhysKit.RadioactiveDecay. */
object RadioactiveDecay {
    const val AVOGADRO = 6.022_140_76e23
    fun decayConstant(halfLife: Double): Double = if (halfLife == Double.POSITIVE_INFINITY) 0.0 else ln(2.0) / halfLife
    fun activity(initial: Double, elapsed: Double, halfLife: Double): Double = initial * exp(-decayConstant(halfLife) * elapsed)
    /** Relative uncertainty of A(t) from the half-life uncertainty: (ln2 · t / T½) · (σT/T½). */
    fun relativeActivityUncertainty(elapsed: Double, halfLife: Double, halfLifeUncertainty: Double): Double =
        abs(ln(2.0) * elapsed / halfLife * (halfLifeUncertainty / halfLife))
    fun atoms(activity: Double, halfLife: Double): Double = activity / decayConstant(halfLife)
    fun activityOfAtoms(atoms: Double, halfLife: Double): Double = atoms * decayConstant(halfLife)
    fun mass(atoms: Double, molarMass: Double): Double = atoms * molarMass / AVOGADRO
    fun atomsOfMass(grams: Double, molarMass: Double): Double = grams * AVOGADRO / molarMass
    fun timeToFraction(fraction: Double, halfLife: Double): Double = -ln(fraction) / decayConstant(halfLife)
}

/** A photon of a decay: energy keV, intensity % per decay. */
data class EmissionLine(val energy: Double, val intensity: Double, val intensityUncertainty: Double, val kind: String)

/** A calibration source: NUBASE state and photon emissions (ENSDF via the IAEA LiveChart). */
data class CalibrationSource(val state: NuclearState, val lines: List<EmissionLine>) {
    val id: String get() = state.plainLabel
    val label: String get() = state.label
    fun prominentLines(minIntensity: Double = 1.0): List<EmissionLine> =
        lines.filter { if (it.kind == "xray") it.intensity >= 5 else it.intensity >= minIntensity }
}

object CalibrationSources {
    val all: List<CalibrationSource> by lazy {
        @Suppress("UNCHECKED_CAST")
        val root = MiniJson.parse(readResourceText("calibration_sources.json")) as Map<String, Any?>
        (root["sources"] as List<Map<String, Any?>>).mapNotNull { e ->
            val state = Nubase.nubase2020.state(e["nuclide"] as String) ?: return@mapNotNull null
            val lines = (e["lines"] as List<Map<String, Any?>>).map {
                EmissionLine(it["e"] as Double, it["i"] as Double, (it["di"] as? Double) ?: 0.0, it["kind"] as String)
            }
            CalibrationSource(state, lines)
        }
    }
    fun source(named: String): CalibrationSource? = all.firstOrNull { it.id.equals(named, ignoreCase = true) }
}

/** A lab source with its certificate. Dates as epoch seconds (UTC). */
data class SourceCertificate(
    val id: String,
    val nuclide: String,
    val name: String = "",
    /** Bq at the reference date. */
    val activity: Double,
    /** Relative standard uncertainty (0.015 = 1.5 %). */
    val relativeUncertainty: Double = 0.015,
    val referenceDate: Double,
) {
    val state: NuclearState? get() = Nubase.nubase2020.state(nuclide)

    data class Now(val activity: Double, val relativeUncertainty: Double, val elapsed: Double)

    /** Activity at `date` with the certificate and half-life uncertainties in quadrature. */
    fun activityAt(date: Double): Now? {
        val s = state ?: return null
        val t = s.halfLife ?: return null
        val dt = date - referenceDate
        val a = RadioactiveDecay.activity(activity, dt, t)
        val uT = s.halfLifeUncertainty?.let { RadioactiveDecay.relativeActivityUncertainty(dt, t, it) } ?: 0.0
        return Now(a, sqrt(relativeUncertainty * relativeUncertainty + uT * uT), dt)
    }
}

/** Air kerma from photon emitters: K̇ = A Σ Iᵢ Eᵢ (μ_en/ρ)ᵢ / (4πr²), unshielded point source. Port of NucPhysKit.AirKerma. */
object AirKerma {
    /** NIST mass energy-absorption coefficients of dry air (Hubbell & Seltzer), MeV → cm²/g. */
    private val table = listOf(
        0.010 to 4.742, 0.015 to 1.334, 0.020 to 0.5389, 0.030 to 0.1537, 0.040 to 0.06833, 0.050 to 0.04098,
        0.060 to 0.03041, 0.080 to 0.02407, 0.100 to 0.02325, 0.150 to 0.02496, 0.200 to 0.02672, 0.300 to 0.02872,
        0.400 to 0.02949, 0.500 to 0.02966, 0.600 to 0.02953, 0.800 to 0.02882, 1.000 to 0.02789, 1.250 to 0.02666,
        1.500 to 0.02547, 2.000 to 0.02345, 3.000 to 0.02057, 4.000 to 0.01870, 5.000 to 0.01740, 6.000 to 0.01647,
        8.000 to 0.01525, 10.00 to 0.01450,
    )

    /** μ_en/ρ of air at `keV`, cm²/g (log–log interpolation, clamped to 10 keV–10 MeV). */
    fun massEnergyAbsorption(keV: Double): Double {
        val e = min(max(keV / 1000, table.first().first), table.last().first)
        val i = table.indexOfFirst { it.first >= e }
        if (i <= 0) return table.first().second
        val (e0, m0) = table[i - 1]; val (e1, m1) = table[i]
        val t = ln(e / e0) / ln(e1 / e0)
        return exp(ln(m0) + t * (ln(m1) - ln(m0)))
    }

    /** Air-kerma rate constant, µGy m² MBq⁻¹ h⁻¹, from photons above `cutoff` keV. */
    fun rateConstant(lines: List<EmissionLine>, cutoff: Double = 20.0): Double {
        val sum = lines.filter { it.energy >= cutoff }.fold(0.0) { acc, l -> acc + l.intensity / 100 * l.energy * massEnergyAbsorption(l.energy) }
        val gyPerDecay = sum * 1.602_176_634e-16 * 1000 / (4 * PI * 1e4)
        return gyPerDecay * 1e6 * 3600 * 1e6
    }

    /** Air-kerma rate, µGy/h, of `activity` Bq at `distance` m. */
    fun rate(lines: List<EmissionLine>, activity: Double, distance: Double, cutoff: Double = 20.0): Double =
        rateConstant(lines, cutoff) * activity / 1e6 / (distance * distance)
}
